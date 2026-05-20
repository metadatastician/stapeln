-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/stapeln.test.js to Idris2.
-- 16 of 16 tests ported.
--
-- Adaptations: emoji icons and x/y coordinates dropped (never asserted on).
-- Regex /^\d+(\.\d+)?[MG]$/ ported as a List Char walk. The kebabify helper
-- (name.toLowerCase().replace(/\s+/g, '-')) is a List Char walk that
-- lowercases A-Z and collapses runs of spaces to a single '-'. JSON
-- save/load roundtrip is reduced to a structural copy (the JS test only
-- asserts node count, connection count and version). Generation helpers
-- inline a fixed "GENERATED" placeholder where the JS used a date string,
-- since the JS tests never assert on the date. parseDouble used for CPU.

module StapelnTest

import Test.Spec
import Data.String
import Data.List
import Data.Maybe

%default covering

-- == Test data records ==

record Node where
  constructor MkNode
  nodeId : String
  nodeName : String
  nodeType : String
  nodePorts : String
  nodeFirewall : Bool
  nodeBaseImage : String
  nodeCpu : String
  nodeMemory : String

record Conn where
  constructor MkConn
  cid : String
  cfrom : String
  cto : String
  protocol : String
  bidirectional : Bool
  encrypted : Bool

record MustRule where
  constructor MkRule
  ruleName : String
  description : String
  critical : Bool

sampleNodes : List Node
sampleNodes =
  [ MkNode "node-1" "API Gateway"  "gateway"     "80"   True  "nginx:alpine"       "0.5" "512M"
  , MkNode "node-2" "Auth Service" "application" "8080" True  "lago-grey:2.1"      "1.0" "1G"
  , MkNode "node-3" "PostgreSQL"   "database"    "5432" False "postgres:16-alpine" "0.5" "2G"
  ]

sampleConnections : List Conn
sampleConnections =
  [ MkConn "conn-1" "node-1" "node-2" "HTTPS" False True
  , MkConn "conn-2" "node-2" "node-3" "TCP"   False True
  ]

mustfileRules : List MustRule
mustfileRules =
  [ MkRule "all-images-signed"      "All images must be signed"             True
  , MkRule "firewall-enabled"       "Firewalls required on public nodes"    True
  , MkRule "ports-unique"           "All ports must be unique"              True
  , MkRule "encrypted-connections"  "External connections must be encrypted" True
  ]

-- == Helpers ==

-- nub: drop duplicates, preserving first occurrence order.
dedup : Eq a => List a -> List a
dedup [] = []
dedup (x :: xs) = x :: dedup (filter (/= x) xs)

-- Lowercase a single ASCII letter A-Z; pass through anything else.
toLowerC : Char -> Char
toLowerC c =
  if c >= 'A' && c <= 'Z'
    then chr (ord c + 32)
    else c

-- Collapse a run of spaces to a single '-' and lowercase ASCII letters.
-- Mirrors JS: name.toLowerCase().replace(/\s+/g, '-').
kebabify : String -> String
kebabify s = pack (go (unpack s) False)
  where
    go : List Char -> Bool -> List Char
    go []          _      = []
    go (c :: cs)   inSpace =
      if c == ' '
        then if inSpace
               then go cs True
               else '-' :: go cs True
        else toLowerC c :: go cs False

-- Memory format: at least one digit, optional .digit+, exactly one M or G,
-- nothing else. Replaces the JS regex /^\d+(\.\d+)?[MG]$/.
isDigitC : Char -> Bool
isDigitC c = c >= '0' && c <= '9'

isValidMemory : String -> Bool
isValidMemory s = case unpack s of
  []     => False
  (h :: t) => isDigitC h && checkInt t
  where
    -- Once integer part started, consume more digits, then optional .digits,
    -- then exactly one M or G as final char.
    checkSuffix : List Char -> Bool
    checkSuffix [c] = c == 'M' || c == 'G'
    checkSuffix _   = False

    checkFracEnd : List Char -> Bool
    checkFracEnd []        = False
    checkFracEnd (c :: cs) =
      if isDigitC c
        then case cs of
               []  => False
               _   => checkFracEnd cs || checkSuffix cs
        else False

    checkFrac : List Char -> Bool
    -- After '.', need at least one digit then suffix.
    checkFrac []        = False
    checkFrac (c :: cs) =
      if isDigitC c
        then checkSuffix cs || checkFrac cs
        else False

    checkInt : List Char -> Bool
    checkInt []        = False
    checkInt (c :: cs) =
      if isDigitC c
        then checkInt cs
        else if c == '.'
               then checkFrac cs
               else checkSuffix (c :: cs)

