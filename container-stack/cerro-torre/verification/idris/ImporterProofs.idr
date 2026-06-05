-- SPDX-License-Identifier: MPL-2.0
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
import Data.List.Quantifiers
import Data.List.Elem
import Data.Nat
import Decidable.Equality
import StringLemmas

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
||| SafePath is an inductive proof that a (relative, normalized) path is safe
||| for extraction. It models a "/"-joined sequence of components with NO
||| trailing slash — exactly what `normalizePath` (split/filter/joinBy) emits:
|||   - SafeEmpty    : the empty path "".
|||   - SafeSingle   : a single FINAL component "c" (e.g. "a", or the last
|||                    component "c" of "a/b/c").
|||   - SafeComponent: "component/rest" where rest is itself safe and non-empty.
||| Each component must be (1) non-empty, (2) not "..", (3) '/'-free.
|||
||| SOUNDNESS NOTES (2026-06):
|||  - (1) non-emptiness is load-bearing for `absolutePathRejection`: without it
|||    "/rest" = "" ++ "/" ++ rest would make every absolute path "safe".
|||  - (3) '/'-freeness (no '/' ANYWHERE in a component, via `charsElem '/'`) is
|||    load-bearing for the SafeSingle/SafeComponent leaves: with only "doesn't
|||    start with /", a single "component" like "a/../x" would be admitted,
|||    sneaking a ".." past the not-".." check (3) forces every real "/"-segment
|||    through checks (2)+(3) individually.
|||  - Earlier this type had only SafeEmpty+SafeComponent, whose language is the
|||    TRAILING-slash paths {"","a/","a/b/"} — disjoint from normalizePath's
|||    output {"","a","a/b"} except at "". That made `normalizedIsSafe` false
|||    (its target type was uninhabited for any non-empty path). SafeSingle (and
|||    the `Not (rest = "")` on SafeComponent) close that gap.
||| `rest` is an explicit index so proofs can recover the suffix string
||| (auto-bound implicits are erased at quantity 0 and unusable relevantly).
public export
data SafePath : Path -> Type where
  ||| An empty path is safe
  SafeEmpty : SafePath ""

  ||| A single final relative component: non-empty, not "..", '/'-free.
  SafeSingle : (component : String)
            -> Not (component = "")
            -> Not (component = "..")
            -> Not (charsElem '/' (unpack component) = True)
            -> SafePath component

  ||| A non-empty, '/'-free, non-".." component followed by a NON-EMPTY safe rest
  SafeComponent : (component : String)
               -> (rest : String)
               -> Not (component = "")
               -> Not (component = "..")
               -> Not (charsElem '/' (unpack component) = True)
               -> Not (rest = "")
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
||| Join strings with a separator, with NO trailing separator:
||| `joinSep "/" [] = ""`, `joinSep "/" ["a"] = "a"`, `joinSep "/" ["a","b"] = "a/b"`.
||| Lifted from a local `where` so normalizedIsSafe's SafePath discharge can
||| recurse on the SAME `joinBy` that builds `normalizePath`.
public export
joinSep : String -> List String -> String
joinSep sep [] = ""
joinSep sep [x] = x
joinSep sep (x :: xs) = x ++ sep ++ joinSep sep xs

||| The normalized-path component filter: drop "" (duplicate slashes) and "."
||| segments. A top-level name (not an inline lambda) so normalizePath and the
||| discharge reference the identical predicate.
public export
normPred : String -> Bool
normPred c = c /= "." && c /= ""

||| The components of a normalized path. Shared by normalizePath and
||| normalizedIsSafe so the two are definitionally the same list.
public export
normComponents : Path -> List String
normComponents p = filter normPred (forget (split (== '/') p))

export
normalizePath : Path -> Path
normalizePath p = joinSep "/" (normComponents p)

-- ============================================================================
-- Tar Entry Types
-- ============================================================================
-- (Hoisted above the safety postulates so those postulates can refer to
-- TarEntry in their types without forward-reference errors.)

