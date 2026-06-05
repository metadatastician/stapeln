-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
--
-- StringLemmas.idr — Provable string operations over List Char
--
-- Idris2's String type uses C primitives (isPrefixOf, isInfixOf) that
-- are opaque to the type checker. This module provides equivalent
-- operations over List Char using DecEq, which ARE provable.
--
-- These lemmas serve as the proven foundation for ImporterProofs.idr.
-- The 6 remaining String postulates in ImporterProofs can be eliminated
-- once a bridge postulate connecting String.isPrefixOf to charsPrefixOf
-- is added (requires proving unpack distributes over ++).

module StringLemmas

import Data.String
import Data.List
import Decidable.Equality

%default total

-- ============================================================================
-- Provable Prefix/Infix Operations
-- ============================================================================

||| DecEq-based prefix check. Unlike String.isPrefixOf, this reduces
||| on variables because DecEq provides decidable structural equality.
public export
charsPrefixOf : List Char -> List Char -> Bool
charsPrefixOf [] _ = True
charsPrefixOf _ [] = False
charsPrefixOf (x :: xs) (y :: ys) = case decEq x y of
  Yes _ => charsPrefixOf xs ys
  No _ => False

||| DecEq-based infix check (sliding window over haystack).
public export
charsInfixOf : List Char -> List Char -> Bool
charsInfixOf [] _ = True
charsInfixOf needle [] = False
charsInfixOf needle (x :: xs) =
  charsPrefixOf needle (x :: xs) || charsInfixOf needle xs

||| Whether a character occurs in a list of characters. Reduces on cons
||| (unlike the Foldable `elem`), so proofs can case-split on it. Used to
||| express the '/'-freeness of a path component (SafePath in ImporterProofs).
public export
charsElem : Char -> List Char -> Bool
charsElem x [] = False
charsElem x (y :: ys) = (x == y) || charsElem x ys

-- ============================================================================
-- Proven Lemmas
-- ============================================================================

||| Any list is a prefix of itself concatenated with anything.
||| This is the core lemma underlying extractionSafety, symlinkSafety,
||| and zipSlipPrevention in ImporterProofs.idr.
public export
charsPrefixOfAppend : (xs : List Char) -> (ys : List Char)
                   -> charsPrefixOf xs (xs ++ ys) = True
charsPrefixOfAppend [] ys = Refl
charsPrefixOfAppend (x :: xs) ys with (decEq x x)
  charsPrefixOfAppend (x :: xs) ys | Yes Refl = charsPrefixOfAppend xs ys
  charsPrefixOfAppend (x :: xs) ys | No contra = absurd (contra Refl)

||| The empty list is a prefix of everything.
public export
emptyPrefix : (xs : List Char) -> charsPrefixOf [] xs = True
emptyPrefix _ = Refl

||| Nothing is a prefix of the empty list except the empty list.
public export
prefixOfNil : (xs : List Char) -> charsPrefixOf xs [] = True -> xs = []
prefixOfNil [] _ = Refl
prefixOfNil (_ :: _) prf = absurd prf

||| The ".." needle is not found in a list that doesn't contain it.
||| (Structural proof over List Char, not String.)
public export
dotDotNotInfix : (xs : List Char)
              -> charsInfixOf ['.', '.'] xs = False
              -> Not (charsInfixOf ['.', '.'] xs = True)
dotDotNotInfix xs prf contra = absurd (trans (sym prf) contra)

||| If the head character matches the needle, the element is present.
||| `charsElem x (c :: cs) = (x == c) || charsElem x cs`, so a `True` head
||| comparison collapses the OR to `True`.
public export
charsElemHere : (x, c : Char) -> (cs : List Char)
             -> (x == c) = True -> charsElem x (c :: cs) = True
charsElemHere x c cs prf = rewrite prf in Refl

-- ============================================================================
-- Boolean / `any` Lemmas (fully proven — no trusted base)
-- ============================================================================
--
-- These structural lemmas about `&&`, `||`, and the stdlib `Foldable`
-- `any` are needed by ImporterProofs.ociLayoutEnforcement. Idris2's `any`
-- is `foldMap @{Any}`, which unfolds to a left fold with an accumulator;
-- `anyCons` re-expresses it in the head/tail form proofs can recurse on.
-- Every proof term here is total, so they add nothing to the trusted base.

||| `b || False = b`.
public export
orFalseRight : (b : Bool) -> (b || False) = b
orFalseRight True  = Refl
orFalseRight False = Refl

||| `||` is associative.
public export
orAssoc : (a, b, c : Bool) -> ((a || b) || c) = (a || (b || c))
orAssoc True  b c = Refl
orAssoc False b c = Refl

||| `b || True = True`.
public export
orTrueRight : (b : Bool) -> (b || True) = True
orTrueRight True  = Refl
orTrueRight False = Refl

||| Left conjunct extraction: if `a && b` is True then `a` is True.
public export
andLeftTrue : (a, b : Bool) -> (a && b) = True -> a = True
andLeftTrue True  _ _   = Refl
andLeftTrue False _ prf = absurd prf