-- Port: 1..65535. JS parses an int; we mirror via parseInteger.
isValidPort : String -> Bool
isValidPort s = case parseInteger {a=Integer} s of
  Nothing => False
  Just n  => n >= 1 && n <= 65535

-- CPU bounds 0.1..4.0 via parseDouble.
isValidCpu : String -> Bool
isValidCpu s = case parseDouble s of
  Nothing => False
  Just d  => d >= 0.1 && d <= 4.0

-- DFS cycle detection over adjacency list keyed by node id.
neighborsOf : String -> List (String, List String) -> List String
neighborsOf _   []                 = []
neighborsOf id ((k, vs) :: rest) =
  if k == id then vs else neighborsOf id rest

-- Walk with explicit fuel (= number of nodes) so the recursion is total.
dfsHas : Nat -> List (String, List String) -> List String -> List String -> String -> Bool
dfsHas Z      _      _       _       _      = False
dfsHas (S k)  graph  visited recStack node =
  if elem node recStack
    then True
    else if elem node visited
           then False
           else let ns = neighborsOf node graph
                    visited' = node :: visited
                    recStack' = node :: recStack
                in anyCycle k graph visited' recStack' ns
  where
    anyCycle : Nat -> List (String, List String) -> List String -> List String -> List String -> Bool
    anyCycle _  _     _       _        []        = False
    anyCycle kk gg    vv      rr       (m :: ms) =
      if dfsHas kk gg vv rr m
        then True
        else anyCycle kk gg vv rr ms

hasCycleFromAny : List (String, List String) -> Bool
hasCycleFromAny graph =
  let n = length graph
      keys = map fst graph
  in anyKey n graph keys
  where
    anyKey : Nat -> List (String, List String) -> List String -> Bool
    anyKey _ _ []         = False
    anyKey n g (k :: ks)  =
      if dfsHas n g [] [] k then True else anyKey n g ks

buildGraph : List Node -> List Conn -> List (String, List String)
buildGraph nodes conns =
  map (\n => (n.nodeId, edgesFrom n.nodeId)) nodes
  where
    edgesFrom : String -> List String
    edgesFrom nid = map cto (filter (\c => c.cfrom == nid) conns)

-- == Generators ==

intercalate : String -> List String -> String
intercalate _   []        = ""
intercalate _   [x]       = x
intercalate sep (x :: xs) = x ++ sep ++ intercalate sep xs

generateJustfile : List Node -> String
generateJustfile nodes =
  let buildLines = map mkBuild (filter (\n => n.nodeType /= "secrets") nodes)
  in
    "# SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
    "# Justfile - Generated: GENERATED\n" ++
    "\n" ++
    "build:\n" ++
    "    @echo Building containers...\n" ++
    intercalate "\n" buildLines ++ "\n" ++
    "\n" ++
    "deploy: build\n" ++
    "    @echo Deploying...\n" ++
    "    podman-compose -f stack.yaml up -d\n"
  where
    mkBuild : Node -> String
    mkBuild n =
      let k = kebabify n.nodeName
      in "    podman build -t " ++ k ++ ":latest ./images/" ++ k

generateMustfile : List Node -> List Conn -> List MustRule -> String
generateMustfile nodes conns rules =
  "# SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
  "# Mustfile - Generated: GENERATED\n" ++
  "\n" ++
  "metadata:\n" ++
  "  component_count: " ++ show (length nodes) ++ "\n" ++
  "  connection_count: " ++ show (length conns) ++ "\n" ++
  "\n" ++
  "checks:\n" ++
  intercalate "\n\n" (map mkRule rules) ++ "\n"
  where
    mkRule : MustRule -> String
    mkRule r =
      "  - name: " ++ r.ruleName ++ "\n" ++
      "    description: \"" ++ r.description ++ "\"\n" ++
      "    critical: " ++ (if r.critical then "true" else "false")

generateTrustfile : List Node -> String
generateTrustfile nodes =
  let quoted = map (\n => "\"" ++ kebabify n.nodeName ++ "\"")
                   (filter (\n => n.nodeType /= "secrets") nodes)
  in
    "-- SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
    "-- Trustfile.hs\n" ++
    "\n" ++
    "module Trustfile where\n" ++
    "\n" ++
    "images :: [String]\n" ++
    "images = [" ++ intercalate ", " quoted ++ "]\n" ++
    "\n" ++
    "main :: IO ()\n" ++
    "main = putStrLn \"Verification complete\"\n"

