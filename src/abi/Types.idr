-- SPDX-License-Identifier: MPL-2.0
-- Stapeln ABI type definitions (Idris2) with dependent types and proofs

module Types

import Data.List
import Data.List.Quantifiers
import Data.Nat
import Decidable.Equality

%default total

-- ============================================================================
-- Result Codes
-- ============================================================================

||| ABI result codes. The integer mapping is the C ABI contract and MUST match
||| `ffi/zig/src/main.zig` (`pub const Result = enum(c_int) { ok=0, error=1,
||| invalid_param=2, out_of_memory=3, null_pointer=4 }`). A previous refactor
||| drifted this type (it carried a `NotFound` at 3 and pushed `OutOfMemory` to
||| 4, with no `NullPointer`), which silently de-correlated the round-trip and
||| injectivity proofs in Proofs.idr from the actual FFI boundary. Realigned.
public export
data ResultCode = Ok | Error | InvalidParam | OutOfMemory | NullPointer

||| The C ABI and Foreign.idr name this type `Result`; `ResultCode` is the
||| canonical Idris name. `Result` is the ABI-facing alias so the proven
||| properties line up with the FFI surface that uses them.
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

-- DecEq for ResultCode enables compile-time equality proofs
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
-- Core Records
-- ============================================================================

public export
record ServiceSpec where
  constructor MkServiceSpec
  name : String
  kind : String
  port : Int

public export
record StackSpec where
  constructor MkStackSpec
  stackId : Int
  name : String
  description : String
  services : List ServiceSpec

public export
record ValidationFinding where
  constructor MkValidationFinding
  findingId : String
  severity : String
  message : String
  hint : String

public export
record ValidationReport where
  constructor MkValidationReport
  score : Int
  findings : List ValidationFinding

-- ============================================================================
-- Dependent Types for Validated Inputs
-- ============================================================================

||| A port number proven to be in the valid range 1..65535.
||| We use Nat internally for proof ergonomics; the caller converts from Int.
public export
data ValidPort : (p : Nat) -> Type where
  MkValidPort : (p : Nat)
             -> {auto gt : LTE 1 p}
             -> {auto lt : LTE p 65535}
             -> ValidPort p

||| Proof witness that a string is non-empty: a (relevant) proof that its
||| length is not zero.
|||
||| Previously the witness was erased (quantity 0) and the type also carried a
||| vacuous `{auto prf : s = s}`. An erased witness cannot be used, so
||| `Not (NonEmpty "")` was impossible to discharge (and the `s = s` field
||| proved nothing). The witness is now relevant so non-emptiness can actually
||| be eliminated in proofs.
public export
data NonEmpty : String -> Type where
  IsNonEmpty : (s : String) -> (notEmpty : length s = 0 -> Void) -> NonEmpty s

||| A service name proven to be non-empty.
public export
data ValidServiceName : String -> Type where
  MkValidServiceName : (s : String) -> NonEmpty s -> ValidServiceName s

||| Proof that a list is non-empty (has at least one element).
||| (Hoisted to top level: it was previously inside an invalid `where` block on
||| the `ValidStack` data declaration — which `MkValidStack` also references
||| forward — so this module failed to parse and never compiled. Its
||| constructor is renamed to avoid clashing with `NonEmpty.IsNonEmpty`.)
public export
data NonEmptyProof : List a -> Type where
  IsNonEmptyList : NonEmptyProof (x :: xs)

||| A stack specification proven to contain at least one service,
||| where every service has a non-empty name.
public export
data ValidStack : StackSpec -> Type where
  MkValidStack : (spec : StackSpec)
              -> {auto nonempty : NonEmptyProof (services spec)}
              -> (allNamed : All (\svc => NonEmpty (name svc)) (services spec))
              -> ValidStack spec

-- ============================================================================
-- Decision Procedures (runtime validation with proof construction)
-- ============================================================================

||| Decide whether a Nat is a valid port number.
public export
isValidPort : (p : Nat) -> Dec (LTE 1 p, LTE p 65535)
isValidPort p =
  case isLTE 1 p of
    Yes gt => case isLTE p 65535 of
      Yes lt => Yes (gt, lt)
      No contra => No (\(_, lt) => contra lt)
    No contra => No (\(gt, _) => contra gt)

||| Decide whether a string is non-empty.
||| We compare length against 0; if positive, the string is non-empty.
public export
isNonEmptyString : (s : String) -> Dec (length s = 0 -> Void)
isNonEmptyString s =
  case decEq (length s) 0 of
    Yes eq => No (\f => f eq)
    No neq => Yes neq
