-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/e2e/container_lifecycle_test.ts to Idris2.
-- 7 of 7 tests ported.
--
-- The TS file uses a mutable `class MockContainerRuntime` with a Map and
-- `throw` on bad transitions. Here we model the runtime as a pure record:
-- each operation is `Runtime -> Either String Runtime` (or returns an updated
-- record alongside the runtime). `throw` is replaced by `Left msg`; `Right v`
-- = success. Date is modelled as a Nat timestamp; `Maybe Nat` mirrors the
-- TS `?` optional-field semantics. The TS tests only ever check outcomes
-- (state change, presence in list, whether it threw), so this mapping is
-- behaviour-preserving. Test names are ASCII (hyphen-minus, straight colon).

module ContainerLifecycleTest

import Test.Spec
import Data.List
import Data.Maybe

%default covering

-- == Container status ==

data ContainerStatus = SCreated | SRunning | SStopped | SDeleted

Eq ContainerStatus where
  SCreated == SCreated = True
  SRunning == SRunning = True
  SStopped == SStopped = True
  SDeleted == SDeleted = True
  _        == _        = False

Show ContainerStatus where
  show SCreated = "created"
  show SRunning = "running"
  show SStopped = "stopped"
  show SDeleted = "deleted"

-- == Records ==

record ContainerRecord where
  constructor MkContainerRecord
  crId : String
  crName : String
  crImage : String
  crStatus : ContainerStatus
  crPid : Maybe Nat
  crCreatedAt : Nat
  crStartedAt : Maybe Nat
  crStoppedAt : Maybe Nat

record MonitoringSnapshot where
  constructor MkSnapshot
  snapContainerId : String
  snapCpuPercent : Double
  snapMemoryMib : Nat
  snapTimestampMs : Nat

record Runtime where
  constructor MkRuntime
  containers : List (String, ContainerRecord)
  monitoring : List (String, List MonitoringSnapshot)
  nextPid : Nat
  clock : Nat  -- monotonic timestamp source

emptyRuntime : Runtime
emptyRuntime = MkRuntime [] [] 1000 0

-- == Assoc-list helpers (Map<string, _> stand-in) ==

lookupAL : String -> List (String, a) -> Maybe a
lookupAL _ [] = Nothing
lookupAL k ((k', v) :: xs) = if k == k' then Just v else lookupAL k xs

upsertAL : String -> a -> List (String, a) -> List (String, a)
upsertAL k v [] = [(k, v)]
upsertAL k v ((k', v') :: xs) =
  if k == k'
    then (k, v) :: xs
    else (k', v') :: upsertAL k v xs

deleteAL : String -> List (String, a) -> List (String, a)
deleteAL _ [] = []
deleteAL k ((k', v) :: xs) =
  if k == k'
    then xs
    else (k', v) :: deleteAL k xs

hasAL : String -> List (String, a) -> Bool
hasAL k xs = case lookupAL k xs of
  Just _  => True
  Nothing => False

-- == Runtime operations ==

-- deploy: create a container in 'created' state.
deploy : String -> String -> Runtime -> Either String (Runtime, ContainerRecord)
deploy name image rt =
  if hasAL name rt.containers
    then Left ("Container '" ++ name ++ "' already exists")
    else
      let t = rt.clock
          cid = "mock-" ++ name ++ "-" ++ show t
          rec = MkContainerRecord cid name image SCreated Nothing t Nothing Nothing
          rt' = { containers := upsertAL name rec rt.containers
                , clock := S t } rt
      in Right (rt', rec)

getByName : String -> Runtime -> Either String ContainerRecord
getByName name rt = case lookupAL name rt.containers of
  Just c  => Right c
  Nothing => Left ("Container '" ++ name ++ "' not found")

-- start: transition created -> running.
start : String -> Runtime -> Either String (Runtime, ContainerRecord)
start name rt = case lookupAL name rt.containers of
  Nothing => Left ("Container '" ++ name ++ "' not found")
  Just c =>
    if c.crStatus /= SCreated
      then Left ("Cannot start container '" ++ name ++ "' in state '" ++ show c.crStatus ++ "'")
      else
        let t = rt.clock
            pid = rt.nextPid
            c' = { crStatus := SRunning
                 , crPid := Just pid
                 , crStartedAt := Just t } c
            rt' = { containers := upsertAL name c' rt.containers
                  , nextPid := S pid
                  , clock := S t } rt
        in Right (rt', c')

-- recordMetrics: append a monitoring snapshot. Container must be running.
recordMetrics : String -> Double -> Nat -> Runtime -> Either String Runtime
recordMetrics name cpu mem rt = case lookupAL name rt.containers of
  Nothing => Left ("Container '" ++ name ++ "' not found")
  Just c =>
    if c.crStatus /= SRunning
      then Left ("Cannot monitor container '" ++ name ++ "' in state '" ++ show c.crStatus ++ "'")
      else
        let t = rt.clock
            snap = MkSnapshot c.crId cpu mem t
            existing = fromMaybe [] (lookupAL name rt.monitoring)
            snaps' = existing ++ [snap]
            rt' = { monitoring := upsertAL name snaps' rt.monitoring
                  , clock := S t } rt
        in Right rt'

getMetrics : String -> Runtime -> List MonitoringSnapshot
getMetrics name rt = fromMaybe [] (lookupAL name rt.monitoring)

-- stop: transition running -> stopped.
stop : String -> Runtime -> Either String (Runtime, ContainerRecord)
stop name rt = case lookupAL name rt.containers of
  Nothing => Left ("Container '" ++ name ++ "' not found")
  Just c =>
    if c.crStatus /= SRunning
      then Left ("Cannot stop container '" ++ name ++ "' in state '" ++ show c.crStatus ++ "'")
      else
        let t = rt.clock
            c' = { crStatus := SStopped
                 , crPid := Nothing
                 , crStoppedAt := Just t } c
            rt' = { containers := upsertAL name c' rt.containers
                  , clock := S t } rt
        in Right (rt', c')