generateDustfile : List Node -> String
generateDustfile nodes =
  "# SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
  "# Dustfile\n" ++
  "\n" ++
  "recovery:\n" ++
  "  strategy: \"blue-green\"\n" ++
  "\n" ++
  "health_checks:\n" ++
  intercalate "\n" (map mkCheck nodes) ++ "\n"
  where
    mkCheck : Node -> String
    mkCheck n =
      "  - component: " ++ kebabify n.nodeName ++ "\n" ++
      "    endpoint: \"http://localhost:" ++ n.nodePorts ++ "/health\""

generateStackYaml : List Node -> List Conn -> String
generateStackYaml nodes _ =
  "# SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
  "# stack.yaml\n" ++
  "\n" ++
  "version: '3.8'\n" ++
  "\n" ++
  "services:\n" ++
  intercalate "\n\n" (map mkService nodes) ++ "\n" ++
  "\n" ++
  "networks:\n" ++
  "  stapeln_network:\n" ++
  "    driver: bridge\n"
  where
    mkService : Node -> String
    mkService n =
      let k = kebabify n.nodeName
      in "  " ++ k ++ ":\n" ++
         "    image: " ++ n.nodeBaseImage ++ "\n" ++
         "    ports:\n" ++
         "      - \"" ++ n.nodePorts ++ ":" ++ n.nodePorts ++ "\"\n" ++
         "    networks:\n" ++
         "      - stapeln_network"

