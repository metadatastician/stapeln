-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Signature Chain Verification Proofs
--
-- Properties of Ed25519 signature chains for multi-party bundle signing.
--
-- HONESTY POLICY:
--   - NO cast Refl (banned pattern — equivalent to believe_me)
--   - NO believe_me, assert_total, or unsafePerformIO
--   - Postulates document their cryptographic justification
--   - Properties provable from definitions are proven structurally

module SignatureProofs

import Data.Vect
import Data.List
import CryptoProofs

%default total

-- ============================================================================
-- Cast Instance (needed for proof reduction of `cast hash` in verifyChain)
-- ============================================================================

export
Cast (Vect n Bits8) (List Bits8) where
  cast = toList

-- ============================================================================
-- Data Types
-- ============================================================================

||| A signed bundle with metadata
public export
record SignedBundle where
  constructor MkSignedBundle
  bundleHash : SHA256Hash
  signatures : List Ed25519Signature
  publicKeys : List Ed25519PublicKey
  timestamp : Nat  -- Unix timestamp

-- ============================================================================
-- Postulated Signature Properties
-- ============================================================================

||| POSTULATE: Signature Non-Replayability
|||
||| A valid signature for bundle1 cannot verify for bundle2 when
||| the bundles have different hashes.
|||
||| Justification: Ed25519 signs over the full message (which includes
||| the bundle hash). If two bundles have different hashes, they
||| constitute different messages. Ed25519 existential unforgeability
||| under chosen-message attack (EUF-CMA) guarantees that a signature
||| valid for one message is not valid for a different message, except
||| with negligible probability (2^-128).
|||
||| Cannot be proven in Idris2: requires reduction to the discrete
||| log problem on Curve25519, which involves modular arithmetic
||| over a 255-bit prime field.
partial
export
signatureNonReplayable : (bundle1 : SignedBundle)
                      -> (bundle2 : SignedBundle)
                      -> (sig : Ed25519Signature)
                      -> (pk : Ed25519PublicKey)
                      -> Not (bundleHash bundle1 = bundleHash bundle2)
                      -> verifyEd25519 pk (cast $ bundleHash bundle1) sig = True
                      -> verifyEd25519 pk (cast $ bundleHash bundle2) sig = False
signatureNonReplayable _ _ _ _ _ _ = idris_crash "signatureNonReplayable: cryptographic postulate — type-level use only"

||| POSTULATE: Signature Non-Malleability
|||
||| An attacker cannot modify a valid signature to produce another
||| valid signature without knowledge of the private key.
|||
||| Justification: Ed25519 is non-malleable by construction (unlike
||| ECDSA). The signature format uses cofactored verification which
||| prevents the small-subgroup attacks that cause malleability in
||| other EdDSA variants. See RFC 8032 Section 8.
partial
export
signatureNonMalleable : (pk : Ed25519PublicKey)
                     -> (msg : Message)
                     -> (sig1 : Ed25519Signature)
                     -> (sig2 : Ed25519Signature)
                     -> verifyEd25519 pk msg sig1 = True
                     -> verifyEd25519 pk msg sig2 = True
                     -> sig1 = sig2
signatureNonMalleable _ _ _ _ _ _ = idris_crash "signatureNonMalleable: cryptographic postulate — type-level use only"

-- ============================================================================
-- Signature Chain Verification
-- ============================================================================

||| A signature chain is a list of (publicKey, signature) pairs
public export
SignatureChain : Type
SignatureChain = List (Ed25519PublicKey, Ed25519Signature)

||| Verify that all signatures in a chain are valid for a given bundle hash.
|||
||| Each signature in the chain is independently verified against the
||| bundle hash. The chain is valid if and only if every signature verifies.
|||
||| Marked `partial` because it transitively calls `verifyEd25519` — a
||| `partial`+`idris_crash` spec stub whose runtime implementation lives
||| in CryptoFFI.verifyEd25519IO. Idris2 0.8 has no native `postulate`
||| keyword, so partiality propagates through any caller of the spec
||| function. Using this chain at runtime would crash; the chain exists
||| only to state proof obligations at the type level.
||| Verify one (publicKey, signature) pair against the bundle hash.
||| Partiality is isolated here (the `verifyEd25519` spec stub); all
||| structural recursion now lives in the total `allValid` / `map`.
partial
public export
verifyPair : SHA256Hash -> (Ed25519PublicKey, Ed25519Signature) -> Bool
verifyPair hash (pk, sig) = verifyEd25519 pk (cast hash) sig