-- remove: drop a non-running container.
remove : String -> Runtime -> Either String Runtime
remove name rt = case lookupAL name rt.containers of
  Nothing => Left ("Container '" ++ name ++ "' not found")
  Just c =>
    if c.crStatus == SRunning
      then Left ("Cannot remove running container '" ++ name ++ "'")
      else Right ({ containers := deleteAL name rt.containers
                  , monitoring := deleteAL name rt.monitoring } rt)

listContainers : Runtime -> List ContainerRecord
listContainers rt = map snd rt.containers

-- == Health probe ==

data HealthStatus = Starting | Healthy | Unhealthy

Eq HealthStatus where
  Starting  == Starting  = True
  Healthy   == Healthy   = True
  Unhealthy == Unhealthy = True
  _         == _         = False

Show HealthStatus where
  show Starting  = "Starting"
  show Healthy   = "Healthy"
  show Unhealthy = "Unhealthy"

record HealthConfig where
  constructor MkHealthConfig
  hcSuccessThreshold : Nat
  hcFailureThreshold : Nat
  hcStartPeriodSeconds : Nat

evalHealth : Nat -> Nat -> Nat -> HealthConfig -> HealthStatus
evalHealth successes failures ageSeconds cfg =
  if ageSeconds < cfg.hcStartPeriodSeconds
    then Starting
    else if failures >= cfg.hcFailureThreshold
      then Unhealthy
      else if successes >= cfg.hcSuccessThreshold
        then Healthy
        else Starting

-- == Test helpers ==

-- Right-projection helpers that fall through with a flag we can test.
isRight : Either a b -> Bool
isRight (Right _) = True
isRight (Left _)  = False

