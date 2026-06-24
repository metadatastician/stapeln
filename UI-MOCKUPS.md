<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
# stapeln Visual UI Mockups: "Spaceship Customizer" Style

**Design Philosophy**: Like customizing a spaceship in a game - choose components, see stats update in real-time, get warnings about vulnerabilities

---

## Page 1: Component Selection & Attack Surface Analyzer

```
┌─────────────────────────────────────────────────────────────────────┐
│ stapeln - Container Stack Designer                    [user@host] ⚙️│
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────┐  ┌────────────────────────────────────┐ │
│  │ Component Palette     │  │ Stack Visualization                │ │
│  ├──────────────────────┤  │                                    │ │
│  │                       │  │  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │ │
│  │ 🏔️  Cerro Torre      │  │  ┃ Cerro Torre (Build)        ┃ │ │
│  │     Container Builder │  │  ┃ Status: ✅ Active           ┃ │ │
│  │                       │  │  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │ │
│  │ 🛡️  Svalinn          │  │             ▼                      │ │
│  │     Edge Gateway      │  │  ┌─────────────────────────────┐ │ │
│  │                       │  │  │ Svalinn (Gateway)            │ │ │
│  │ 🌉  selur            │  │  │ Status: ⚠️  Port 22 exposed  │ │ │
│  │     IPC Bridge        │  │  └─────────────────────────────┘ │ │
│  │                       │  │             ▼                      │ │
│  │ ⚔️  Vörðr             │  │  ┌─────────────────────────────┐ │ │
│  │     Runtime           │  │  │ nginx (Web Server)           │ │ │
│  │                       │  │  │ Status: ✅ Healthy           │ │ │
│  │ 🐳  Containers        │  │  └─────────────────────────────┘ │ │
│  │   • nginx             │  │             ▼                      │ │
│  │   • postgres          │  │  ┌─────────────────────────────┐ │ │
│  │   • redis             │  │  │ postgres (Database)          │ │ │
│  │                       │  │  │ Status: ❌ No backup volume  │ │ │
│  └──────────────────────┘  │  └─────────────────────────────┘ │ │
│                             │             ▼                      │ │
│                             │  ╔═══════════════════════════════╗ │ │
│                             │  ║ Supply Chain Verification     ║ │ │
│                             │  ║ ✅ Signatures verified        ║ │ │
│                             │  ║ ✅ SBOM present               ║ │ │
│                             │  ╚═══════════════════════════════╝ │ │
│                             └────────────────────────────────────┘ │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ 🎯 Attack Surface Analysis                                   │   │
│  ├─────────────────────────────────────────────────────────────┤   │
│  │                                                               │   │
│  │  Overall Security Score: 67/100  🟡                          │   │
│  │  ██████████████░░░░░░░░░░░░░░                                │   │
│  │                                                               │   │
│  │  ❌ CRITICAL (Fix Now!)                                      │   │
│  │   • SSH Port 22 exposed to internet                          │   │
│  │     ⚠️  This allows brute-force attacks                      │   │
│  │     💡 Fix: Close port or use ephemeral pinhole              │   │
│  │     [Auto-Fix] [Configure] [Ignore]                          │   │
│  │                                                               │   │
│  │   • postgres running as root                                 │   │
│  │     ⚠️  Container breakout risk                              │   │
│  │     💡 Fix: Add USER directive to Containerfile              │   │
│  │     [Auto-Fix] [Show How] [Ignore]                           │   │
│  │                                                               │   │
│  │  ⚠️  HIGH                                                     │   │
│  │   • No backup volume for postgres                            │   │
│  │     ⚠️  Data loss risk                                       │   │
│  │     💡 Consider: Add persistent volume                       │   │
│  │     [Add Volume] [Learn More]                                │   │
│  │                                                               │   │
│  │   • Missing health check (nginx)                             │   │
│  │     ⚠️  Can't detect failures automatically                  │   │
│  │     💡 Consider: Add HTTP /health endpoint                   │   │
│  │     [Add Health Check] [Later]                               │   │
│  │                                                               │   │
│  │  💡 RECOMMENDATIONS                                           │   │
│  │   • Enable auto-restart on failure                           │   │
│  │   • Add resource limits (prevent resource exhaustion)        │   │
│  │   • Use alpine base images (smaller attack surface)          │   │
│  │                                                               │   │
│  │  [Auto-Fix All Critical] [Deploy Stack] [Simulate First]    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Page 2: "Spaceship Customizer" - Cisco Network View

```
┌─────────────────────────────────────────────────────────────────────┐
│ stapeln - Network Topology View                      [Simulate Mode]│
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Canvas (drag & drop components)                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                               │  │
│  │         Internet ☁️                                           │  │
│  │             │                                                 │  │
│  │             ▼                                                 │  │
│  │      ┏━━━━━━━━━━━━━┓                                         │  │
│  │      ┃  Firewall   ┃  🔥                                     │  │
│  │      ┃  (Svalinn)  ┃                                         │  │
│  │      ┃  :443 🔒    ┃                                         │  │
│  │      ┗━━━━━━━━━━━━━┛                                         │  │
│  │             │                                                 │  │
│  │             ▼                                                 │  │
│  │      ┌─────────────┐                                         │  │
│  │      │   nginx     │  🌐                                     │  │
│  │      │   :80 🔓    │  ⚠️  Insecure!                         │  │
│  │      │   :443 🔒   │                                         │  │
│  │      └─────────────┘                                         │  │
│  │         │       │                                            │  │
│  │         ▼       ▼                                            │  │
│  │   ┌─────────┐  ┌─────────┐                                  │  │
│  │   │ Node.js │  │ Python  │                                  │  │
│  │   │ API     │  │ Worker  │                                  │  │
│  │   └─────────┘  └─────────┘                                  │  │
│  │         │           │                                        │  │
│  │         └───────┬───┘                                        │  │
│  │                 ▼                                            │  │
│  │          ┌────────────┐                                      │  │
│  │          │ postgres   │  🗄️                                  │  │
│  │          │ :5432 🔒   │                                      │  │
│  │          └────────────┘                                      │  │
│  │                 │                                            │  │
│  │                 ▼                                            │  │
│  │          ╔════════════╗                                      │  │
│  │          ║ Backup Vol ║  💾                                  │  │
│  │          ╚════════════╝                                      │  │
│  │                                                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │ Component Configuration: nginx                              │    │
│  ├────────────────────────────────────────────────────────────┤    │
│  │                                                             │    │
│  │  🎯 Attack Surface: 🟡 MEDIUM                              │    │
│  │                                                             │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │ Port Configuration                                   │  │    │
│  │  │                                                       │  │    │
│  │  │  Port 80 (HTTP)                     ⚠️  Unencrypted │  │    │
│  │  │    ○ Closed  ● Open  ○ Ephemeral                   │  │    │
│  │  │    💡 Consider: Redirect to HTTPS                    │  │    │
│  │  │    [Auto-Redirect] [Close Port]                      │  │    │
│  │  │                                                       │  │    │
│  │  │  Port 443 (HTTPS)                   ✅ Secure        │  │    │
│  │  │    ○ Closed  ● Open  ○ Ephemeral                   │  │    │
│  │  │    ✅ TLS 1.3, Strong ciphers                        │  │    │
│  │  │                                                       │  │    │
│  │  │  Port 22 (SSH)                      ❌ DANGEROUS!    │  │    │
│  │  │    ○ Closed  ● Open  ○ Ephemeral                   │  │    │
│  │  │    ⚠️  Exposed to internet - brute force risk!      │  │    │
│  │  │    [Close Now] [Ephemeral Only]                      │  │    │
│  │  └─────────────────────────────────────────────────────┘  │    │
│  │                                                             │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │ Security Checklist                                   │  │    │
│  │  │                                                       │  │    │
│  │  │  ✅ Image signature verified                         │  │    │
│  │  │  ✅ SBOM present                                     │  │    │
│  │  │  ✅ Running as non-root                              │  │    │
│  │  │  ✅ Health check configured                          │  │    │
│  │  │  ✅ Resource limits set                              │  │    │
│  │  │  ❌ Read-only root filesystem                        │  │    │
│  │  │  ❌ No privileged mode                               │  │    │
│  │  │                                                       │  │    │
│  │  │  [Auto-Fix Missing Items]                            │  │    │
│  │  └─────────────────────────────────────────────────────┘  │    │
│  │                                                             │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │ Performance Stats (Real-time)                        │  │    │
│  │  │                                                       │  │    │
│  │  │  CPU:    ████░░░░░░  32%                            │  │    │
│  │  │  Memory: ██████████  87%  ⚠️  High!                 │  │    │
│  │  │  Network: ▁▂▃▄▅▆▇█  245 Mbps                        │  │    │
│  │  │  Disk I/O: ▃▅▃▂▁▁▂▃  12 MB/s                        │  │    │
│  │  │                                                       │  │    │
│  │  │  💡 Memory usage high - consider increasing limit    │  │    │
│  │  │  [Increase Limit] [Analyze]                          │  │    │
│  │  └─────────────────────────────────────────────────────┘  │    │
│  │                                                             │    │
│  │  [Apply Changes] [Simulate First] [Cancel]                │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Simulation Mode (Packet Tracer Style)

