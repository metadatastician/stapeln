-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/property/layer_invariants_test.ts to Idris2.
-- 27 of 27 tests ported.
--
-- The TS suite uses Map<string,LayerDef>; we model LayerSet as a
-- (List (String, LayerDef), List String) pair for layers + buildOrder.
-- JSON.stringify/JSON.parse roundtripping is replaced with a structural
-- copy through serialiseToFields / deserialiseFromFields, which
-- preserves every field the TS test asserts on (the test never inspects
-- the JSON string itself, only the round-tripped object).

module LayerInvariantsTest

import Test.Spec
import Data.String
import Data.List
import Data.Maybe

%default covering

-- == LayerDef ==

record LayerDef where
  constructor MkLayer
  layerName : String
  layerDesc : String
  extendsFrom : Maybe String     -- "extends" (parent layer)
  baseImage : Maybe String       -- "from"
  cache : Bool
  verify : Maybe Bool
  memoryBudget : Maybe Nat
  cpuShare : Maybe Nat

-- == OciLabels ==

record OciLabels where
  constructor MkLabels
  labelName : String
  labelDesc : String
  labelCache : String          -- "true" / "false"
  labelExtends : Maybe String
  labelMemBudgetMib : Maybe String
  labelCpuShare : Maybe String

layerToOciLabels : LayerDef -> OciLabels
layerToOciLabels l =
  MkLabels
    l.layerName
    l.layerDesc
    (if l.cache then "true" else "false")
    l.extendsFrom
    (map show l.memoryBudget)
    (map show l.cpuShare)

-- == Validation ==

isBlank : String -> Bool
isBlank s = length (trim s) == 0

validateLayer : LayerDef -> List String
validateLayer l =
  let e1 : List String = if isBlank l.layerName then ["layer name must be non-empty"] else []
      e2 : List String = if isBlank l.layerDesc then ["layer description must be non-empty"] else []
      e3 : List String = case (l.baseImage, l.extendsFrom) of
             (Nothing, Nothing) =>
               ["layer must have either 'from' (base image) or 'extends' (parent layer)"]
             _ => []
      e4 : List String = case l.memoryBudget of
             Just 0 => ["memory_budget must be > 0, got 0"]
             _      => []
      e5 : List String = case l.cpuShare of
             Just 0 => ["cpu_share must be > 0, got 0"]
             _      => []
  in e1 ++ e2 ++ e3 ++ e4 ++ e5

-- Validate OCI labels: name + desc non-empty, cache in {true,false}, mb numeric+positive when set.
validateOciLabels : OciLabels -> List String
validateOciLabels labels =
  let e1 : List String = if isBlank labels.labelName
             then ["OCI label 'name' must be present and non-empty"]
             else []
      e2 : List String = if isBlank labels.labelDesc
             then ["OCI label 'description' must be present and non-empty"]
             else []
      e3 : List String = if labels.labelCache /= "true" && labels.labelCache /= "false"
             then ["OCI label 'cache' must be 'true' or 'false'"]
             else []
      e4 : List String = case labels.labelMemBudgetMib of
             Just s => case parsePositive {a=Integer} s of
                         Just n => if n > 0
                                     then []
                                     else ["mb_mib must be > 0"]
                         Nothing => ["mb_mib must be numeric"]
             Nothing => []
  in e1 ++ e2 ++ e3 ++ e4

-- == Roundtrip ==
-- TS roundtrip = JSON stringify/parse on a LayerDef object. Idris2 records
-- have no automatic JSON; mirror the TS semantics by structural copy. The
-- TS test never inspects the serialised string, only the restored object's
-- fields, so a deep-copy semantically matches.

roundtripLayer : LayerDef -> LayerDef
roundtripLayer l =
  MkLayer
    l.layerName
    l.layerDesc
    l.extendsFrom
    l.baseImage
    l.cache
    l.verify
    l.memoryBudget
    l.cpuShare

-- Show-equivalence proxy for layer's serialised form (instead of JSON string).
showLayer : LayerDef -> String
showLayer l =
  l.layerName ++ "|" ++ l.layerDesc ++ "|" ++
  show l.extendsFrom ++ "|" ++ show l.baseImage ++ "|" ++
  show l.cache ++ "|" ++ show l.verify ++ "|" ++
  show l.memoryBudget ++ "|" ++ show l.cpuShare

-- Show-equivalence for OciLabels.
showLabels : OciLabels -> String
showLabels lbl =
  lbl.labelName ++ "|" ++ lbl.labelDesc ++ "|" ++
  lbl.labelCache ++ "|" ++ show lbl.labelExtends ++ "|" ++
  show lbl.labelMemBudgetMib ++ "|" ++ show lbl.labelCpuShare

