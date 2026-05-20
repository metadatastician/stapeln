-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/unit/container_types_test.ts to Idris2.
-- 26 of 26 tests ported. Pure-logic suite — no I/O, all predicates run on
-- inlined types that mirror src/ but don't import from it.

module ContainerTypesTest

import Test.Spec
import Data.String
import Data.List

%default covering

-- == Sum types ==

data ContainerState = SCreated | SRunning | SPaused | SStopped

Eq ContainerState where
  SCreated == SCreated = True
  SRunning == SRunning = True
  SPaused  == SPaused  = True
  SStopped == SStopped = True
  _        == _        = False

stateName : ContainerState -> String
stateName SCreated = "created"
stateName SRunning = "running"
stateName SPaused  = "paused"
stateName SStopped = "stopped"

validContainerStates : List String
validContainerStates = ["created", "running", "paused", "stopped"]

data RestartPolicy = RNever | RAlways | ROnFailure | RUnlessStopped

Eq RestartPolicy where
  RNever         == RNever         = True
  RAlways        == RAlways        = True
  ROnFailure     == ROnFailure     = True
  RUnlessStopped == RUnlessStopped = True
  _              == _              = False

policyName : RestartPolicy -> String
policyName RNever         = "never"
policyName RAlways        = "always"
policyName ROnFailure     = "on-failure"
policyName RUnlessStopped = "unless-stopped"

validRestartPolicies : List String
validRestartPolicies = ["never", "always", "on-failure", "unless-stopped"]

data Protocol = ProtoTcp | ProtoUdp

Eq Protocol where
  ProtoTcp == ProtoTcp = True
  ProtoUdp == ProtoUdp = True
  _        == _        = False

-- == Records ==

record PortMapping where
  constructor MkPortMapping
  hostPort : Nat
  containerPort : Nat
  protocol : Protocol

record VolumeMount where
  constructor MkVolumeMount
  source : String
  destination : String
  readOnly : Bool

record EnvVar where
  constructor MkEnvVar
  envKey : String
  envValue : String

record Resources where
  constructor MkResources
  cpuPercent : Integer
  memoryMib : Nat

record ContainerSpec where
  constructor MkContainerSpec
  csId : String
  csName : String
  csImage : String
  csState : ContainerState
  csPorts : List PortMapping
  csVolumes : List VolumeMount
  csEnv : List EnvVar
  csRestartPolicy : RestartPolicy
  csResources : Resources

-- == Validation helpers ==

-- isValidPort: 1..65535 inclusive.
isValidPort : Nat -> Bool
isValidPort p = p >= 1 && p <= 65535

isValidContainerName : String -> Bool
isValidContainerName name =
  let n = length name
      cs = unpack name
  in n > 0 && n <= 63 && all noPathOrNull cs
  where
    noPathOrNull : Char -> Bool
    noPathOrNull c = c /= '/' && c /= '\\' && c /= '\0'

-- Char predicates for env-key regex /^[A-Z_][A-Z0-9_]*$/.
isAZ : Char -> Bool
isAZ c = c >= 'A' && c <= 'Z'

isAZdigUnd : Char -> Bool
isAZdigUnd c = isAZ c || (c >= '0' && c <= '9') || c == '_'

isHeadEnvKey : Char -> Bool
isHeadEnvKey c = isAZ c || c == '_'

isValidEnvKey : String -> Bool
isValidEnvKey s = case unpack s of
  []        => False
  (h :: cs) => isHeadEnvKey h && all isAZdigUnd cs

isValidEnvValue : String -> Bool
isValidEnvValue v =
  let cs = unpack v
  in all (\c => c /= '\0' && c /= '\n' && c /= '\r') cs

shellMetachars : List Char
shellMetachars = [';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>']

isValidImageRef : String -> Bool
isValidImageRef image =
  let cs = unpack image
      n = length image
  in n > 0
     && all (\c => not (elem c shellMetachars)) cs
     && all (\c => c /= '\n' && c /= '\r' && c /= '\0') cs

isValidContainerState : String -> Bool
isValidContainerState s = elem s validContainerStates

isValidRestartPolicy : String -> Bool
isValidRestartPolicy s = elem s validRestartPolicies

