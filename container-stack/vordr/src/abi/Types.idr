-- SPDX-License-Identifier: MPL-2.0
-- Vordr ABI core types and proofs (Idris2).
--
-- This module was missing: src/abi/Foreign.idr imported `Vordr.ABI.Types`
-- (and `Vordr.ABI.Layout`), neither of which existed, so the ABI layer never
-- compiled and was orphaned (no ipkg referenced it). Provided here, flat-module
-- (estate-consistent), matching the authoritative Zig ABI in ffi/zig/src/main.zig.
--
-- No believe_me / assert_total / idris_crash / holes.

module Types

import Decidable.Equality

%default total

-- ============================================================================
-- Result Codes
-- ============================================================================

||| ABI result codes. The integer mapping is the C ABI contract and MUST match
||| `ffi/zig/src/main.zig` (`ok=0, err=1, invalid_param=2, out_of_memory=3,
||| null_pointer=4`). Foreign.idr's `resultFromInt`/`errorDescription` use the
||| same set, so the proofs below describe the real FFI boundary.
public export
data ResultCode = Ok | Error | InvalidParam | OutOfMemory | NullPointer

||| The C ABI and Foreign.idr name this type `Result`; `ResultCode` is the
||| canonical Idris name and `Result` the ABI-facing alias.
public export
Result : Type
Result = ResultCode

public export
resultToInt : ResultCode -> Int
resultToInt Ok = 0
resultToInt Error = 1
resultToInt InvalidParam = 2
resultToInt OutOfMemory = 3
resultToInt NullPointer = 4

public export
DecEq ResultCode where
  decEq Ok Ok = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error Error = Yes Refl
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam InvalidParam = Yes Refl
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)
  decEq NullPointer NullPointer = Yes Refl

-- ============================================================================
-- Proof: resultToInt is injective
-- ============================================================================

||| Distinct result codes map to distinct Int codes, so equal codes imply equal
||| constructors. Off-diagonal pairs are refuted by `Refl impossible` (the
||| coverage checker reduces the reducible `resultToInt` to the primitive Int
||| literals); we avoid `absurd`, whose `Uninhabited (resultToInt a = resultToInt
||| b)` search does not reduce `resultToInt` and diverges.
public export
resultToIntInjective : (a, b : ResultCode) -> resultToInt a = resultToInt b -> a = b
resultToIntInjective Ok           Ok           Refl = Refl
resultToIntInjective Error        Error        Refl = Refl
resultToIntInjective InvalidParam InvalidParam Refl = Refl
resultToIntInjective OutOfMemory  OutOfMemory  Refl = Refl
resultToIntInjective NullPointer  NullPointer  Refl = Refl
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
-- Proof: Int -> ResultCode round-trip
-- ============================================================================

||| Decode an Int back to a ResultCode (partial inverse of resultToInt).
public export
intToResult : Int -> Maybe ResultCode
intToResult 0 = Just Ok
intToResult 1 = Just Error
intToResult 2 = Just InvalidParam
intToResult 3 = Just OutOfMemory
intToResult 4 = Just NullPointer
intToResult _ = Nothing

||| Round-trip: encoding then decoding recovers the original code.
public export
resultRoundTrip : (r : ResultCode) -> intToResult (resultToInt r) = Just r
resultRoundTrip Ok = Refl
resultRoundTrip Error = Refl
resultRoundTrip InvalidParam = Refl
resultRoundTrip OutOfMemory = Refl
resultRoundTrip NullPointer = Refl