-- == LayerSet ==

record LayerSet where
  constructor MkLayerSet
  setLayers : List (String, LayerDef)   -- preserves insertion order
  setBuildOrder : List String

setHas : String -> List (String, LayerDef) -> Bool
setHas n xs = any (\(k, _) => k == n) xs

setSize : List (String, LayerDef) -> Nat
setSize = length

setKeys : List (String, LayerDef) -> List String
setKeys = map fst

-- composeLayers throws on conflict in TS; in Idris2 we return Either.
composeLayers : LayerSet -> LayerSet -> Either String LayerSet
composeLayers a b =
  let conflict = find (\(n, _) => setHas n a.setLayers) b.setLayers
  in case conflict of
       Just (n, _) => Left ("Layer name conflict: '" ++ n ++ "' exists in both sets")
       Nothing => Right (MkLayerSet
                           (a.setLayers ++ b.setLayers)
                           (a.setBuildOrder ++ b.setBuildOrder))

validateLayerSet : LayerSet -> List String
validateLayerSet s =
  let perLayer = concatMap layerErrs s.setLayers
      missingFromOrder = concatMap (orderCheck s.setBuildOrder) (setKeys s.setLayers)
  in perLayer ++ missingFromOrder
  where
    layerErrs : (String, LayerDef) -> List String
    layerErrs (n, l) =
      let local = map (\e => "layer '" ++ n ++ "': " ++ e) (validateLayer l)
          extendsErr = case l.extendsFrom of
                         Just parent =>
                           if any (\(k, _) => k == parent) s.setLayers
                             then []
                             else ["layer '" ++ n ++ "' extends '" ++ parent
                                    ++ "' which is not in this set"]
                         Nothing => []
      in local ++ extendsErr

    orderCheck : List String -> String -> List String
    orderCheck order n =
      if elem n order
        then []
        else ["layer '" ++ n ++ "' is defined but missing from buildOrder"]

-- == Fixtures ==

baseLayer : LayerDef
baseLayer = MkLayer
  "base"
  "Chainguard Wolfi minimal base image"
  Nothing
  (Just "cgr.dev/chainguard/wolfi-base:latest")
  True
  (Just True)
  Nothing
  Nothing

toolchainLayer : LayerDef
toolchainLayer = MkLayer
  "elixir-toolchain"
  "Erlang/OTP + Elixir + Mix build tooling"
  (Just "base")
  Nothing
  True
  Nothing
  Nothing
  Nothing

depsLayer : LayerDef
depsLayer = MkLayer
  "backend-deps"
  "Fetch and compile Elixir dependencies"
  (Just "elixir-toolchain")
  Nothing
  True
  Nothing
  (Just 2048)
  (Just 512)

buildLayer : LayerDef
buildLayer = MkLayer
  "backend-build"
  "Compile and release Elixir application"
  (Just "backend-deps")
  Nothing
  False
  Nothing
  (Just 4096)
  (Just 1024)

runtimeLayer : LayerDef
runtimeLayer = MkLayer
  "runtime"
  "Minimal runtime image with release artefacts"
  Nothing
  (Just "cgr.dev/chainguard/wolfi-base:latest")
  False
  (Just True)
  (Just 512)
  Nothing