||| Conjunction over a Bool list. Total and structural, so it reduces
||| in conversion checking even when its elements are opaque.
public export
allValid : List Bool -> Bool
allValid []        = True
allValid (b :: bs) = b && allValid bs

||| Verify that all signatures in a chain are valid for a given bundle
||| hash. Refactored 2026-05-18 from an `if`-recursive definition to a
||| NON-RECURSIVE alias `allValid . map verifyPair`. The old form could
||| not be unfolded in conversion (recursive + `partial`), which forced
||| `chainCommutative` to be postulated. With recursion moved into the
||| total `allValid`/`map`, `verifyChain h chain` reduces structurally
||| on a concrete chain (the opaque `verifyEd25519` results stay as
||| `&&` operands), so order-independence is now provable.
|||
||| Still `partial` because `verifyPair` transitively calls the
||| `verifyEd25519` spec stub; runtime impl is CryptoFFI.verifyEd25519IO.
partial
export
verifyChain : SHA256Hash -> SignatureChain -> Bool
verifyChain hash chain = allValid (map (verifyPair hash) chain)

-- ============================================================================
-- Chain Decomposition Helpers (proven by with-block on opaque verifyEd25519)
-- ============================================================================

||| If a chain verifies, the head element's signature is valid.
||| Proven by case-splitting on verifyEd25519's Bool result: if False,
||| the chain returns False, contradicting the True premise.
|||
||| Marked `partial` because it calls the partial spec `verifyEd25519`.
||| The proof content is structural; only the symbol itself inherits
||| partiality from the spec stub.
partial
export
chainHeadValid : (hash : SHA256Hash)
              -> (pk : Ed25519PublicKey)
              -> (sig : Ed25519Signature)
              -> (rest : SignatureChain)
              -> verifyChain hash ((pk, sig) :: rest) = True
              -> verifyEd25519 pk (cast hash) sig = True
chainHeadValid hash pk sig rest prf with (verifyEd25519 pk (cast hash) sig)
  chainHeadValid hash pk sig rest prf | True = Refl
  chainHeadValid hash pk sig rest prf | False = absurd prf

||| If a chain verifies, the tail also verifies.
||| Same proof strategy as chainHeadValid.
partial
export
chainTailValid : (hash : SHA256Hash)
              -> (pk : Ed25519PublicKey)
              -> (sig : Ed25519Signature)
              -> (rest : SignatureChain)
              -> verifyChain hash ((pk, sig) :: rest) = True
              -> verifyChain hash rest = True
chainTailValid hash pk sig rest prf with (verifyEd25519 pk (cast hash) sig)
  chainTailValid hash pk sig rest prf | True = prf
  chainTailValid hash pk sig rest prf | False = absurd prf

-- ============================================================================
-- Propositional Membership (replaces boolean elem for proof purposes)
-- ============================================================================

||| Type-level proof that an element is in a list.
||| Unlike boolean `elem` (which uses ==), this carries propositional
||| equality, enabling substitution in proof goals.
public export
data IsElem : a -> List a -> Type where
  ||| The element is at the head of the list.
  Here : IsElem x (x :: xs)
  ||| The element is somewhere in the tail.
  There : IsElem x xs -> IsElem x (y :: xs)

||| The empty list contains no elements.
export
Uninhabited (IsElem x []) where
  uninhabited Here impossible
  uninhabited (There _) impossible

-- ============================================================================
-- Structural Proofs (all proven from definitions)
-- ============================================================================

