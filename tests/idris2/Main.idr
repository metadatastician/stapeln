-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

module Main

import Test.Spec
import ContainerTypesTest
import NickelConfigPropertiesTest
import SecurityAspectTest
import LayerInvariantsTest
import ContainerLifecycleTest
import StapelnTest
import System

%default covering

main : IO ()
main = do
  (p1, f1) <- runTestSuite "ContainerTypesTest" ContainerTypesTest.allSuites
  (p2, f2) <- runTestSuite "NickelConfigPropertiesTest" NickelConfigPropertiesTest.allSuites
  (p3, f3) <- runTestSuite "SecurityAspectTest" SecurityAspectTest.allSuites
  (p4, f4) <- runTestSuite "LayerInvariantsTest" LayerInvariantsTest.allSuites
  (p5, f5) <- runTestSuite "ContainerLifecycleTest" ContainerLifecycleTest.allSuites
  (p6, f6) <- runTestSuite "StapelnTest" StapelnTest.allSuites
  let totalPassed = p1 + p2 + p3 + p4 + p5 + p6
  let totalFailed = f1 + f2 + f3 + f4 + f5 + f6
  putStrLn ""
  putStrLn $ "=== Total: " ++ show totalPassed ++ " passed, " ++ show totalFailed ++ " failed ==="
  if totalFailed > 0
    then exitWith (ExitFailure 1)
    else pure ()