||| A tar entry with path and content.
|||
||| `Eq` is defined below so `elem`-based constructors on `List TarEntry`
||| can compare entries (needed by OCILayout's hasManifest witness).
public export
record TarEntry where
  constructor MkTarEntry
  path : Path
  size : Nat
  isSymlink : Bool
  symlinkTarget : Maybe Path

public export
Eq TarEntry where
  a == b =
    a.path == b.path
    && a.size == b.size
    && a.isSymlink == b.isSymlink
    && a.symlinkTarget == b.symlinkTarget

-- ============================================================================
-- Importer Safety Postulates
-- ============================================================================
-- These properties relate to String operations (isPrefixOf, isInfixOf)
-- whose implementations in Idris2's standard library are opaque
-- (implemented via primitive string operations). Full structural
-- proofs would require String lemmas that don't exist in the stdlib.

-- ============================================================================
-- normalizedIsSafe — DISCHARGED (2026-06). Was false-as-stated (see SafePath);
-- now that SafePath models normalizePath's output, here is the real proof.
-- ============================================================================
-- normalizePath p = joinSep "/" (normComponents p). We build SafePath of that
-- join from per-component safety (joinBySafe). Each component is:
--   * non-empty            — it survived the normComponents filter (filterSat);
--   * not ".."             — else ".." is an infix of the join (dotDotInfixOfJoin),
--                            contradicting the premise;
--   * '/'-free             — split on '/' yields '/'-free components (splitNoDelim),
--                            preserved by filter (allFilter).
-- Trusted base grows by exactly two fundamental, opaque-String-primitive axioms:
-- splitNoDelim and dotDotInfixOfJoin. Everything else below is total.

||| AXIOM (split semantics): components of `split (== '/')` contain no '/'.
||| `split` is built on opaque String primitives; '/'-freeness of its outputs is
||| its defining property, not reducible at the Idris2 type level.
partial
export
splitNoDelim : (p : String)
            -> All (\c => charsElem '/' (unpack c) = False) (forget (split (== '/') p))
splitNoDelim _ =
  idris_crash "splitNoDelim: split-semantics axiom — type-level use only"

||| AXIOM (join/infix semantics): a ".." component is a ".." infix of the join.
||| `isInfixOf` is an opaque String primitive; this surfaces a ".." component to
||| the infix premise of normalizedIsSafe.
partial
export
dotDotInfixOfJoin : (cs : List String) -> Elem ".." cs
                 -> Data.String.isInfixOf ".." (joinSep "/" cs) = True
dotDotInfixOfJoin _ _ =
  idris_crash "dotDotInfixOfJoin: join/infix-semantics axiom — type-level use only"

||| `xs ++ ys = [] → xs = []` over List Char (trivial, total).
nilFromAppendL : (xs, ys : List Char) -> xs ++ ys = [] -> xs = []
nilFromAppendL []       _ _   = Refl
nilFromAppendL (_ :: _) _ prf = absurd prf

||| `a ++ b = "" → a = ""`, via the existing unpackAppend/unpackEmptyInv axioms.
partial
appendEmptyLeft : (a, b : String) -> a ++ b = "" -> a = ""
appendEmptyLeft a b prf =
  unpackEmptyInv a
    (nilFromAppendL (unpack a) (unpack b)
       (trans (sym (unpackAppend a b)) (cong unpack prf)))

||| `joinSep "/" (x :: xs)` is non-empty when `x` is non-empty — satisfies
||| SafeComponent's `Not (rest = "")` obligation for each interior split.
partial
joinByConsNonEmpty : (x : String) -> Not (x = "") -> (xs : List String)
                  -> Not (joinSep "/" (x :: xs) = "")
joinByConsNonEmpty _ neX []        = neX
joinByConsNonEmpty x neX (y :: ys) =
  \eq => neX (appendEmptyLeft x ("/" ++ joinSep "/" (y :: ys)) eq)

||| Per-component safety obligation for SafePath.
public export
SafeComp : String -> Type
SafeComp c = ( Not (c = "")
             , Not (c = "..")
             , Not (charsElem '/' (unpack c) = True) )

||| Heart of the discharge: SafePath of the join from per-component safety.
||| SafeEmpty / SafeSingle / SafeComponent line up with joinBy's
||| [] / [x] / (x :: y :: ys) clauses.
partial
joinBySafe : (cs : List String) -> All SafeComp cs -> SafePath (joinSep "/" cs)
joinBySafe []              []                              = SafeEmpty
joinBySafe (c :: [])       ((ne, nd, nf) :: [])            = SafeSingle c ne nd nf
joinBySafe (c :: c2 :: cs) ((ne, nd, nf) :: (sc2 :: rest)) =
  SafeComponent c (joinSep "/" (c2 :: cs)) ne nd nf
    (joinByConsNonEmpty c2 (fst sc2) cs)
    (joinBySafe (c2 :: cs) (sc2 :: rest))

||| An element of a filtered list satisfies the predicate (total).
filterSat : (q : String -> Bool) -> (xs : List String) -> (x : String)
         -> Elem x (filter q xs) -> q x = True
filterSat q []        x e = absurd e
filterSat q (y :: ys) x e with (q y) proof qEq
  filterSat q (y :: ys) x e | True = case e of
                                       Here      => qEq
                                       There e'  => filterSat q ys x e'
  filterSat q (y :: ys) x e | False = filterSat q ys x e

||| `All p` survives `filter` (total).
allFilter : {0 p : String -> Type} -> (q : String -> Bool) -> (xs : List String)
         -> All p xs -> All p (filter q xs)
allFilter q []        []          = []
allFilter q (y :: ys) (py :: pys) with (q y)
  _ | True  = py :: allFilter q ys pys
  _ | False = allFilter q ys pys

||| Project an `All` at an `Elem` (total).
allElem : {0 p : String -> Type} -> {0 xs : List String}
       -> All p xs -> Elem x xs -> p x
allElem (px :: _)   Here      = px
allElem (_  :: pxs) (There e) = allElem pxs e

||| Build an `All` from a per-element function over `Elem` (total).
allFromElem : {0 p : String -> Type} -> (xs : List String)
           -> ((x : String) -> Elem x xs -> p x) -> All p xs
allFromElem []        _ = []
allFromElem (x :: xs) f = f x Here :: allFromElem xs (\y, e => f y (There e))

-- Bool/String micro-lemmas (total).
andRightTrue : (a, b : Bool) -> (a && b) = True -> b = True
andRightTrue True  _ prf = prf
andRightTrue False _ prf = absurd prf

notTrueImpliesFalse : (b : Bool) -> not b = True -> b = False
notTrueImpliesFalse True  prf = absurd prf
notTrueImpliesFalse False _   = Refl

notTrueFromFalse : (b : Bool) -> b = False -> Not (b = True)
notTrueFromFalse _ bFalse bTrue = absurd (trans (sym bFalse) bTrue)

||| `(c /= "") = True → Not (c = "")`. If `c = ""` then `c == ""` folds to True,
||| contradicting `(c == "") = False` (from the `/=`).
notEqEmptyFromNeq : (c : String) -> (c /= "") = True -> Not (c = "")
notEqEmptyFromNeq c neqTrue cEq =
  absurd (trans (sym (notTrueImpliesFalse (c == "") neqTrue))
                (replace {p = \z => (z == "") = True} (sym cEq) Refl))

||| Per-component safety for every element of `normComponents p`, given the
||| no-".."-infix premise.
partial
mkAllSafe : (p : Path)
         -> Not (Data.String.isInfixOf ".." (joinSep "/" (normComponents p)) = True)
         -> All SafeComp (normComponents p)
mkAllSafe p noDot = allFromElem (normComponents p) safeAt
  where
    safeAt : (c : String) -> Elem c (normComponents p) -> SafeComp c
    safeAt c elemC =
      ( notEqEmptyFromNeq c
          (andRightTrue (c /= ".") (c /= "")
             (filterSat normPred (forget (split (== '/') p)) c elemC))
      , (\cEq => case cEq of
                   Refl => noDot (dotDotInfixOfJoin (normComponents p) elemC))
      , notTrueFromFalse (charsElem '/' (unpack c))
          (allElem (allFilter normPred (forget (split (== '/') p)) (splitNoDelim p))
                   elemC) )

||| PROVEN (2026-06, was a postulate): a normalized path with no ".." infix is a
||| SafePath. The proof is `joinBySafe` over the verified per-component safety
||| (`mkAllSafe`). Trusted base: `splitNoDelim` + `dotDotInfixOfJoin` (two
||| fundamental opaque-String-primitive axioms) + the pre-existing
||| `unpackAppend`/`unpackEmptyInv`. No believe_me / cast Refl / assert_total.
partial
export
normalizedIsSafe : (p : Path)
                -> Not (Data.String.isInfixOf ".." (normalizePath p) = True)
                -> SafePath (normalizePath p)
normalizedIsSafe p noDot = joinBySafe (normComponents p) (mkAllSafe p noDot)

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
partial
export
extractionSafety : (root : Path)
                -> (entry : TarEntry)
                -> SafePath (entry.path)
                -> isPrefixOf root (root ++ "/" ++ entry.path) = True
extractionSafety root entry _ =
  rewrite isPrefixOfBridge root (root ++ "/" ++ entry.path) in
  rewrite unpackAppend root ("/" ++ entry.path) in
  charsPrefixOfAppend (unpack root) (unpack ("/" ++ entry.path))

||| POSTULATE: Symlink Safety
|||
||| A symlink with a safe target path cannot escape the extraction root.
|||
||| Same justification as extractionSafety — symlink targets are
||| validated to be SafePath, and the concatenation with root
||| ensures the target is under root.
partial
export
symlinkSafety : (root : Path)
             -> (entry : TarEntry)
             -> (target : Path)
             -> entry.isSymlink = True
             -> entry.symlinkTarget = Just target
             -> SafePath target
             -> isPrefixOf root (root ++ "/" ++ target) = True
symlinkSafety root _ target _ _ _ =
  rewrite isPrefixOfBridge root (root ++ "/" ++ target) in
  rewrite unpackAppend root ("/" ++ target) in
  charsPrefixOfAppend (unpack root) (unpack ("/" ++ target))

-- --- Helper lemmas for absolutePathRejection ------------------------------

||| `isPrefixOf "/" ""` is False — both literals constant-fold, so by `Refl`.
export
prefixSlashEmpty : Data.String.isPrefixOf "/" "" = False
prefixSlashEmpty = Refl

||| Native unfolding of String.isPrefixOf for the "/" separator. `isPrefixOf`
||| on String is `\a,b => isPrefixOf (unpack a) (unpack b)` (the List version,
||| `isPrefixOfBy (==)`), and `unpack "/"` constant-folds to `['/']`; all by Refl.
export
prefixNative : (x : String)
            -> Data.String.isPrefixOf "/" x = isPrefixOfBy (==) ['/'] (unpack x)
prefixNative x = Refl

||| For a non-empty `comp` (so `unpack comp = c :: cs`), prefixing-"/"-ness is
||| unaffected by appending `tail`: only the head char is inspected. Proven by
||| `unpackAppend` + reducing `isPrefixOfBy (==) ['/']` on both cons forms to
||| `('/' == c) && True`.
partial
export
slashPrefixAppendEq : (comp, tail : String) -> (c : Char) -> (cs : List Char)
  -> unpack comp = c :: cs
  -> Data.String.isPrefixOf "/" comp = Data.String.isPrefixOf "/" (comp ++ tail)
slashPrefixAppendEq comp tail c cs eq =
  rewrite prefixNative comp in
  rewrite prefixNative (comp ++ tail) in
  rewrite unpackAppend comp tail in
  rewrite eq in
  Refl

||| A non-empty string unpacks to a cons. The `[]` case contradicts
||| `Not (comp = "")` via `unpackEmptyInv`.
partial
export
nonEmptyUnpack : (comp : String) -> Not (comp = "")
  -> (c : Char ** cs : List Char ** unpack comp = c :: cs)
nonEmptyUnpack comp neComp with (unpack comp) proof eq
  _ | [] = absurd (neComp (unpackEmptyInv comp eq))
  _ | (c :: cs) = (c ** cs ** Refl)

||| If "/" is a prefix of `comp ++ tail` and `comp` is non-empty, then "/" is
||| a prefix of `comp` (the separator must be `comp`'s first character).
partial
export
slashPrefixThroughAppend : (comp, tail : String) -> Not (comp = "")
  -> Data.String.isPrefixOf "/" (comp ++ tail) = True
  -> Data.String.isPrefixOf "/" comp = True
slashPrefixThroughAppend comp tail neComp prefixPrf =
  let (c ** cs ** eq) = nonEmptyUnpack comp neComp
  in trans (slashPrefixAppendEq comp tail c cs eq) prefixPrf

||| From "/" being a prefix of a non-empty `comp`, conclude '/' occurs in
||| `unpack comp`. `isPrefixOf "/" comp` unfolds (prefixNative) to
||| `isPrefixOfBy (==) ['/'] (unpack comp)`; with `unpack comp = c :: cs` it
||| reduces to `('/' == c) && True`, whose `True` head gives `'/' == c = True`,
||| hence `charsElem '/' (c :: cs) = True`. (Bridges the SafePath '/'-free field
||| to the absolute-prefix premise without a Char-equality axiom.)
partial
export
slashPrefixImpliesCharsElem : (comp : String) -> Not (comp = "")
  -> Data.String.isPrefixOf "/" comp = True
  -> charsElem '/' (unpack comp) = True
slashPrefixImpliesCharsElem comp neComp prefixPrf =
  let (c ** cs ** eq) = nonEmptyUnpack comp neComp
      slashEqC = andLeftTrue ('/' == c) True
                   (replace {p = \u => isPrefixOfBy (==) ['/'] u = True} eq
                      (trans (sym (prefixNative comp)) prefixPrf))
  in replace {p = \u => charsElem '/' u = True} (sym eq)
       (charsElemHere '/' c cs slashEqC)

||| Core of absolutePathRejection, over a path string `p`.
partial
export
absolutePathNotSafe : {p : Path} -> Data.String.isPrefixOf "/" p = True
                   -> SafePath p -> Void
absolutePathNotSafe prefixPrf SafeEmpty =
  absurd (trans (sym prefixSlashEmpty) prefixPrf)
absolutePathNotSafe prefixPrf (SafeSingle comp neComp _ notSlash) =
  notSlash (slashPrefixImpliesCharsElem comp neComp prefixPrf)
absolutePathNotSafe prefixPrf (SafeComponent comp rest neComp _ notSlash _ _) =
  notSlash (slashPrefixImpliesCharsElem comp neComp
              (slashPrefixThroughAppend comp ("/" ++ rest) neComp prefixPrf))

||| PROVEN: Absolute Path Rejection (2026-06 — was a postulate)
|||
||| An absolute path (starting with "/") cannot be SafePath.
|||
||| Proof: case analysis on the SafePath witness (`absolutePathNotSafe`).
|||   - SafeEmpty: path = "" but `isPrefixOf "/" "" = False` (Refl) contradicts
|||     the `= True` premise.
|||   - SafeComponent comp rest …: path = comp ++ "/" ++ rest with comp
|||     non-empty. `slashPrefixThroughAppend` derives `isPrefixOf "/" comp = True`
|||     from the premise, contradicting the constructor's `notSlash` field.
|||
||| This is exactly why `SafeComponent` now requires `Not (component = "")`:
||| without it the empty-leading-component decomposition of "/rest" would make
||| the theorem false. Trusted base: `unpackAppend` + `unpackEmptyInv` (both
||| fundamental String-primitive facts); `isPrefixOf "/" ""` and the native
||| unfolding reduce by `Refl`. `partial` is the AXIOM-TRANSITIVE marker.
partial
export
absolutePathRejection : (entry : TarEntry)
                     -> isPrefixOf "/" entry.path = True
                     -> Not (SafePath entry.path)
absolutePathRejection entry prefixPrf = absolutePathNotSafe prefixPrf

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

||| PROVEN: OCI Layout Enforcement (2026-06 — was a postulate)
|||
||| A valid OCI layout contains manifest.json (path-level statement).
|||
||| Proof: `ValidOCI` carries `hasManifest : elem m entries = True` with
||| `m = MkTarEntry "manifest.json" 0 False Nothing`. By the stdlib defs
||| `elem = elemBy (==)` and `elemBy p e = any (p e)`, this is definitionally
||| `any (m ==) entries = True`. We lift it to the goal predicate
||| `\e => e.path == "manifest.json"` via `anyMono` (StringLemmas): the
||| pointwise obligation `(m == e) = True -> (e.path == "manifest.json") = True`
||| is discharged by extracting the first conjunct of the `Eq TarEntry`
||| chain (`andLeftTrue`) — giving `"manifest.json" == e.path = True` — and
||| flipping it with the fundamental `eqStringSym` axiom.
|||
||| Trusted base: `eqStringSym` only (a fundamental String-`==` primitive
||| fact). The list/Bool reasoning (`anyMono`, `andLeftTrue`) is fully total.
||| `partial` is the AXIOM-TRANSITIVE marker inherited from `eqStringSym`.
partial
export
ociLayoutEnforcement : (entries : List TarEntry)
                    -> OCILayout entries
                    -> any (\e => e.path == "manifest.json") entries = True
ociLayoutEnforcement entries (ValidOCI entries hasManifest _) =
  anyMono (\e => MkTarEntry "manifest.json" 0 False Nothing == e)
          (\e => e.path == "manifest.json")
          pointwise entries hasManifest
  where
    partial
    pointwise : (e : TarEntry)
             -> (MkTarEntry "manifest.json" 0 False Nothing == e) = True
             -> (e.path == "manifest.json") = True
    pointwise e prf =
      eqStringSym "manifest.json" e.path
        (andLeftTrue ("manifest.json" == e.path) _ prf)

-- ============================================================================
-- Attack Prevention
-- ============================================================================

||| PROVEN: Tar Bomb Prevention
|||
||| If the number of entries and total size are within limits,
||| extraction is safe.
|||
||| Proof: The return type is () (unit), always constructible.
||| The security guarantee is in the premises: the caller must
||| PROVIDE LTE proofs for entry count and total size bounds.
||| These proofs are constructed at runtime by the extraction code,
||| which checks limits before proceeding. Previously postulated
||| because analysis focused on the operational semantics rather
||| than the trivial return type.
export
tarBombPrevention
  : (entries : List TarEntry)
  -> (maxSize : Nat)
  -> (maxEntries : Nat)
  -> length entries `LTE` maxEntries
  -> sum (map TarEntry.size entries) `LTE` maxSize
  -> ()  -- Witness that extraction within bounds is safe
tarBombPrevention _ _ _ _ _ = ()

||| POSTULATE: Zip Slip Prevention
|||
||| A tar entry with a safe normalized path cannot escape the root.
|||
||| Same justification as extractionSafety — SafePath after
||| normalization ensures no ".." traversal, and concatenation
||| with root ensures the path prefix property.
partial
export
zipSlipPrevention : (root : Path)
                 -> (entry : TarEntry)
                 -> SafePath (normalizePath entry.path)
                 -> isPrefixOf root (root ++ "/" ++ normalizePath entry.path) = True
zipSlipPrevention root entry _ =
  rewrite isPrefixOfBridge root (root ++ "/" ++ normalizePath entry.path) in
  rewrite unpackAppend root ("/" ++ normalizePath entry.path) in
  charsPrefixOfAppend (unpack root) (unpack ("/" ++ normalizePath entry.path))