||| Pull the accumulator out of the OR-fold underlying `any`.
public export
foldlOrPull : (p : a -> Bool) -> (acc : Bool) -> (xs : List a)
  -> foldl (\z, e => z || p e) acc xs
   = acc || foldl (\z, e => z || p e) False xs
foldlOrPull p acc [] = sym (orFalseRight acc)
foldlOrPull p acc (x :: xs) =
  rewrite foldlOrPull p (acc || p x) xs in
  rewrite foldlOrPull p (p x) xs in
  orAssoc acc (p x) (foldl (\z, e => z || p e) False xs)

||| `any` in head/tail form: `any p (x :: xs) = p x || any p xs`.
||| (Stdlib `any = foldMap @{Any}` does not reduce to this definitionally.)
public export
anyCons : (p : a -> Bool) -> (x : a) -> (xs : List a)
       -> any p (x :: xs) = p x || any p xs
anyCons p x xs = foldlOrPull p (p x) xs

||| OR-introduction from pointwise Bool implications.
public export
orIntroFromImpl : (px, anyp, qx, anyq : Bool)
  -> (px = True -> qx = True)
  -> (anyp = True -> anyq = True)
  -> (px || anyp) = True
  -> (qx || anyq) = True
orIntroFromImpl True  anyp qx anyq f g prf = rewrite f Refl in Refl
orIntroFromImpl False anyp qx anyq f g prf = rewrite g prf in orTrueRight qx

||| Monotonicity of Bool `any`: a pointwise implication lifts over the list.
public export
anyMono : (p, q : a -> Bool)
       -> ((z : a) -> p z = True -> q z = True)
       -> (xs : List a)
       -> any p xs = True
       -> any q xs = True
anyMono p q impl [] prf = absurd prf
anyMono p q impl (x :: xs) prf =
  rewrite anyCons q x xs in
  orIntroFromImpl (p x) (any p xs) (q x) (any q xs)
    (impl x) (anyMono p q impl xs)
    (trans (sym (anyCons p x xs)) prf)

-- ============================================================================
-- Bridge Axioms (string-primitive postulates)
-- ============================================================================
--
-- These two are the *minimal* trusted base connecting Idris2's opaque C
-- String primitives to the proven List-Char operations above. They are
-- the same justified category as backend string-primitive axioms
-- elsewhere in the estate (cf. boj-server SafetyLemmas charEqSound/
-- unpackLength): not provable in Idris2 (no reduction rules for the C
-- prims), minimal, isolated, documented. Per the repo idiom (Idris2 0.8
-- has no `postulate` keyword) they are `partial`+`idris_crash` stubs.
--
-- NET EFFECT: they let ImporterProofs.idr discharge `extractionSafety`,
-- `symlinkSafety`, `zipSlipPrevention` with real proofs — replacing 3
-- ad-hoc string postulates with 2 fundamental, well-understood ones.
-- Two further fundamental axioms (`eqStringSym`, `unpackEmptyInv`, below)
-- additionally discharge `ociLayoutEnforcement` and `absolutePathRejection`.

||| BRIDGE AXIOM: String.isPrefixOf agrees with the proven List-Char
||| `charsPrefixOf` under `unpack`. `isPrefixOf` is a C primitive with
||| no reduction rules; this equivalence is a backend-semantics fact.
partial
public export
isPrefixOfBridge : (s1, s2 : String)
                -> isPrefixOf s1 s2 = charsPrefixOf (unpack s1) (unpack s2)
isPrefixOfBridge _ _ =
  idris_crash "isPrefixOfBridge: string-primitive axiom — type-level use only"

||| BRIDGE AXIOM: `unpack` distributes over String `++`. Backend
||| primitive guarantee (`prim__strAppend` / `prim__strToCharList`),
||| not reducible at the Idris2 type level.
partial
public export
unpackAppend : (a, b : String)
            -> unpack (a ++ b) = unpack a ++ unpack b
unpackAppend _ _ =
  idris_crash "unpackAppend: string-primitive axiom — type-level use only"

||| BRIDGE AXIOM: primitive String equality `==` is symmetric. `(==)` on
||| String is `intToBool ∘ prim__eqString`, an opaque C primitive with no
||| reduction rules; symmetry is a backend-semantics fact. Used to flip the
||| `"manifest.json" == e.path` conjunct (extracted from the `elem` witness)
||| into the goal orientation `e.path == "manifest.json"`.
partial
public export
eqStringSym : (s1, s2 : String) -> (s1 == s2) = True -> (s2 == s1) = True
eqStringSym _ _ _ =
  idris_crash "eqStringSym: string-primitive axiom — type-level use only"

||| BRIDGE AXIOM: `unpack` yields the empty list only for the empty string
||| (the converse, `unpack "" = []`, holds by `Refl` via constant folding).
||| `unpack` is built on opaque C primitives (`prim__strLength` etc.), so
||| this injectivity-at-empty fact is not reducible at the type level. Used
||| to turn a char-level non-emptiness (`unpack comp = c :: cs`) obligation
||| back into the string-level premise `Not (component = "")`.
partial
public export
unpackEmptyInv : (s : String) -> unpack s = [] -> s = ""
unpackEmptyInv _ _ =
  idris_crash "unpackEmptyInv: string-primitive axiom — type-level use only"
