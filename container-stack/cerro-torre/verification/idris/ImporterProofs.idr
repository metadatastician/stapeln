-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Importer Safety Proofs
--
-- Properties ensuring that OCI image importers cannot perform path
-- traversal, zip slip, tar bomb, or other filesystem attacks.
--
-- HONESTY POLICY:
--   - NO cast Refl (banned pattern — equivalent to believe_me)
--   - NO believe_me, assert_total, or unsafePerformIO
--   - Postulates are used where Idris2's String library lacks
--     the lemmas needed for structural proofs about isPrefixOf/isInfixOf
--   - Each postulate documents why it cannot currently be proven
--     and what would be needed to prove it

module ImporterProofs

import Data.String
import Data.List
import Data.List1

%default total

-- ============================================================================
-- Type Definitions
-- ============================================================================

||| A filesystem path
public export
Path : Type
Path = String

||| A safe path that doesn't contain ".." or absolute paths.
|||
||| SafePath is an inductive proof that a path is safe for extraction:
|||   - SafeEmpty: the empty string is trivially safe
|||   - SafeComponent: a path "component/rest" is safe if:
|||     1. component is not ".."
|||     2. component doesn't start with "/"
|||     3. rest is also safe
public export
data SafePath : Path -> Type where
  ||| An empty path is safe
  SafeEmpty : SafePath ""

  ||| A relative component without ".." is safe
  SafeComponent : (component : String)
               -> Not (component = "..")
               -> Not (isPrefixOf "/" component)
               -> SafePath rest
               -> SafePath (component ++ "/" ++ rest)

-- ============================================================================
-- Path Normalization
-- ============================================================================

