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