When user clicks **[Simulate]**:

```
┌─────────────────────────────────────────────────────────────────────┐
│ stapeln - Simulation Mode                        ⏸️  [Stop] [Reset] │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                                                               │  │
│  │    Internet ☁️                                                │  │
│  │        │  💚💚💚  (packets flowing)                          │  │
│  │        ▼                                                      │  │
│  │   ┏━━━━━━━━━━━━━┓                                            │  │
│  │   ┃ Firewall    ┃  ✅ Inspecting...                         │  │
│  │   ┃   (443)     ┃  💚 SSL termination OK                    │  │
│  │   ┗━━━━━━━━━━━━━┛                                            │  │
│  │        │  💚💚                                                │  │
│  │        ▼                                                      │  │
│  │   ┌─────────────┐                                            │  │
│  │   │   nginx     │  ✅ Routing...                            │  │
│  │   │             │  💚 /api → Node.js                        │  │
│  │   └─────────────┘                                            │  │
│  │        │  💚💚                                                │  │
│  │        ▼                                                      │  │
│  │   ┌─────────────┐                                            │  │
│  │   │  Node.js    │  ✅ Processing...                         │  │
│  │   │    API      │  💚 Query DB                              │  │
│  │   └─────────────┘                                            │  │
│  │        │  💚💚                                                │  │
│  │        ▼                                                      │  │
│  │   ┌─────────────┐                                            │  │
│  │   │  postgres   │  ✅ Executing query...                    │  │
│  │   │             │  💚 200ms response time                   │  │
│  │   └─────────────┘                                            │  │
│  │        │  💚💚  (response flowing back)                      │  │
│  │        ▼                                                      │  │
│  │   ┌─────────────┐                                            │  │
│  │   │  Client     │  ✅ Received!                             │  │
│  │   │  200 OK     │  💚 Total: 312ms                          │  │
│  │   └─────────────┘                                            │  │
│  │                                                               │  │
│  │  💡 Simulation shows your stack will work correctly!         │  │
│  │  ✅ All components responding                                │  │
│  │  ✅ No port conflicts                                        │  │
│  │  ✅ Network connectivity verified                            │  │
│  │                                                               │  │
│  │  [Deploy for Real] [Run Again] [Exit Simulation]            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  Simulation Log:                                                    │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ [0.0s]   ✅ Client sends HTTPS request to port 443          │  │
│  │ [0.1s]   ✅ Firewall accepts connection (TLS 1.3)           │  │
│  │ [0.2s]   ✅ nginx receives request                          │  │
│  │ [0.3s]   ✅ nginx routes to Node.js API                     │  │
│  │ [0.4s]   ✅ Node.js connects to postgres                    │  │
│  │ [0.6s]   ✅ postgres executes: SELECT * FROM users...       │  │
│  │ [0.8s]   ✅ postgres returns 42 rows                        │  │
│  │ [0.9s]   ✅ Node.js formats JSON response                   │  │
│  │ [1.0s]   ✅ nginx sends response to client                  │  │
│  │ [1.1s]   ✅ Client receives 200 OK (312ms total)            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

If simulation detects a problem:

```
│  │   ┌─────────────┐                                            │  │
│  │   │   nginx     │  ❌ ERROR!                                │  │
│  │   │   :8080     │  💥 Port already in use!                 │  │
│  │   └─────────────┘                                            │  │
│  │                                                               │  │
│  │  ❌ Simulation failed - stack won't deploy                   │  │
│  │                                                               │  │
│  │  Problem: Port 8080 is already taken by: postgres-dev        │  │
│  │                                                               │  │
│  │  Fix options:                                                 │  │
│  │  1. [Auto-fix] Change nginx to port 8081                     │  │
│  │  2. [Stop] Stop postgres-dev container                       │  │
│  │  3. [Manual] Choose a different port                         │  │
│  │                                                               │  │
│  │  [Apply Fix #1] [Choose Fix] [Cancel Deployment]            │  │
```

---

## Attack Surface Analyzer - "Spaceship Stats" Style

```
┌─────────────────────────────────────────────────────────────────────┐
│ 🎯 Attack Surface Analysis                                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Your Stack Profile:                                                │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │                                                              │  │
│  │   Security:     ████████░░░░░░░░  67/100  🟡                │  │
│  │   Performance:  ███████████████░  92/100  ✅                │  │
│  │   Reliability:  ██████████░░░░░░  73/100  🟡                │  │
│  │   Compliance:   ██████░░░░░░░░░░  51/100  🟠                │  │
│  │   Usability:    ████████████████  98/100  ✅                │  │
│  │                                                              │  │
│  │   Overall Grade: C+ (Need security improvements!)           │  │
│  │                                                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Threat Model                                                 │  │
│  │                                                              │  │
│  │  Exposed Attack Vectors:                                    │  │
│  │                                                              │  │
│  │   ❌ SSH (Port 22)                    Risk: CRITICAL        │  │
│  │      • Brute-force attacks                                  │  │
│  │      • Credential stuffing                                  │  │
│  │      • CVE-2023-XXXXX vulnerability                         │  │
│  │      [Close Port] [Require Key Auth] [Details]              │  │
│  │                                                              │  │
│  │   ⚠️  HTTP (Port 80)                  Risk: HIGH            │  │
│  │      • Unencrypted traffic                                  │  │
│  │      • MITM attacks possible                                │  │
│  │      • Sensitive data exposed                               │  │
│  │      [Force HTTPS Redirect] [Close Port]                    │  │
│  │                                                              │  │
│  │   ⚠️  Root User                       Risk: HIGH            │  │
│  │      • Container breakout risk                              │  │
│  │      • Privilege escalation                                 │  │
│  │      [Switch to Non-Root] [Learn Why]                       │  │
│  │                                                              │  │
│  │   💡 postgres                         Risk: LOW             │  │
│  │      • Internal network only (good!)                        │  │
│  │      • TLS encryption enabled                               │  │
│  │      • Strong password policy                               │  │
│  │      ✅ No issues found                                     │  │
│  │                                                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Compliance Scorecard                                         │  │
│  │                                                              │  │
│  │  OWASP Top 10:            6/10 issues addressed  🟡         │  │
│  │  CIS Benchmarks:          12/20 controls passed  🟠         │  │
│  │  NIST Cybersecurity:      8/15 functions met    🟠         │  │
│  │  PCI-DSS:                 ❌ Not compliant                  │  │
│  │  SOC 2:                   ❌ Not compliant                  │  │
│  │                                                              │  │
│  │  [View Details] [Generate Report] [Fix All]                 │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Recommended Improvements (Priority Order)                    │  │
│  │                                                              │  │
│  │  1. 🔥 Close SSH port 22 immediately                        │  │
│  │     Impact: ⬆️ Security +15 points                          │  │
│  │     Effort: 30 seconds                                      │  │
│  │     [Fix Now]                                                │  │
│  │                                                              │  │
│  │  2. 🔥 Switch postgres to non-root user                     │  │
│  │     Impact: ⬆️ Security +12 points                          │  │
│  │     Effort: 2 minutes                                       │  │
│  │     [Auto-Fix]                                               │  │
│  │                                                              │  │
│  │  3. ⚠️  Enable automatic backups                            │  │
│  │     Impact: ⬆️ Reliability +18 points                       │  │
│  │     Effort: 5 minutes                                       │  │
│  │     [Configure]                                              │  │
│  │                                                              │  │
│  │  4. 💡 Add rate limiting to API                             │  │
│  │     Impact: ⬆️ Security +8 points                           │  │
│  │     Effort: 10 minutes                                      │  │
│  │     [Learn How]                                              │  │
│  │                                                              │  │
│  │  [Apply Top 3] [Custom Priority] [Ignore]                   │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Interactive "Choose Your Configuration" Screen

Like a game where you customize your spaceship:

```
┌─────────────────────────────────────────────────────────────────────┐
│ 🚀 Configure Your Container Stack                                   │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Component: nginx Web Server                                        │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Base Configuration                                           │  │
│  │                                                              │  │
│  │  Choose your approach:                                       │  │
│  │                                                              │  │
│  │  ○ 🛡️  Maximum Security (Recommended)                       │  │
│  │     • No unnecessary ports                                   │  │
│  │     • Read-only filesystem                                   │  │
│  │     • Non-root user                                          │  │
│  │     • Automatic security updates                             │  │
│  │     Security: ████████████████   Performance: ████████████  │  │
│  │                                                              │  │
│  │  ○ ⚡ Maximum Performance                                    │  │
│  │     • Optimized for speed                                    │  │
│  │     • Caching enabled                                        │  │
│  │     • More open configuration                                │  │
│  │     Security: ████████░░░░░░   Performance: ████████████████│  │
│  │                                                              │  │
│  │  ● 🎯 Balanced (Default)                                     │  │
│  │     • Good security + good performance                       │  │
│  │     • Sensible defaults                                      │  │
│  │     • Easy to customize later                                │  │
│  │     Security: ████████████░░   Performance: ████████████░░  │  │
│  │                                                              │  │
│  │  ○ 🔧 Custom (Advanced)                                      │  │
│  │     • Configure everything manually                          │  │
│  │     • For experts only!                                      │  │
│  │     Security: ???            Performance: ???               │  │
│  │                                                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Optional Features (Click to toggle)                          │  │
│  │                                                              │  │
│  │  [✅] Auto-restart on failure                               │  │
│  │       ⚡ Impact: Reliability +20%                            │  │
│  │                                                              │  │
│  │  [✅] Health check monitoring                               │  │
│  │       ⚡ Impact: Reliability +15%                            │  │
│  │                                                              │  │
│  │  [✅] Resource limits (CPU: 1 core, RAM: 512MB)             │  │
│  │       ⚡ Impact: Stability +25%, Prevents resource hog       │  │
│  │                                                              │  │
│  │  [❌] Enable debug logs                                     │  │
│  │       ⚠️  Warning: May expose sensitive data                │  │
│  │                                                              │  │
│  │  [❌] Privileged mode                                       │  │
│  │       ❌ Warning: DANGEROUS! Don't enable unless required   │  │
│  │       ⚠️  Security: -50 points                              │  │
│  │                                                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Your Configuration Stats:                                    │  │
│  │                                                              │  │
│  │  Security:     ████████████░░   78/100                      │  │
│  │  Performance:  ██████████░░░░   71/100                      │  │
│  │  Reliability:  ███████████████   89/100                     │  │
│  │  Cost:         ██████░░░░░░░░   $2.50/month                │  │
│  │                                                              │  │
│  │  ⚠️  2 warnings:                                            │  │
│  │   • No backup configured (data loss risk)                   │  │
│  │   • Port 80 open (unencrypted traffic)                      │  │
│  │                                                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                      │
│  [Save Configuration] [Simulate First] [Cancel]                     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Key Visual Design Elements

### 1. Color-Coded Risk Levels

```
✅ Green  = Safe, no issues
🟡 Yellow = Warnings, should fix
🟠 Orange = High risk, fix soon
🔴 Red    = Critical, fix now!
💜 Purple = Recommendations (nice-to-have)
```

### 2. Real-Time Stat Bars (like RPG games)

```
Security:     ████████░░░░░░  67/100
Performance:  ███████████████  92/100
Reliability:  ██████████░░░░  73/100
```

### 3. Impact Indicators

```
[Auto-Fix]  ⬆️ Security +15 points
[Configure] ⬆️ Reliability +18 points
[Enable]    ⬇️ Security -10 points (show trade-offs!)
```

### 4. Emoji Icons (Quick Recognition)

```
🔒 Closed/Secure
🔓 Open/Exposed
⏱️  Ephemeral
🔥 Critical issue
⚠️  Warning
💡 Recommendation
✅ Working correctly
❌ Problem detected
🎯 Attack surface
🛡️  Protected
```

### 5. "Before vs After" Preview

```
Before Auto-Fix:
  Security: ███░░░░░░░░  45/100  ❌

After Auto-Fix:
  Security: ████████████  82/100  ✅

  Changes:
  • Port 22 closed
  • User switched to non-root
  • Read-only filesystem enabled

  [Apply These Changes]
```

---

## Implementation Priority

1. **Week 1**: Build attack surface analyzer with real-time scoring
2. **Week 2**: Add simulation mode with packet animation
3. **Week 3**: Create "spaceship customizer" config screen
4. **Week 4**: User testing with container-hater (your son!)

---

## Success Metrics

✅ User sees security score update in real-time as they configure
✅ User understands why something is dangerous (visual + plain English)
✅ User can fix issues without knowing what "iptables" or "USER directive" means
✅ Feels like playing a game, not configuring a server

**Goal**: "Wow, this is actually fun!" 🎮
