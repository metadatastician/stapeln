-- SPDX-License-Identifier: MPL-2.0
-- Proofs.idr - Formal verification proofs for stapeln ABI contracts
--
-- All proofs are genuine case analysis or structural recursion.
-- NO believe_me, NO assert_total, NO assert_smaller, NO unsafePerformIO.
-- Postulates are used ONLY where the property depends on runtime values
-- (e.g., C struct packing) or Idris2 cannot reduce concrete record fields.

module Proofs

import Data.Nat
import Data.List
import Data.List.Elem
import Decidable.Equality
import Types
import Layout

%default total

-- ============================================================================
-- Proof 1: ResultCode Mapping Is Injective
-- ============================================================================
-- If two result codes map to the same integer, they must be the same code.
-- Proved by exhaustive case analysis on all 25 constructor pairs.

||| resultToInt is injective: equal outputs imply equal inputs.
public export
resultToIntInjective : (a, b : ResultCode) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective Ok           Ok           Refl = Refl
resultToIntInjective Error        Error        Refl = Refl
resultToIntInjective InvalidParam InvalidParam Refl = Refl
resultToIntInjective OutOfMemory  OutOfMemory  Refl = Refl
resultToIntInjective NullPointer  NullPointer  Refl = Refl
-- Distinct constructors map to distinct Int codes (0..4), so a witness that
-- their codes are equal is uninhabited. We refute each off-diagonal pair with
-- an explicit `Refl impossible` clause: the coverage checker reduces the
-- (public, reducible) `resultToInt` to the primitive literals and sees `Refl`
-- cannot typecheck at e.g. `0 = 1`. This is both honest and fast. (Using
-- `absurd` instead requires `Uninhabited (resultToInt a = resultToInt b)`,
-- whose instance search does NOT reduce `resultToInt` and diverges in this
-- module's import context.)
resultToIntInjective Ok           Error        Refl impossible
resultToIntInjective Ok           InvalidParam Refl impossible
resultToIntInjective Ok           OutOfMemory  Refl impossible
resultToIntInjective Ok           NullPointer  Refl impossible
resultToIntInjective Error        Ok           Refl impossible
resultToIntInjective Error        InvalidParam Refl impossible
resultToIntInjective Error        OutOfMemory  Refl impossible
resultToIntInjective Error        NullPointer  Refl impossible
resultToIntInjective InvalidParam Ok           Refl impossible
resultToIntInjective InvalidParam Error        Refl impossible
resultToIntInjective InvalidParam OutOfMemory  Refl impossible
resultToIntInjective InvalidParam NullPointer  Refl impossible
resultToIntInjective OutOfMemory  Ok           Refl impossible
resultToIntInjective OutOfMemory  Error        Refl impossible
resultToIntInjective OutOfMemory  InvalidParam Refl impossible
resultToIntInjective OutOfMemory  NullPointer  Refl impossible
resultToIntInjective NullPointer  Ok           Refl impossible
resultToIntInjective NullPointer  Error        Refl impossible
resultToIntInjective NullPointer  InvalidParam Refl impossible
resultToIntInjective NullPointer  OutOfMemory  Refl impossible

-- ============================================================================
-- Proof 2: ResultCode Values Are Distinct
-- ============================================================================
-- Each pair of distinct constructors maps to a different integer.
-- These follow directly from computation but are stated for documentation.

public export
okNotError : Not (resultToInt Ok = resultToInt Error)
okNotError = \case Refl impossible

public export
okNotInvalidParam : Not (resultToInt Ok = resultToInt InvalidParam)
okNotInvalidParam = \case Refl impossible

public export
okNotNullPointer : Not (resultToInt Ok = resultToInt NullPointer)
okNotNullPointer = \case Refl impossible

public export
okNotOutOfMemory : Not (resultToInt Ok = resultToInt OutOfMemory)
okNotOutOfMemory = \case Refl impossible

public export
errorNotInvalidParam : Not (resultToInt Error = resultToInt InvalidParam)
errorNotInvalidParam = \case Refl impossible

public export
errorNotNullPointer : Not (resultToInt Error = resultToInt NullPointer)
errorNotNullPointer = \case Refl impossible

public export
errorNotOutOfMemory : Not (resultToInt Error = resultToInt OutOfMemory)
errorNotOutOfMemory = \case Refl impossible

public export
invalidParamNotNullPointer : Not (resultToInt InvalidParam = resultToInt NullPointer)
invalidParamNotNullPointer = \case Refl impossible

public export
invalidParamNotOutOfMemory : Not (resultToInt InvalidParam = resultToInt OutOfMemory)
invalidParamNotOutOfMemory = \case Refl impossible

public export
nullPointerNotOutOfMemory : Not (resultToInt NullPointer = resultToInt OutOfMemory)
nullPointerNotOutOfMemory = \case Refl impossible

-- ============================================================================
-- Proof 3: Port Validity Constraints
-- ============================================================================
-- Valid ports are in the range [1, 65535]. We prove properties about ValidPort.

||| A valid port is never zero.
public export
validPortNonZero : ValidPort p -> Not (p = 0)
validPortNonZero (MkValidPort p {gt}) prf =
  -- If p = 0, then LTE 1 0 would hold, which is absurd
  let lte10 = replace {p = \x => LTE 1 x} prf gt
  in absurd lte10

||| A valid port is at most 65535.
public export
validPortBounded : ValidPort p -> LTE p 65535
validPortBounded (MkValidPort p {lt}) = lt

||| Port 0 is not valid (cannot construct ValidPort 0).
public export
portZeroInvalid : Not (ValidPort 0)
portZeroInvalid (MkValidPort 0 {gt}) = absurd gt

-- NOTE: the upper-bound witness `LTE p 65535` is supplied EXPLICITLY via
-- `lteAddRight` rather than left to `{auto}` search. Auto-searching `LTE p
-- 65535` for a concrete port diverges here: with Data.Nat's LTE hints in scope
-- the proof search branches at every level down to depth ~p, which never
-- terminates in practice (it hung the whole module). `lteAddRight p : LTE p
-- (p + m)` builds the witness directly (m is inferred by peeling), so each
-- proof is linear and fast. The lower bound `LTE 1 p` is shallow (`LTESucc
-- LTEZero`).

||| Port 80 is valid (constructive proof).
public export
port80Valid : ValidPort 80
port80Valid = MkValidPort 80 {gt = LTESucc LTEZero} {lt = lteAddRight 80}

||| Port 443 is valid (constructive proof).
public export
port443Valid : ValidPort 443
port443Valid = MkValidPort 443 {gt = LTESucc LTEZero} {lt = lteAddRight 443}

||| Port 8080 is valid (constructive proof).
public export
port8080Valid : ValidPort 8080
port8080Valid = MkValidPort 8080 {gt = LTESucc LTEZero} {lt = lteAddRight 8080}

-- ============================================================================
-- Proof 4: Service Name Non-Emptiness
-- ============================================================================

||| The empty string cannot have a ValidServiceName.
public export
emptyNameInvalid : Not (NonEmpty "")
emptyNameInvalid (IsNonEmpty "" f) = f Refl

-- ============================================================================
-- Proof 5: Stack Invariants
-- ============================================================================
-- A valid stack has at least one service, and all services have non-empty names.

||| A valid stack has a non-empty services list.
public export
validStackNonEmpty : ValidStack spec -> NonEmptyProof (services spec)
validStackNonEmpty (MkValidStack spec {nonempty} _) = nonempty

||| An empty services list cannot form a valid stack.
public export
emptyServicesInvalid : (spec : StackSpec) -> services spec = [] -> Not (ValidStack spec)
emptyServicesInvalid spec prf (MkValidStack spec {nonempty} _) =
  -- Rewrite services spec to [] using prf, then NonEmptyProof [] is uninhabited
  let ne = replace {p = NonEmptyProof} prf nonempty
  in case ne of {}  -- NonEmptyProof [] has no constructors

-- ============================================================================
-- Proof 6: Layout Field Ordering
-- ============================================================================
-- Adjacent fields in ServiceSpec layout are correctly ordered (each starts
-- where the previous ends, with no gaps or overlaps).

||| Field a immediately precedes field b (a ends exactly where b starts).
public export
data Adjacent : FieldLayout -> FieldLayout -> Type where
  MkAdjacent : (a, b : FieldLayout)
            -> {auto prf : fieldEnd a = offset b}
            -> Adjacent a b

||| ServiceSpec fields are contiguous: each field starts where the previous ends.
||| name_ptr[0..8), name_len[8..16), kind_ptr[16..24), kind_len[24..32),
||| port[32..36), padding[36..40)
|||
||| PROVEN: Idris2 reduces fieldEnd on concrete FieldLayout records and
||| Nat addition normalizes correctly. Each proof is by Refl:
||| 0+8=8, 8+8=16, 16+8=24, 24+8=32, 32+4=36.
||| Previously postulated unnecessarily.
public export
serviceSpecContiguous0 : fieldEnd (MkFieldLayout "name_ptr" 0 8) = offset (MkFieldLayout "name_len" 8 8)
serviceSpecContiguous0 = Refl

public export
serviceSpecContiguous1 : fieldEnd (MkFieldLayout "name_len" 8 8) = offset (MkFieldLayout "kind_ptr" 16 8)
serviceSpecContiguous1 = Refl

public export
serviceSpecContiguous2 : fieldEnd (MkFieldLayout "kind_ptr" 16 8) = offset (MkFieldLayout "kind_len" 24 8)
serviceSpecContiguous2 = Refl

public export
serviceSpecContiguous3 : fieldEnd (MkFieldLayout "kind_len" 24 8) = offset (MkFieldLayout "port" 32 4)
serviceSpecContiguous3 = Refl

public export
serviceSpecContiguous4 : fieldEnd (MkFieldLayout "port" 32 4) = offset (MkFieldLayout "padding" 36 4)
serviceSpecContiguous4 = Refl

-- ============================================================================
-- Proof 7: ResultCode Round-Trip
-- ============================================================================
-- intToResult is a partial inverse of resultToInt.

||| Attempt to decode an Int back to a ResultCode.
public export
intToResult : Int -> Maybe ResultCode
intToResult 0 = Just Ok
intToResult 1 = Just Error
intToResult 2 = Just InvalidParam
intToResult 3 = Just OutOfMemory
intToResult 4 = Just NullPointer
intToResult _ = Nothing

||| Round-trip: encoding then decoding always recovers the original code.
public export
resultRoundTrip : (r : ResultCode) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip NullPointer = Refl
resultRoundTrip OutOfMemory = Refl

-- ============================================================================
-- Proof 8: ResultCode Enumeration Is Complete
-- ============================================================================

||| Every ResultCode is one of exactly five constructors.
||| (Trivially true by pattern matching, but useful as documentation.)
public export
allResultCodes : List ResultCode
allResultCodes = [Ok, Error, InvalidParam, NullPointer, OutOfMemory]

||| Every ResultCode appears in allResultCodes. The list is inlined in the type
||| (rather than referring to `allResultCodes`) because the `Elem` constructors
||| `Here`/`There` need the spine to be a literal `(::)` to unify; the named CAF
||| `allResultCodes` does not unfold during unification. It is definitionally the
||| same list, so this proves exactly "every ResultCode appears in allResultCodes".
public export
resultCodeComplete : (r : ResultCode)
                  -> Elem r [Ok, Error, InvalidParam, NullPointer, OutOfMemory]
resultCodeComplete Ok = Here
resultCodeComplete Error = There Here
resultCodeComplete InvalidParam = There (There Here)
resultCodeComplete NullPointer = There (There (There Here))
resultCodeComplete OutOfMemory = There (There (There (There Here)))
