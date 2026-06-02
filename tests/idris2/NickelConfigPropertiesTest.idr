-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/property/nickel_config_properties_test.ts to Idris2.
-- 15 of 15 tests ported.
--
-- The original tests validate Record<string, unknown> shapes; we model
-- this with sum types over the small set of fields actually queried:
-- service configs have name/image, resource configs have cpu/memory, etc.
-- The regex /^\d+[KMGkmg]B?$/ for memory units is ported to a List Char
-- walk; the regex /^\d+$/ for port parsing is replaced by Data.String.parseInteger.

module NickelConfigPropertiesTest

import Test.Spec
import Data.String
import Data.List
import Data.List1
import Data.Maybe

%default covering

-- == Service config (minimal: name + image + optional flags) ==

record ServiceConfig where
  constructor MkServiceConfig
  hasName : Bool
  hasImage : Bool
  -- Additional fields are not modelled because validateServiceConfig
  -- only reads "name" and "image" presence; other fields are accepted.

validateServiceConfig : ServiceConfig -> (Bool, List String)
validateServiceConfig c =
  let missing = (if c.hasName then [] else ["name"])
              ++ (if c.hasImage then [] else ["image"])
  in (null missing, missing)

-- == Resource config ==

data ResourceMemoryUnit = MUnitK | MUnitM | MUnitG

-- Validate memory string matches /^\d+[KMGkmg]B?$/:
-- one or more digits, then exactly one of K/M/G (case-insensitive),
-- optionally followed by 'B'.
isValidMemoryString : String -> Bool
isValidMemoryString s = case unpack s of
  []        => False
  (c :: cs) => if isDigit c
                 then matchAfterDigits cs
                 else False
  where
    isDigit : Char -> Bool
    isDigit c = c >= '0' && c <= '9'

    isUnit : Char -> Bool
    isUnit c = c == 'K' || c == 'M' || c == 'G'
            || c == 'k' || c == 'm' || c == 'g'

    -- After at least one digit consumed; consume zero or more digits, then
    -- exactly one unit char, then optionally 'B', then end of string.
    matchUnitTail : List Char -> Bool
    matchUnitTail [] = True
    matchUnitTail ['B'] = True
    matchUnitTail _ = False

    matchAfterDigits : List Char -> Bool
    matchAfterDigits [] = False  -- e.g. "512" alone
    matchAfterDigits (c :: cs) =
      if isDigit c
        then matchAfterDigits cs
        else if isUnit c
          then matchUnitTail cs
          else False

-- Resource config has optional cpu and memory (string values).
record ResourceConfig where
  constructor MkResourceConfig
  hasCpu : Bool
  hasMemory : Bool
  -- For type checks, model what TS validates:
  -- cpu can be string or number — both are valid types in Idris2 model so we
  -- track only presence here. Memory validation runs only if hasMemory.
  memoryString : Maybe String

validateResourceConfig : ResourceConfig -> List String
validateResourceConfig r =
  let missingCpu = if r.hasCpu then [] else ["missing required resource field: cpu"]
      missingMem = if r.hasMemory then [] else ["missing required resource field: memory"]
      memFormat = case r.memoryString of
        Just s => if isValidMemoryString s
                    then []
                    else ["memory '" ++ s ++ "' must match pattern: number + unit (K/M/G)"]
        Nothing => []
  in missingCpu ++ missingMem ++ memFormat

-- == Port spec validator ==

-- Port range 1..65535 inclusive.
inPortRange : Nat -> Bool
inPortRange p = p >= 1 && p <= 65535

-- Parse port; returns Nothing on non-numeric or out-of-range.
parsePort : String -> Maybe Nat
parsePort s = case parsePositive {a=Integer} s of
  Nothing => Nothing
  Just n  => if n >= 1 && n <= 65535
               then Just (cast n)
               else Nothing

-- Validate "port" or "host:container".
validatePortSpec : String -> Bool
validatePortSpec spec =
  let parts = forget (split (== ':') spec)
  in case parts of
       [p]      => isJust (parsePort p)
       [h, c]   => isJust (parsePort h) && isJust (parsePort c)
       _        => False

-- == Network driver validator ==

validNetworkDrivers : List String
validNetworkDrivers = ["bridge", "host", "none", "overlay"]

validateNetworkDriver : String -> List String
validateNetworkDriver d =
  if elem d validNetworkDrivers
    then []
    else ["invalid driver '" ++ d ++ "'"]

-- == Injection-character check ==

dangerousChars : List Char
dangerousChars = [';', '|', '&', '$', '`', '(', ')']

hasDangerousChar : String -> Bool
hasDangerousChar s = any (\c => elem c dangerousChars) (unpack s)