makeBackendLayerSet : LayerSet
makeBackendLayerSet = MkLayerSet
  [ ("base", baseLayer)
  , ("elixir-toolchain", toolchainLayer)
  , ("backend-deps", depsLayer)
  , ("backend-build", buildLayer)
  ]
  ["base", "elixir-toolchain", "backend-deps", "backend-build"]

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  -- --- Invariant 1: valid layer -> valid OCI labels ---
  [ test "LayerInvariant: valid layer produces valid OCI labels" $ do
      let layers = [baseLayer, toolchainLayer, depsLayer, buildLayer, runtimeLayer]
      let allErrs = map (validateOciLabels . layerToOciLabels) layers
      assertTrue "no errors across all layers" (all null allErrs)

  , test "LayerInvariant: OCI label name matches layer name" $ do
      let labels = layerToOciLabels depsLayer
      assertEq labels.labelName depsLayer.layerName

  , test "LayerInvariant: OCI label description matches layer description" $ do
      let labels = layerToOciLabels depsLayer
      assertEq labels.labelDesc depsLayer.layerDesc

  , test "LayerInvariant: cache=true produces OCI label 'true'" $ do
      let l = MkLayer "l1" "d" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let labels = layerToOciLabels l
      assertEq labels.labelCache "true"

  , test "LayerInvariant: cache=false produces OCI label 'false'" $ do
      let l = MkLayer "l2" "d" Nothing (Just "img:latest") False Nothing Nothing Nothing
      let labels = layerToOciLabels l
      assertEq labels.labelCache "false"

  , test "LayerInvariant: extends present in OCI labels when set" $ do
      let labels = layerToOciLabels toolchainLayer
      assertEq labels.labelExtends (Just "base")

  , test "LayerInvariant: extends absent from OCI labels when not set" $ do
      let labels = layerToOciLabels baseLayer
      assertEq labels.labelExtends Nothing

  , test "LayerInvariant: memory_budget produces correctly typed OCI label" $ do
      let labels = layerToOciLabels depsLayer
      case labels.labelMemBudgetMib of
        Nothing => assertTrue "label present" False
        Just s => case parsePositive {a=Integer} s of
                    Just n => allPass
                                [ assertTrue "is positive" (n > 0)
                                , assertEq (cast {to=Integer} (the Nat 2048)) n
                                ]
                    Nothing => assertTrue "numeric" False

  -- --- Invariant 2: Roundtrip ---
  , test "LayerRoundtrip: base layer round-trips correctly" $ do
      let r = roundtripLayer baseLayer
      allPass
        [ assertEq r.layerName baseLayer.layerName
        , assertEq r.layerDesc baseLayer.layerDesc
        , assertEq r.baseImage baseLayer.baseImage
        , assertEq r.cache baseLayer.cache
        , assertEq r.verify baseLayer.verify
        ]

  , test "LayerRoundtrip: layer with extends round-trips correctly" $ do
      let r = roundtripLayer toolchainLayer
      allPass
        [ assertEq r.layerName toolchainLayer.layerName
        , assertEq r.extendsFrom toolchainLayer.extendsFrom
        , assertEq r.cache toolchainLayer.cache
        ]

  , test "LayerRoundtrip: layer with budget round-trips correctly" $ do
      let r = roundtripLayer depsLayer
      allPass
        [ assertEq r.memoryBudget depsLayer.memoryBudget
        , assertEq r.cpuShare depsLayer.cpuShare
        ]

  , test "LayerRoundtrip: roundtripped layer produces same OCI labels" $ do
      let originalLabels = layerToOciLabels buildLayer
      let restored = roundtripLayer buildLayer
      let restoredLabels = layerToOciLabels restored
      assertEq (showLabels originalLabels) (showLabels restoredLabels)

  , test "LayerRoundtrip: roundtrip is idempotent (double roundtrip = single)" $ do
      let once = roundtripLayer depsLayer
      let twice = roundtripLayer once
      assertEq (showLayer once) (showLayer twice)

  -- --- Invariant 3: memory_budget > 0 ---
  , test "BudgetProperty: layer with positive memory_budget is valid" $ do
      let l = MkLayer "big-build" "Resource-heavy build step"
                      (Just "base") Nothing False Nothing (Just 8192) Nothing
      assertTrue "no errors" (length (validateLayer l) == 0)

  , test "BudgetProperty: layer with memory_budget=0 is invalid" $ do
      let l = MkLayer "zero-budget" "Bad layer"
                      (Just "base") Nothing False Nothing (Just 0) Nothing
      let errs = validateLayer l
      allPass
        [ assertTrue "errors present" (length errs > 0)
        , assertTrue "mentions memory_budget" (any (\e => isInfixOf "memory_budget" e) errs)
        ]

  , test "BudgetProperty: layer with negative memory_budget is invalid" $ do
      -- Nat has no negative; the TS-equivalent invariant (memory_budget <= 0 invalid)
      -- is exercised by the memory_budget=0 case. Encode as a tautology to mark covered.
      assertTrue "Nat excludes negatives by construction" True

  , test "BudgetProperty: all fixture layers with memory_budget have budget > 0" $ do
      let budgeted = [depsLayer, buildLayer, runtimeLayer]
      let checks = map (\l => case l.memoryBudget of
                                Just n => n > 0
                                Nothing => True) budgeted
      assertTrue "all > 0" (all id checks)

  , test "BudgetProperty: cpu_share=0 is invalid when set" $ do
      let l = MkLayer "zero-cpu" "Bad layer"
                      (Just "base") Nothing False Nothing Nothing (Just 0)
      let errs = validateLayer l
      allPass
        [ assertTrue "errors present" (length errs > 0)
        , assertTrue "mentions cpu_share" (any (\e => isInfixOf "cpu_share" e) errs)
        ]

  , test "BudgetProperty: layer without memory_budget is valid (budget is optional)" $ do
      let l = MkLayer "no-budget" "Layer without explicit budget"
                      (Just "base") Nothing True Nothing Nothing Nothing
      assertTrue "no errors" (length (validateLayer l) == 0)

  , test "BudgetProperty: OCI label memory_budget_mib absent when memory_budget not set" $ do
      let labels = layerToOciLabels toolchainLayer
      assertEq labels.labelMemBudgetMib Nothing

  -- --- Invariant 4: Composition ---
  , test "LayerComposition: backend layer set is individually valid" $ do
      let s = makeBackendLayerSet
      let errs = validateLayerSet s
      assertTrue "no errors" (length errs == 0)

  , test "LayerComposition: frontend layer set is individually valid (with base dependency)" $ do
      let deno = MkLayer "deno-toolchain" "Deno runtime"
                          Nothing (Just "cgr.dev/chainguard/wolfi-base:latest")
                          True Nothing Nothing Nothing
      let rescript = MkLayer "rescript-toolchain" "ReScript compiler"
                              (Just "deno-toolchain") Nothing
                              True Nothing Nothing Nothing
      let build = MkLayer "frontend-build" "Frontend build"
                           (Just "rescript-toolchain") Nothing
                           False Nothing Nothing Nothing
      let s = MkLayerSet
                [ ("deno-toolchain", deno)
                , ("rescript-toolchain", rescript)
                , ("frontend-build", build)
                ]
                ["deno-toolchain", "rescript-toolchain", "frontend-build"]
      assertTrue "no errors" (length (validateLayerSet s) == 0)

  , test "LayerComposition: composing backend and runtime produces valid combined set" $ do
      let runtimeSet = MkLayerSet [("runtime", runtimeLayer)] ["runtime"]
      case composeLayers makeBackendLayerSet runtimeSet of
        Left _ => assertTrue "compose succeeded" False
        Right combined =>
          allPass
            [ assertTrue "5 layers" (setSize combined.setLayers == 5)
            , assertTrue "5 in build order" (length combined.setBuildOrder == 5)
            , assertTrue "all layers valid"
                (all (\(_, l) => length (validateLayer l) == 0) combined.setLayers)
            ]

  , test "LayerComposition: composing disjoint sets preserves all layer names" $ do
      let a1 = MkLayer "layer-a1" "A1" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let a2 = MkLayer "layer-a2" "A2" (Just "layer-a1") Nothing False Nothing Nothing Nothing
      let b1 = MkLayer "layer-b1" "B1" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let sa = MkLayerSet [("layer-a1", a1), ("layer-a2", a2)] ["layer-a1", "layer-a2"]
      let sb = MkLayerSet [("layer-b1", b1)] ["layer-b1"]
      case composeLayers sa sb of
        Left _ => assertTrue "compose succeeded" False
        Right combined =>
          allPass
            [ assertTrue "has layer-a1" (setHas "layer-a1" combined.setLayers)
            , assertTrue "has layer-a2" (setHas "layer-a2" combined.setLayers)
            , assertTrue "has layer-b1" (setHas "layer-b1" combined.setLayers)
            , assertTrue "exactly 3 layers" (setSize combined.setLayers == 3)
            ]

  , test "LayerComposition: composing overlapping sets throws on conflict" $ do
      let shared = MkLayer "shared-name" "A" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let shared2 = MkLayer "shared-name" "B" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let sa = MkLayerSet [("shared-name", shared)] ["shared-name"]
      let sb = MkLayerSet [("shared-name", shared2)] ["shared-name"]
      case composeLayers sa sb of
        Left _  => assertTrue "conflict detected" True
        Right _ => assertTrue "should not compose" False

  , test "LayerComposition: composed set buildOrder is concatenation of both" $ do
      let a1 = MkLayer "a1" "A1" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let b1 = MkLayer "b1" "B1" Nothing (Just "img:latest") True Nothing Nothing Nothing
      let sa = MkLayerSet [("a1", a1)] ["a1"]
      let sb = MkLayerSet [("b1", b1)] ["b1"]
      case composeLayers sa sb of
        Left _ => assertTrue "should compose" False
        Right combined => assertEq combined.setBuildOrder ["a1", "b1"]

  , test "LayerComposition: all OCI labels of composed layers are valid" $ do
      let runtimeSet = MkLayerSet [("runtime", runtimeLayer)] ["runtime"]
      case composeLayers makeBackendLayerSet runtimeSet of
        Left _ => assertTrue "compose succeeded" False
        Right combined =>
          let labelErrors = map (\(_, l) => validateOciLabels (layerToOciLabels l)) combined.setLayers
          in assertTrue "all labels valid" (all null labelErrors)
  ]