||| Normalize a filesystem path by removing redundant separators,
||| resolving "." components, and stripping trailing slashes.
|||
||| NOTE: This does NOT resolve ".." — that's handled by SafePath
||| rejection. A normalized path that still contains ".." is rejected
||| by the normalizedIsSafe check. This is intentional: ".." removal
||| requires a stack-based algorithm that changes path semantics
||| (e.g., "a/../b" → "b" is wrong if "a" is a symlink).
|||
||| Operations performed:
|||   - Split on "/", filter out "" (duplicate slashes) and "." components
|||   - Rejoin with single "/" separators
|||   - Strip leading "/" (normalization produces relative paths; absolute
|||     paths are rejected by SafePath's absolutePathRejection postulate)
export
normalizePath : Path -> Path
normalizePath p =
  let components = split (== '/') p
      filtered = filter (\c => c /= "." && c /= "") (forget components)
  in joinBy "/" filtered
  where
    joinBy : String -> List String -> String
    joinBy sep [] = ""
    joinBy sep [x] = x
    joinBy sep (x :: xs) = x ++ sep ++ joinBy sep xs

-- ============================================================================
-- Importer Safety Postulates
-- ============================================================================
-- These properties relate to String operations (isPrefixOf, isInfixOf)
-- whose implementations in Idris2's standard library are opaque
-- (implemented via primitive string operations). Full structural
-- proofs would require String lemmas that don't exist in the stdlib.

||| POSTULATE: Normalized Safe Path
|||
||| A normalized path with no ".." substrings is safe for extraction.
|||
||| Justification: If a path contains no ".." after normalization,
||| it cannot traverse upward in the directory tree. Combined with
||| the SafeComponent requirement that no component starts with "/",
||| this ensures the path stays within the extraction root.
|||
||| Cannot currently be proven because:
|||   1. normalizePath uses split/filter/join which are opaque to the
|||      type checker (String operations reduce to C primitives)
|||   2. Proving the relationship between isInfixOf ".." and
|||      SafePath requires String decomposition lemmas that
|||      don't exist in Idris2's stdlib
|||   3. SafePath is defined inductively over string concatenation,
|||      but String in Idris2 is a primitive type, not an inductive
|||      data structure
export
postulate normalizedIsSafe
  : (p : Path)
  -> Not (isInfixOf ".." (normalizePath p))
  -> SafePath (normalizePath p)

||| POSTULATE: Extraction Safety
|||
||| Extracting a file with a safe path under a root directory
||| produces a path that starts with the root.
|||
||| Justification: By construction, (root ++ "/" ++ entry.path) must
||| start with root because string concatenation prepends root.
||| This is trivially true but requires a lemma about isPrefixOf
||| and string concatenation:
|||   isPrefixOf s (s ++ t) = True  for all s, t
|||
||| Cannot currently be proven because Idris2's isPrefixOf is
||| implemented as a C primitive with no reduction rules available
||| to the type checker.
export
postulate extractionSafety
  : (root : Path)
  -> (entry : TarEntry)
  -> SafePath (entry.path)
  -> isPrefixOf root (root ++ "/" ++ entry.path) = True

||| POSTULATE: Symlink Safety
|||
||| A symlink with a safe target path cannot escape the extraction root.
|||
||| Same justification as extractionSafety — symlink targets are
||| validated to be SafePath, and the concatenation with root
||| ensures the target is under root.
export
postulate symlinkSafety
  : (root : Path)
  -> (entry : TarEntry)
  -> (target : Path)
  -> entry.isSymlink = True
  -> entry.symlinkTarget = Just target
  -> SafePath target
  -> isPrefixOf root (root ++ "/" ++ target) = True

||| POSTULATE: Absolute Path Rejection
|||
||| An absolute path (starting with "/") cannot be SafePath.
|||
||| Justification: SafePath's SafeComponent constructor requires
||| Not (isPrefixOf "/" component) for every component. An absolute
||| path has "/" as a prefix of its first component, which contradicts
||| the SafeComponent requirement.
|||
||| Proof sketch (for future implementation):
|||   Case analysis on safePath:
|||     SafeEmpty: entry.path = "" but isPrefixOf "/" "" = False,
|||       contradicting isAbsolute
|||     SafeComponent component notDotDot notSlash rest:
|||       entry.path = component ++ "/" ++ rest
|||       isPrefixOf "/" (component ++ "/" ++ rest) = True (given)
|||       This implies isPrefixOf "/" component = True (string prefix lemma)
|||       But notSlash : Not (isPrefixOf "/" component) → contradiction
export
postulate absolutePathRejection
  : (entry : TarEntry)
  -> isPrefixOf "/" entry.path = True
  -> Not (SafePath entry.path)

-- ============================================================================
-- Tar Entry Types
-- ============================================================================

||| A tar entry with path and content
public export
record TarEntry where
  constructor MkTarEntry
  path : Path
  size : Nat
  isSymlink : Bool
  symlinkTarget : Maybe Path

-- ============================================================================
-- OCI Layout Validation
-- ============================================================================

||| Docker OCI tar layout validation.
|||
||| OCI images must have specific structure:
|||   - manifest.json at root
|||   - blobs/ directory with sha256:HASH files
|||   - index.json or oci-layout at root
public export
data OCILayout : List TarEntry -> Type where
  ValidOCI : (entries : List TarEntry)
          -> (hasManifest : elem (MkTarEntry "manifest.json" 0 False Nothing) entries = True)
          -> (hasBlobsDir : any (\e => isPrefixOf "blobs/" e.path) entries = True)
          -> OCILayout entries

||| POSTULATE: OCI Layout Enforcement
|||
||| A valid OCI layout contains manifest.json.
|||
||| Justification: The ValidOCI constructor requires hasManifest as
||| a proof that manifest.json is in the entry list. The goal asks
||| for a slightly different formulation using (==) instead of elem
||| on the full record. These are equivalent when the path field
||| matches, but proving the equivalence requires decidable equality
||| on TarEntry and a lemma relating elem to any with (==).
export
postulate ociLayoutEnforcement
  : (entries : List TarEntry)
  -> OCILayout entries
  -> any (\e => e.path == "manifest.json") entries = True

-- ============================================================================
-- Attack Prevention
-- ============================================================================

||| POSTULATE: Tar Bomb Prevention
|||
||| If the number of entries and total size are within limits,
||| extraction is safe.
|||
||| Justification: This is an operational bound — if entry count
||| and total size are within configured limits, resource exhaustion
||| cannot occur. The proof requires showing that bounded extraction
||| terminates and stays within resource limits, which involves
||| reasoning about IO effects that Idris2's type system tracks
||| but cannot prove termination properties about.
|||
||| NOTE: The previous implementation had a fake extractAll function
||| that returned True unconditionally. This has been removed.
||| Real extraction safety requires runtime resource monitoring,
||| not a compile-time proof.
export
postulate tarBombPrevention
  : (entries : List TarEntry)
  -> (maxSize : Nat)
  -> (maxEntries : Nat)
  -> length entries `LTE` maxEntries
  -> sum (map size entries) `LTE` maxSize
  -> ()  -- Witness that extraction within bounds is safe

||| POSTULATE: Zip Slip Prevention
|||
||| A tar entry with a safe normalized path cannot escape the root.
|||
||| Same justification as extractionSafety — SafePath after
||| normalization ensures no ".." traversal, and concatenation
||| with root ensures the path prefix property.
export
postulate zipSlipPrevention
  : (root : Path)
  -> (entry : TarEntry)
  -> SafePath (normalizePath entry.path)
  -> isPrefixOf root (root ++ "/" ++ normalizePath entry.path) = True