isLeft : Either a b -> Bool
isLeft = not . isRight

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  [ test "E2E: full container lifecycle: deploy -> start -> monitor -> stop -> remove" $ do
      -- Step 1: deploy (create)
      case deploy "web" "nginx:1.27" emptyRuntime of
        Left err => assertTrue ("deploy failed: " ++ err) False
        Right (rt1, created) =>
          -- Step 2: start
          case start "web" rt1 of
            Left err => assertTrue ("start failed: " ++ err) False
            Right (rt2, running) =>
              -- Step 3: monitor (3 snapshots)
              case recordMetrics "web" 12.5 64 rt2 of
                Left err => assertTrue ("metric 1 failed: " ++ err) False
                Right rt3 => case recordMetrics "web" 15.0 68 rt3 of
                  Left err => assertTrue ("metric 2 failed: " ++ err) False
                  Right rt4 => case recordMetrics "web" 10.0 62 rt4 of
                    Left err => assertTrue ("metric 3 failed: " ++ err) False
                    Right rt5 =>
                      let metrics = getMetrics "web" rt5 in
                      -- Step 4: stop
                      case stop "web" rt5 of
                        Left err => assertTrue ("stop failed: " ++ err) False
                        Right (rt6, stopped) =>
                          -- Step 5: remove
                          case remove "web" rt6 of
                            Left err => assertTrue ("remove failed: " ++ err) False
                            Right rt7 =>
                              let firstId = case metrics of
                                              (h :: _) => h.snapContainerId
                                              []       => "" in
                              allPass
                                [ assertEq created.crStatus SCreated
                                , assertEq created.crName "web"
                                , assertEq created.crImage "nginx:1.27"
                                , assertTrue "startedAt not set before start" (isNothing created.crStartedAt)
                                , assertEq running.crStatus SRunning
                                , assertTrue "running has PID" (isJust running.crPid)
                                , assertTrue "startedAt set after start" (isJust running.crStartedAt)
                                , assertEq (length metrics) 3
                                , assertTrue "all CPU in [0,100]"
                                    (all (\m => m.snapCpuPercent >= 0.0 && m.snapCpuPercent <= 100.0) metrics)
                                , assertTrue "all memory non-negative"
                                    (all (\m => m.snapMemoryMib >= 0) metrics)
                                , assertEq firstId created.crId
                                , assertEq stopped.crStatus SStopped
                                , assertTrue "stopped has no PID" (isNothing stopped.crPid)
                                , assertTrue "stoppedAt set after stop" (isJust stopped.crStoppedAt)
                                , assertEq (length (listContainers rt7)) 0
                                ]

  , test "E2E: multi-container compose: all services deploy in dependency order" $ do
      let services : List (String, String)
          services = [ ("db",  "postgres:16-alpine")
                     , ("api", "myapp:2.0")
                     , ("web", "nginx:1.27")
                     ]
          step : Either String Runtime -> (String, String) -> Either String Runtime
          step (Left e) _ = Left e
          step (Right rt) (n, img) = case deploy n img rt of
            Left e => Left e
            Right (rt', _) => case start n rt' of
              Left e => Left e
              Right (rt'', _) => Right rt''
      case foldl step (Right emptyRuntime) services of
        Left err => assertTrue ("compose deploy failed: " ++ err) False
        Right rt =>
          let all3 = listContainers rt
              dbOk  = case getByName "db"  rt of Right c => c.crImage == "postgres:16-alpine" && isJust c.crPid; _ => False
              apiOk = case getByName "api" rt of Right c => c.crImage == "myapp:2.0"          && isJust c.crPid; _ => False
              webOk = case getByName "web" rt of Right c => c.crImage == "nginx:1.27"         && isJust c.crPid; _ => False
          in allPass
               [ assertEq (length all3) 3
               , assertTrue "all running" (all (\c => c.crStatus == SRunning) all3)
               , assertTrue "db image + pid"  dbOk
               , assertTrue "api image + pid" apiOk
               , assertTrue "web image + pid" webOk
               ]

  , test "E2E: monitoring threshold breach triggers alert" $ do
      let readings : List Double
          readings = [20.0, 45.0, 75.0, 90.0, 95.0]
          step : Either String Runtime -> Double -> Either String Runtime
          step (Left e) _ = Left e
          step (Right rt) cpu = recordMetrics "api" cpu 256 rt
      case deploy "api" "myapp:2.0" emptyRuntime of
        Left err => assertTrue ("deploy failed: " ++ err) False
        Right (rt1, _) => case start "api" rt1 of
          Left err => assertTrue ("start failed: " ++ err) False
          Right (rt2, _) => case foldl step (Right rt2) readings of
            Left err => assertTrue ("record failed: " ++ err) False
            Right rt3 =>
              let metrics = getMetrics "api" rt3
                  cpuThreshold : Double
                  cpuThreshold = 80.0
                  alerts = filter (\m => m.snapCpuPercent > cpuThreshold) metrics
              in allPass
                   [ assertEq (length metrics) (length readings)
                   , assertEq (length alerts) 2
                   , assertTrue "all alerts above threshold"
                       (all (\a => a.snapCpuPercent > cpuThreshold) alerts)
                   ]

  , test "E2E: deploying duplicate container is rejected" $ do
      case deploy "db" "postgres:16-alpine" emptyRuntime of
        Left err => assertTrue ("first deploy failed: " ++ err) False
        Right (rt1, _) =>
          let second = deploy "db" "postgres:16-alpine" rt1 in
          assertTrue "duplicate deploy rejected" (isLeft second)

  , test "E2E: starting an already-running container is rejected" $ do
      case deploy "web" "nginx:1.27" emptyRuntime of
        Left err => assertTrue ("deploy failed: " ++ err) False
        Right (rt1, _) => case start "web" rt1 of
          Left err => assertTrue ("first start failed: " ++ err) False
          Right (rt2, _) =>
            let second = start "web" rt2 in
            assertTrue "second start rejected" (isLeft second)

  , test "E2E: removing a running container is rejected" $ do
      case deploy "web" "nginx:1.27" emptyRuntime of
        Left err => assertTrue ("deploy failed: " ++ err) False
        Right (rt1, _) => case start "web" rt1 of
          Left err => assertTrue ("start failed: " ++ err) False
          Right (rt2, _) =>
            let bad = remove "web" rt2 in
            assertTrue "remove of running rejected" (isLeft bad)

  , test "E2E: health probe evaluates correctly" $ do
      let cfg = MkHealthConfig 1 3 30
      allPass
        [ assertEq (evalHealth 0 0 10 cfg) Starting
        , assertEq (evalHealth 1 0 45 cfg) Healthy
        , assertEq (evalHealth 0 3 45 cfg) Unhealthy
        , assertEq (evalHealth 0 2 45 cfg) Starting
        ]
  ]