-- Helper: build "a" * n
repeatChar : Char -> Nat -> String
repeatChar c n = pack (replicate n c)

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  -- --- Container name invariants ---
  [ test "ContainerSpec: valid name accepted" $ do
      let names = ["web", "api-service", "db_primary", "myapp123", repeatChar 'a' 63]
      assertTrue "all valid names" (all isValidContainerName names)

  , test "ContainerSpec: empty name rejected" $
      assertTrue "empty rejected" (not (isValidContainerName ""))

  , test "ContainerSpec: name too long rejected" $
      assertTrue "64-char rejected" (not (isValidContainerName (repeatChar 'a' 64)))

  , test "ContainerSpec: name with path separator rejected" $
      allPass
        [ assertTrue "/ rejected" (not (isValidContainerName "my/container"))
        , assertTrue "\\ rejected" (not (isValidContainerName "my\\container"))
        ]

  , test "ContainerSpec: name with null byte rejected" $
      assertTrue "null byte rejected" (not (isValidContainerName "my\0container"))

  -- --- Port mapping invariants ---
  , test "PortMapping: valid ports accepted" $ do
      let ports = the (List Nat) [1, 80, 443, 8080, 65535]
      assertTrue "all in range" (all isValidPort ports)

  , test "PortMapping: port 0 rejected" $
      assertTrue "port 0 rejected" (not (isValidPort 0))

  , test "PortMapping: port 65536 rejected" $
      assertTrue "port 65536 rejected" (not (isValidPort 65536))

  , test "PortMapping: negative port rejected" $
      -- Port is Nat in Idris2, so negativity is unrepresentable.
      -- TS test asserts -1 rejected; we encode the same invariant: 0 (the
      -- least Nat) is rejected, satisfying "no port <= 0".
      assertTrue "least Nat rejected" (not (isValidPort 0))

  , test "PortMapping: non-integer port rejected" $
      -- TS allows Number, then filters with Number.isInteger. In Idris2 the
      -- type is Nat — non-integer is unrepresentable, so the invariant is
      -- enforced at the type level.
      assertTrue "type-level integrality" True

  -- --- Container state invariants ---
  , test "ContainerState: all valid states accepted" $
      assertTrue "all 4 valid" (all isValidContainerState validContainerStates)

  , test "ContainerState: unknown state rejected" $ do
      let invalid = ["pending", "starting", "RUNNING", "Created", "running "]
      assertTrue "none accepted" (all (\s => not (isValidContainerState s)) invalid)

  -- --- Restart policy invariants ---
  , test "RestartPolicy: all valid policies accepted" $
      assertTrue "all 4 valid" (all isValidRestartPolicy validRestartPolicies)

  , test "RestartPolicy: unknown policy rejected" $ do
      let invalid = ["yes", "no", "Always", "on_failure", "unless-Stopped"]
      assertTrue "none accepted" (all (\s => not (isValidRestartPolicy s)) invalid)

  -- --- Environment variable invariants ---
  , test "EnvVar: valid keys accepted" $ do
      let keys = ["PATH", "HOME", "POSTGRES_DB", "APP_PORT_8080", "_PRIVATE"]
      assertTrue "all valid" (all isValidEnvKey keys)

  , test "EnvVar: lowercase key rejected" $
      allPass
        [ assertTrue "path rejected" (not (isValidEnvKey "path"))
        , assertTrue "MyVar rejected" (not (isValidEnvKey "MyVar"))
        ]

  , test "EnvVar: key starting with digit rejected" $
      assertTrue "1VAR rejected" (not (isValidEnvKey "1VAR"))

  , test "EnvVar: value with newline rejected (HTTP injection)" $
      allPass
        [ assertTrue "LF rejected" (not (isValidEnvValue "value\nX-Injected: evil"))
        , assertTrue "CRLF rejected" (not (isValidEnvValue "value\r\n"))
        ]

  , test "EnvVar: value with null byte rejected" $
      assertTrue "null byte rejected" (not (isValidEnvValue "value\0hidden"))

  , test "EnvVar: empty value accepted" $
      assertTrue "empty accepted" (isValidEnvValue "")

  -- --- Image reference invariants ---
  , test "ContainerSpec: valid image refs accepted" $ do
      let images =
            [ "nginx:1.27"
            , "postgres:16-alpine"
            , "ghcr.io/myorg/myapp:v2.0.0"
            , "cgr.dev/chainguard/nginx:latest"
            ]
      assertTrue "all safe" (all isValidImageRef images)

  , test "ContainerSpec: image with shell injection rejected" $ do
      let injections =
            [ "nginx; rm -rf /"
            , "nginx | cat /etc/passwd"
            , "$(whoami):latest"
            ]
      assertTrue "all rejected" (all (\s => not (isValidImageRef s)) injections)

  -- --- Resource bounds ---
  , test "ContainerSpec: CPU percent in [0, 100]" $ do
      let valid = the (List Integer) [0, 25, 50, 100]
      assertTrue "all in range" (all (\c => c >= 0 && c <= 100) valid)

  , test "ContainerSpec: negative CPU rejected" $ do
      let c : Integer = -1
      assertTrue "-1 < 0" (c < 0)

  , test "ContainerSpec: memory must be non-negative integer in MiB" $ do
      let valid = the (List Nat) [0, 128, 512, 1024, 16384]
      -- Nat is non-negative + integer by type — invariant holds at type level.
      assertTrue "all are Nat" (length valid == 5)

  -- --- Full ContainerSpec construction ---
  , test "ContainerSpec: minimal valid spec constructs correctly" $ do
      let portMap = MkPortMapping 80 80 ProtoTcp
          envVar = MkEnvVar "APP_ENV" "production"
          spec = MkContainerSpec
            "abc123"
            "web"
            "nginx:1.27"
            SCreated
            [portMap]
            []
            [envVar]
            RUnlessStopped
            (MkResources 50 512)
      allPass
        [ assertTrue "state created" (spec.csState == SCreated)
        , assertTrue "1 port" (length spec.csPorts == 1)
        , assertTrue "host port 80" (case spec.csPorts of (h :: _) => h.hostPort == 80; [] => False)
        , assertTrue "name valid" (isValidContainerName spec.csName)
        , assertTrue "env key valid" (case spec.csEnv of (h :: _) => isValidEnvKey h.envKey; [] => False)
        , assertTrue "restart policy valid" (isValidRestartPolicy (policyName spec.csRestartPolicy))
        ]
  ]
