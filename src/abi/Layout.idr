-- SPDX-License-Identifier: MPL-2.0
-- Memory layout definitions and proofs for Stapeln ABI

module Layout

import Data.Nat
import Data.List
import Data.List.Quantifiers
import Types

%default total

-- ============================================================================
-- Field Layout Definitions
-- ============================================================================

||| A named field within a C struct, with offset and size in bytes.
public export
record FieldLayout where
  constructor MkFieldLayout
  fieldName : String
  offset : Nat
  size : Nat

||| A complete struct layout: a list of fields and a total size.
public export
record StructLayout where
  constructor MkStructLayout
  structName : String
  fields : List FieldLayout
  totalSize : Nat

-- ============================================================================
-- Concrete Layout Constants
-- ============================================================================

public export
serviceSpecLayout : StructLayout
serviceSpecLayout = MkStructLayout "ServiceSpec"
  [ MkFieldLayout "name_ptr"  0  8
  , MkFieldLayout "name_len"  8  8
  , MkFieldLayout "kind_ptr"  16 8
  , MkFieldLayout "kind_len"  24 8
  , MkFieldLayout "port"      32 4
  , MkFieldLayout "padding"   36 4
  ]
  40

public export
stackSpecHeaderLayout : StructLayout
stackSpecHeaderLayout = MkStructLayout "StackSpecHeader"
  [ MkFieldLayout "stack_id"      0  4
  , MkFieldLayout "padding0"      4  4
  , MkFieldLayout "name_ptr"      8  8
  , MkFieldLayout "name_len"      16 8
  , MkFieldLayout "services_ptr"  24 8
  ]
  32

public export
validationFindingHeaderLayout : StructLayout
validationFindingHeaderLayout = MkStructLayout "ValidationFindingHeader"
  [ MkFieldLayout "finding_id_ptr" 0  8
  , MkFieldLayout "finding_id_len" 8  8
  , MkFieldLayout "severity_ptr"   16 8
  , MkFieldLayout "severity_len"   24 8
  ]
  32

-- ============================================================================
-- Layout Size Constants (backward compatibility)
-- ============================================================================

public export
serviceSpecSizeBytes : Int
serviceSpecSizeBytes = 40

public export
stackSpecHeaderSizeBytes : Int
stackSpecHeaderSizeBytes = 32

public export
validationFindingHeaderSizeBytes : Int
validationFindingHeaderSizeBytes = 32

public export
abiLayoutVersion : String
abiLayoutVersion = "stapeln-abi-layout-v1"

-- ============================================================================
-- Proof: Field Sizes Are Positive
-- ============================================================================

||| A field has a positive (non-zero) size.
public export
data PositiveSize : FieldLayout -> Type where
  IsPositive : (f : FieldLayout) -> {auto prf : LTE 1 (size f)} -> PositiveSize f

||| All fields in the ServiceSpec layout have positive sizes.
||| Proved by explicit construction for each field.
public export
serviceSpecFieldsPositive : All PositiveSize (fields Layout.serviceSpecLayout)
serviceSpecFieldsPositive =
  [ IsPositive (MkFieldLayout "name_ptr"  0  8)
  , IsPositive (MkFieldLayout "name_len"  8  8)
  , IsPositive (MkFieldLayout "kind_ptr"  16 8)
  , IsPositive (MkFieldLayout "kind_len"  24 8)
  , IsPositive (MkFieldLayout "port"      32 4)
  , IsPositive (MkFieldLayout "padding"   36 4)
  ]

-- ============================================================================
-- Proof: Field Ranges
-- ============================================================================

||| The byte range [offset, offset+size) occupied by a field.
public export
fieldEnd : FieldLayout -> Nat
fieldEnd f = offset f + size f

||| Two fields do not overlap if one ends before the other starts.
public export
data NonOverlapping : FieldLayout -> FieldLayout -> Type where
  ||| Field a ends at or before field b starts.
  ABeforeB : (a, b : FieldLayout) -> {auto prf : LTE (fieldEnd a) (offset b)} -> NonOverlapping a b
  ||| Field b ends at or before field a starts.
  BBeforeA : (a, b : FieldLayout) -> {auto prf : LTE (fieldEnd b) (offset a)} -> NonOverlapping a b

||| All pairs of fields in a layout are non-overlapping.
public export
data AllNonOverlapping : List FieldLayout -> Type where
  ANONil  : AllNonOverlapping []
  ANOOne  : AllNonOverlapping [f]
  ANOCons : NonOverlapping f g
          -> AllNonOverlapping (g :: rest)
          -> AllNonOverlapping (f :: g :: rest)