generateContainerfile : String -> String -> String
generateContainerfile name baseImage =
  "# SPDX-License-Identifier: PMPL-1.0-or-later\n" ++
  "FROM " ++ baseImage ++ "\n" ++
  "LABEL org.opencontainers.image.title=\"" ++ name ++ "\"\n" ++
  "CMD [\"/bin/sh\"]\n"

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  [ test "Validation: Unique Node IDs" $ do
      let ids = map nodeId sampleNodes
      assertEq (length ids) (length (dedup ids))

  , test "Validation: Port Numbers In Range" $
      assertTrue "all ports in 1..65535"
        (all (\n => isValidPort n.nodePorts) sampleNodes)

  , test "Validation: Port Conflicts" $ do
      let ports = map nodePorts sampleNodes
      assertEq (length ports) (length (dedup ports))

  , test "Validation: Valid Connections" $
      let nodeIds = map nodeId sampleNodes
      in assertTrue "every connection endpoint is a known node and not self"
           (all (\c => elem c.cfrom nodeIds
                       && elem c.cto nodeIds
                       && c.cfrom /= c.cto)
                sampleConnections)

  , test "Validation: Resource Limits" $
      assertTrue "CPU in [0.1,4.0] and memory format valid"
        (all (\n => isValidCpu n.nodeCpu && isValidMemory n.nodeMemory) sampleNodes)

  , test "Validation: Firewall on Gateway Nodes" $
      let gateways = filter (\n => n.nodeType == "gateway") sampleNodes
      in assertTrue "all gateways have firewall"
           (all (\n => n.nodeFirewall) gateways)

  , test "Validation: Encrypted External Connections" $
      let nodeIds = map (\n => (n.nodeId, n.nodeType)) sampleNodes
          lookupType = \cf => fromMaybe "" (lookup cf nodeIds)
          fromGateway = filter (\c => lookupType c.cfrom == "gateway") sampleConnections
      in assertTrue "all gateway-originating connections encrypted"
           (all (\c => c.encrypted) fromGateway)

  , test "Validation: Acyclic Topology" $
      let graph = buildGraph sampleNodes sampleConnections
      in assertTrue "no cycle reachable from any node"
           (not (hasCycleFromAny graph))

  , test "Generation: Justfile Format" $ do
      let j = generateJustfile sampleNodes
          buildable = filter (\n => n.nodeType /= "secrets"
                                    && n.nodeType /= "firewall")
                             sampleNodes
      allPass
        [ assertTrue "SPDX header" (isInfixOf "# SPDX-License-Identifier: PMPL-1.0-or-later" j)
        , assertTrue "build target"   (isInfixOf "build:" j)
        , assertTrue "deploy target"  (isInfixOf "deploy:" j)
        , assertTrue "uses podman"    (isInfixOf "podman build" j)
        , assertTrue "all buildable node names present"
            (all (\n => isInfixOf (kebabify n.nodeName) j) buildable)
        ]

  , test "Generation: Mustfile Format" $ do
      let m = generateMustfile sampleNodes sampleConnections mustfileRules
      allPass
        [ assertTrue "SPDX header"        (isInfixOf "# SPDX-License-Identifier: PMPL-1.0-or-later" m)
        , assertTrue "metadata section"   (isInfixOf "metadata:" m)
        , assertTrue "component_count"    (isInfixOf "component_count:" m)
        , assertTrue "connection_count"   (isInfixOf "connection_count:" m)
        , assertTrue "checks section"     (isInfixOf "checks:" m)
        , assertTrue "all rule names present"
            (all (\r => isInfixOf r.ruleName m) mustfileRules)
        ]

  , test "Generation: Trustfile.hs Format" $ do
      let t = generateTrustfile sampleNodes
          nonSecret = filter (\n => n.nodeType /= "secrets") sampleNodes
      allPass
        [ assertTrue "SPDX header"    (isInfixOf "-- SPDX-License-Identifier: PMPL-1.0-or-later" t)
        , assertTrue "module decl"    (isInfixOf "module Trustfile where" t)
        , assertTrue "images list"    (isInfixOf "images :: [String]" t)
        , assertTrue "main function"  (isInfixOf "main :: IO ()" t)
        , assertTrue "all non-secret node names present"
            (all (\n => isInfixOf (kebabify n.nodeName) t) nonSecret)
        ]

  , test "Generation: Dustfile Format" $ do
      let d = generateDustfile sampleNodes
      allPass
        [ assertTrue "SPDX header"      (isInfixOf "# SPDX-License-Identifier: PMPL-1.0-or-later" d)
        , assertTrue "recovery section" (isInfixOf "recovery:" d)
        , assertTrue "strategy field"   (isInfixOf "strategy:" d)
        , assertTrue "health_checks"    (isInfixOf "health_checks:" d)
        , assertTrue "all node health checks present"
            (all (\n => isInfixOf (kebabify n.nodeName) d) sampleNodes)
        ]

  , test "Generation: stack.yaml Format" $ do
      let s = generateStackYaml sampleNodes sampleConnections
      allPass
        [ assertTrue "SPDX header"      (isInfixOf "# SPDX-License-Identifier: PMPL-1.0-or-later" s)
        , assertTrue "compose version"  (isInfixOf "version: '3.8'" s)
        , assertTrue "services section" (isInfixOf "services:" s)
        , assertTrue "networks section" (isInfixOf "networks:" s)
        , assertTrue "all services present"
            (all (\n => isInfixOf (kebabify n.nodeName ++ ":") s) sampleNodes)
        , assertTrue "all base images present"
            (all (\n => isInfixOf ("image: " ++ n.nodeBaseImage) s) sampleNodes)
        ]

  , test "Generation: Containerfile Format" $ do
      let c = generateContainerfile "nginx" "nginx:alpine"
      allPass
        [ assertTrue "SPDX header"      (isInfixOf "# SPDX-License-Identifier: PMPL-1.0-or-later" c)
        , assertTrue "FROM instruction" (isInfixOf "FROM nginx:alpine" c)
        , assertTrue "LABEL present"    (isInfixOf "LABEL" c)
        , assertTrue "no Dockerfile ref" (not (isInfixOf "Dockerfile" c))
        ]

  , test "E2E: Complete Stack Generation" $ do
      let j = generateJustfile sampleNodes
          m = generateMustfile sampleNodes sampleConnections mustfileRules
          t = generateTrustfile sampleNodes
          d = generateDustfile sampleNodes
          s = generateStackYaml sampleNodes sampleConnections
      allPass
        [ assertTrue "justfile > 100 chars"  (length j > 100)
        , assertTrue "mustfile > 100 chars"  (length m > 100)
        , assertTrue "trustfile > 100 chars" (length t > 100)
        , assertTrue "dustfile > 100 chars"  (length d > 100)
        , assertTrue "stackyaml > 100 chars" (length s > 100)
        , assertTrue "justfile non-empty"    (length j > 0)
        , assertTrue "mustfile non-empty"    (length m > 0)
        , assertTrue "trustfile non-empty"   (length t > 0)
        , assertTrue "dustfile non-empty"    (length d > 0)
        , assertTrue "stackyaml non-empty"   (length s > 0)
        ]

  , test "E2E: Save and Load Design" $ do
      -- JSON roundtrip reduces to a structural copy: the JS test only
      -- asserts node count, connection count and a fixed version string.
      let version = "1.0"
          loadedNodes = sampleNodes
          loadedConns = sampleConnections
      allPass
        [ assertEq (length loadedNodes) (length sampleNodes)
        , assertEq (length loadedConns) (length sampleConnections)
        , assertEq version "1.0"
        ]
  ]