hasNewlineOrCR : String -> Bool
hasNewlineOrCR s = any (\c => c == '\n' || c == '\r') (unpack s)

hasNullByte : String -> Bool
hasNullByte s = any (\c => c == '\0') (unpack s)

-- == Required-field constants ==

requiredServiceFields : List String
requiredServiceFields = ["name", "image"]

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  [ test "NickelConfig property: all service configs have required fields" $ do
      let configs =
            [ MkServiceConfig True True
            , MkServiceConfig True True
            , MkServiceConfig True True
            , MkServiceConfig True True
            , MkServiceConfig True True
            ]
      let results = map validateServiceConfig configs
      assertTrue "all valid" (all fst results)

  , test "NickelConfig property: config without name is invalid" $ do
      let (valid, missing) = validateServiceConfig (MkServiceConfig False True)
      allPass
        [ assertTrue "invalid" (not valid)
        , assertTrue "name reported" (elem "name" missing)
        ]

  , test "NickelConfig property: config without image is invalid" $ do
      let (valid, missing) = validateServiceConfig (MkServiceConfig True False)
      allPass
        [ assertTrue "invalid" (not valid)
        , assertTrue "image reported" (elem "image" missing)
        ]

  , test "NickelConfig property: valid resource configs pass" $ do
      let configs =
            [ MkResourceConfig True True (Just "512M")
            , MkResourceConfig True True (Just "1G")
            , MkResourceConfig True True (Just "4G")
            , MkResourceConfig True True (Just "128M")
            ]
      let results = map validateResourceConfig configs
      assertTrue "all empty error lists" (all null results)

  , test "NickelConfig property: resource config missing fields fails" $ do
      let errs = validateResourceConfig (MkResourceConfig True False Nothing)
      assertTrue "errors present" (length errs > 0)

  , test "NickelConfig property: memory without unit fails" $ do
      let errs = validateResourceConfig (MkResourceConfig True True (Just "512"))
      assertTrue "errors present" (length errs > 0)

  , test "NickelConfig property: memory with invalid unit fails" $ do
      let errs = validateResourceConfig (MkResourceConfig True True (Just "512X"))
      assertTrue "errors present" (length errs > 0)

  , test "NickelConfig property: valid port specs pass" $ do
      let ports = ["80", "443", "80:80", "8080:8080", "9000:9000"]
      assertTrue "all valid" (all validatePortSpec ports)

  , test "NickelConfig property: invalid port specs fail" $ do
      let invalid =
            [ "0:80"
            , "80:0"
            , "65536:80"
            , "80:65536"
            , "abc:80"
            , "80:abc"
            , "80:80:80"
            , ""
            ]
      assertTrue "all rejected" (all (\s => not (validatePortSpec s)) invalid)

  , test "NickelConfig property: valid network drivers pass" $ do
      let errs = map validateNetworkDriver validNetworkDrivers
      assertTrue "all empty" (all null errs)

  , test "NickelConfig property: invalid network driver fails" $ do
      let invalid = ["macvlan", "custom", "BRIDGE", "Bridge"]
      let errs = map validateNetworkDriver invalid
      assertTrue "all non-empty" (all (\e => length e > 0) errs)

  , test "NickelConfig property: image names have no shell injection characters" $ do
      let safe =
            [ "nginx:1.27"
            , "postgres:16-alpine"
            , "cgr.dev/chainguard/nginx:latest"
            , "registry.example.com:5000/myapp:v1.0.0"
            ]
      allPass
        [ assertTrue "no dangerous chars" (all (\i => not (hasDangerousChar i)) safe)
        , assertTrue "no newlines/CR" (all (\i => not (hasNewlineOrCR i)) safe)
        ]

  , test "NickelConfig property: env var values have no null bytes or newlines" $ do
      let safe =
            [ "production"
            , "postgres://user:pass@db:5432/mydb"
            , "some value with spaces"
            , "/var/lib/data"
            , "v2.0.0-beta.1+build.123"
            ]
      allPass
        [ assertTrue "no null" (all (\v => not (hasNullByte v)) safe)
        , assertTrue "no LF" (all (\v => not (hasNewlineOrCR v)) safe)
        ]

  , test "NickelConfig property: REQUIRED_SERVICE_FIELDS is non-empty" $
      assertTrue "non-empty" (length requiredServiceFields > 0)

  , test "NickelConfig property: REQUIRED_SERVICE_FIELDS contains 'name' and 'image'" $
      allPass
        [ assertTrue "name" (elem "name" requiredServiceFields)
        , assertTrue "image" (elem "image" requiredServiceFields)
        ]
  ]