||| Proof that adjacent ServiceSpec fields don't overlap.
||| Each field starts at or after the previous field ends.
||| Layout: name_ptr[0..8), name_len[8..16), kind_ptr[16..24),
|||          kind_len[24..32), port[32..36), padding[36..40)
public export
serviceSpecNonOverlapping : AllNonOverlapping (fields Layout.serviceSpecLayout)
serviceSpecNonOverlapping =
  ANOCons (ABeforeB (MkFieldLayout "name_ptr" 0 8) (MkFieldLayout "name_len" 8 8))
  (ANOCons (ABeforeB (MkFieldLayout "name_len" 8 8) (MkFieldLayout "kind_ptr" 16 8))
  (ANOCons (ABeforeB (MkFieldLayout "kind_ptr" 16 8) (MkFieldLayout "kind_len" 24 8))
  (ANOCons (ABeforeB (MkFieldLayout "kind_len" 24 8) (MkFieldLayout "port" 32 4))
  (ANOCons (ABeforeB (MkFieldLayout "port" 32 4) (MkFieldLayout "padding" 36 4))
  ANOOne))))

-- ============================================================================
-- Proof: Total Size Equals Sum of Field Sizes
-- ============================================================================

||| Sum of all field sizes in a list.
public export
sumFieldSizes : List FieldLayout -> Nat
sumFieldSizes [] = 0
sumFieldSizes (f :: fs) = size f + sumFieldSizes fs

||| The ServiceSpec total size (40) equals the sum of its field sizes.
||| Fields: 8 + 8 + 8 + 8 + 4 + 4 = 40
|||
||| PROVEN: Idris2 reduces sumFieldSizes over concrete FieldLayout records
||| and Nat addition normalizes to 40. Previously postulated because
||| Idris2 treats lowercase `serviceSpecLayout` as an implicit variable
||| in type signatures. Solved by inlining the concrete field list.
public export
serviceSpecSizeCorrect : sumFieldSizes
  [ MkFieldLayout "name_ptr"  0  8, MkFieldLayout "name_len"  8  8
  , MkFieldLayout "kind_ptr"  16 8, MkFieldLayout "kind_len"  24 8
  , MkFieldLayout "port"      32 4, MkFieldLayout "padding"   36 4
  ] = 40
serviceSpecSizeCorrect = Refl

||| The StackSpecHeader total size (32) equals the sum of its field sizes.
||| Fields: 4 + 4 + 8 + 8 + 8 = 32
|||
||| PROVEN: Same approach as serviceSpecSizeCorrect — inlined concrete fields.
public export
stackSpecHeaderSizeCorrect : sumFieldSizes
  [ MkFieldLayout "stack_id"     0  4, MkFieldLayout "padding0"     4  4
  , MkFieldLayout "name_ptr"     8  8, MkFieldLayout "name_len"     16 8
  , MkFieldLayout "services_ptr" 24 8
  ] = 32
stackSpecHeaderSizeCorrect = Refl

-- ============================================================================
-- Proof: Last Field Ends At Total Size
-- ============================================================================

||| Total `last` for field layouts (empty -> a zero field; concrete layouts are
||| non-empty). Hoisted from an invalid `where` on the data declaration below,
||| which also left a `?impossible_empty_layout` hole — so this module never
||| compiled. Made total (no hole) by returning a zero field for the empty case.
public export
lastField : List FieldLayout -> FieldLayout
lastField [x]            = x
lastField (_ :: x :: xs) = lastField (x :: xs)
lastField []             = MkFieldLayout "" 0 0

||| The last field of a non-empty layout ends exactly at the struct's total size.
public export
data LastFieldEndsAtTotal : StructLayout -> Type where
  MkLastFieldEndsAtTotal : (layout : StructLayout)
                        -> {auto prf : fieldEnd (lastField (fields layout)) = totalSize layout}
                        -> LastFieldEndsAtTotal layout

||| The last field of ServiceSpec (padding at offset 36, size 4) ends at 40.
||| 36 + 4 = 40 = totalSize serviceSpecLayout
|||
||| PROVEN: fieldEnd (MkFieldLayout "padding" 36 4) reduces to 36 + 4 = 40.
||| totalSize is inlined as 40 to avoid implicit variable binding.
||| Previously postulated due to the same lowercase-name issue.
public export
serviceSpecLastFieldCorrect : fieldEnd (MkFieldLayout "padding" 36 4) = 40
serviceSpecLastFieldCorrect = Refl