||| PROVEN: Chain Implies Individual
|||
||| If a signature chain is valid, then each individual signature
||| in the chain is valid.
|||
||| Proof: By induction on the IsElem membership proof.
|||   - Here: (pk, sig) is the head → delegate to chainHeadValid.
|||   - There: (pk, sig) is in the tail → extract tail validity via
|||     chainTailValid, then recurse.
|||
||| Previously postulated because boolean `elem` uses `==` (Bool Eq)
||| which doesn't give propositional equality. Solved by defining
||| IsElem as a type-level membership proof carrying `=`.
|||
||| Partial because downstream of `verifyEd25519` / `verifyChain` stubs.
partial
export
chainImpliesIndividual
  : (hash : SHA256Hash)
  -> (chain : SignatureChain)
  -> verifyChain hash chain = True
  -> (pk : Ed25519PublicKey)
  -> (sig : Ed25519Signature)
  -> IsElem (pk, sig) chain
  -> verifyEd25519 pk (cast hash) sig = True
chainImpliesIndividual hash [] _ _ _ inChain = absurd inChain
chainImpliesIndividual hash ((pk, sig) :: rest) chainPrf pk sig Here =
  chainHeadValid hash pk sig rest chainPrf
chainImpliesIndividual hash ((pk', sig') :: rest) chainPrf pk sig (There later) =
  chainImpliesIndividual hash rest (chainTailValid hash pk' sig' rest chainPrf) pk sig later

||| PROVEN: Chain Extension
|||
||| Adding a valid signature to a valid chain preserves validity.
|||
||| Proof: rewrite with validSig substitutes True for the if-condition,
||| reducing the if-then-else to `verifyChain hash chain`, which equals
||| True by validChain. Previously postulated because the approach of
||| case-splitting on the opaque verifyEd25519 was tried instead of
||| rewriting with the equality premise.
|||
||| Partial because downstream of `verifyEd25519` / `verifyChain` stubs.
partial
export
chainExtension
  : (hash : SHA256Hash)
  -> (chain : SignatureChain)
  -> (pk : Ed25519PublicKey)
  -> (sig : Ed25519Signature)
  -> verifyChain hash chain = True
  -> verifyEd25519 pk (cast hash) sig = True
  -> verifyChain hash ((pk, sig) :: chain) = True
chainExtension hash chain pk sig validChain validSig =
  rewrite validSig in validChain

||| PROVEN: Chain Commutativity (2026-05-18, no longer postulated)
|||
||| Signature verification order doesn't matter — verifying [A, B]
||| gives the same result as verifying [B, A].
|||
||| Enabled by the `verifyChain = allValid . map verifyPair` refactor:
||| `verifyChain h [a,b]` now reduces structurally (total `allValid`/
||| `map`) to `vA && (vB && True)` with the opaque `verifyEd25519`
||| results as `&&` operands. Order-independence is then the pure Bool
||| identity `a && (b && True) = b && (a && True)`, proven by the total
||| 4-case `boolCommTrue`. No `verifyChain` recursion is unfolded by the
||| proof, so chainHeadValid/chainTailValid/chainImpliesIndividual are
||| untouched. `partial` retained only because the type mentions
||| `verifyChain` (spec-stub lineage); the proof term is total.
partial
export
chainCommutative
  : (hash : SHA256Hash)
  -> (pk1 : Ed25519PublicKey)
  -> (sig1 : Ed25519Signature)
  -> (pk2 : Ed25519PublicKey)
  -> (sig2 : Ed25519Signature)
  -> verifyChain hash [(pk1, sig1), (pk2, sig2)]
   = verifyChain hash [(pk2, sig2), (pk1, sig1)]
chainCommutative hash pk1 sig1 pk2 sig2 =
  boolCommTrue (verifyEd25519 pk1 (cast hash) sig1)
               (verifyEd25519 pk2 (cast hash) sig2)
  where
    boolCommTrue : (a, b : Bool) -> a && (b && True) = b && (a && True)
    boolCommTrue True  True  = Refl
    boolCommTrue True  False = Refl
    boolCommTrue False True  = Refl
    boolCommTrue False False = Refl
