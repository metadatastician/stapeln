# Stapeln — Product Vision

<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

**Status:** vision doc (authoritative), drafted 2026-04-10
**Audience:** anyone — users, platform maintainers, developers, AI agents
**Relationship to other docs:** this is the *why* and the *flow*. `UX-MANIFESTO.adoc` is the *design philosophy*. `CONTAINER-HATER-TEST.adoc` is the *acceptance criterion*. `ARCHITECTURE.adoc` / `IMPLEMENTATION-PLAN.adoc` are the *how*. If those disagree with this doc, this doc wins until edited.

---

## The one-sentence version

Stapeln staples the entire Svalinn constellation — Cerro Torre, Svalinn core, Vörðr, Selur, Selur-compose, Rokur, Lago Grey — into a single seamless experience where **nobody has to care about the pieces** unless they want to.

## The one-paragraph version

Stapeln is a conversational, tab-skippable, CLI-and-GUI-parity configurator for verified containers. A returning user picks a saved setup and ships in one click. A new user answers a short chain of plain-English questions — "do you want a container? which runtime? which distro? build it? seal it? secrets?" — and Stapeln staples together the correct underlying subsystems behind each answer without ever naming them. A user with an *existing* `.a2ml` stack opens it in Stapeln and gets a security-and-compatibility audit with concrete remediations, offered as yes/no prompts and one-click config profiles. The name of every subsystem (Cerro Torre, Selur, Vörðr, Rokur) is plumbing; the user never has to learn any of them.

## Why this is the product

The person who built the Svalinn constellation — that's you, Jonathan — **cannot hold all of it in working memory simultaneously**. You've said as much. If the author forgets pieces, no user will ever succeed at "pick the right subsystem for your threat model" on their own. Stapeln is the externalisation of the mental model: it knows which subsystem does what, which combinations are compatible, and which defaults are sane. Users answer questions about *what they want*, and Stapeln translates answers into subsystem wiring.

This is the same reason Dell.com, Framework.com, and Azure Resource Manager exist. Nobody assembles a laptop from a parts bin; they pick options from a configurator that knows the compatibility matrix. Containers should work the same way.

## Acceptance criterion

From `CONTAINER-HATER-TEST.adoc`: *A government cyberwar officer who loathes containerization must be able to ship a secure container stack through Stapeln without ever reading the manual.* If the flow fails that test, the flow is wrong.

Operationally: **a twelve-year-old who is reasonably IT-capable can help their parents build a secure container stack.** Same goal, different phrasing.

## The three user modes

### Mode 1 — Returning user ("I have done this before")

- **Entry**: open Stapeln, pick a saved stack from the landing screen. Or via CLI: `stapeln load <name>` or `stapeln load <file.a2ml>`.
- **Flow**: land directly at the relevant view (Paragon / Cisco / Lago Grey) with the stack already loaded. One button to deploy, one to edit.
- **Purpose**: zero friction for people who already know what they want. The wizard doesn't get in their way.

### Mode 2 — New user ("I have never done this before")

- **Entry**: open Stapeln, click "Build a new stack" (or `stapeln new` on the CLI).
- **Flow**: a chain of short questions, each on its own tab, each skippable when the answer is obvious or the user already knows what they want. The tabs are not rigid — they're progressive disclosure with smart defaults. See §"The wizard chain" below.
- **Purpose**: zero prior knowledge required. Every question is in plain English. Every tradeoff has a short explanation the user can ignore or read.

### Mode 3 — Audit existing stack ("I have this .a2ml file, is it any good?")

This is the killer feature.

- **Entry**: open Stapeln, drag in an `.a2ml` file. Or `stapeln audit <file.a2ml>`.
- **Flow**:
  1. Stapeln parses the file.
  2. Paragon view renders the stack.
  3. miniKanren security engine + CVE daily sync + attack-surface analyzer run in the background.
  4. Gap analysis sidebar lights up with findings in plain English:
     > ❌ CRITICAL — your secrets are sitting in the environment as plaintext.
     > ❌ CRITICAL — port 22 is exposed to the internet.
     > ⚠️ HIGH — this image has a CVE from three days ago.
     > 💡 RECOMMENDATION — you have no backup volume.
  5. Each finding comes with a concrete remediation, offered as a yes/no prompt:
     > "Add Rokur for secrets management? [Yes] [No] [Tell me more]"
     > "Put Vörðr around the container to sandbox it? [Yes] [No] [Tell me more]"
     > "Close port 22 and add an ephemeral pinhole for admin access? [Yes] [No] [Tell me more]"
  6. One-click config profiles at the top of the findings:
     > `[ Security focus ] [ Performance focus ] [ Minimal footprint ] [ Developer convenience ]`
     Each profile applies a pre-vetted set of remediations in one click.
- **Purpose**: bring stacks out of the wild into a safe state with zero expertise required. The user doesn't have to know what Rokur, Vörðr, or an ephemeral pinhole *are* — they just have to say yes.

## CLI / GUI parity

Everything Stapeln can do through the GUI, it can also do through the CLI. The GUI is for most people; the CLI is for automation, CI pipelines, and users who want a REPL-style workflow. The two surfaces share the same backend state and the same `.a2ml` file format, so a stack built in the GUI can be version-controlled, edited in a text editor, replayed in CI, and vice versa.

**This is a design principle, not a feature to add later.** The GUI should not contain any capability that isn't also expressible on the CLI. The CLI should not contain any capability that isn't also reachable from the GUI. If the two diverge, that's a bug.

**Illustrative CLI commands** (subject to refinement):

```
stapeln new                              # interactive wizard in the terminal
stapeln new --profile security           # wizard with security-focus defaults
stapeln load <name|file.a2ml>            # load a saved or on-disk stack
stapeln audit <file.a2ml>                # audit-and-remediate mode
stapeln audit <file.a2ml> --fix profile=security  # apply a profile non-interactively
stapeln build                            # hand off to Cerro Torre
stapeln deploy                           # build + run via Vörðr, gated by Svalinn
stapeln seal --compose <file>            # Selur/Selur-compose
stapeln secrets add <key> --from-file <f>  # Rokur
stapeln base-image --designer           # open Lago Grey designer
stapeln gui                              # launch the desktop GUI (no-op if already open)
```

## The wizard chain

The wizard is a sequence of tabs. Each tab is one decision. The order is roughly build-time → run-time → security → deploy. The user can skip any tab by answering "no / skip / not applicable" or by using a profile. None of the subsystem names (Cerro Torre, Vörðr, Selur, Rokur, Lago Grey) ever appear in question text — they only appear in the optional "tell me more" expansion.

### Tab 1 — "Do you need a container at all?"

- [Yes] [No]
- If no: Stapeln exits gracefully with "you don't need this tool for what you're doing."
- If yes: continue.

### Tab 2 — "Which container runtime?"

- [Podman — recommended, daemonless] [nerdctl — containerd direct] [Docker — most familiar]
- Smart default: Podman.
- Skippable for returning users via profile.
- Wires into: Vörðr integration layer (`container-stack/vordr/`) picks the right adapter.

### Tab 3 — "Do you want a Linux distribution?"

- [Distroless — minimal, one binary] [I want a distro]
- If distroless: skip Tab 4, go straight to Tab 5.
- If distro: Tab 4.

### Tab 4 — "Which distro?" (only if Tab 3 said yes)

- [Chainguard — hardened, zero-CVE goal] [Alpine — tiny, musl-based] [Debian — familiar, glibc] [Fedora Kinoite — atomic, rpm-ostree]
- Compatibility guidance per choice:
  > "Chainguard works well for most production workloads; if you need a specific glibc library, you may need Debian."
  > "Alpine is smallest but musl can surprise you with Python/Node workloads."
  > "Debian is the safest default if you don't know."
  > "Kinoite is for desktop-style atomic deployments, not typical servers."
- Also available here: [Let me design my own minimal image with Lago Grey →] which opens the Lago Grey designer inline.
- Wires into: Lago Grey base-image selector (`container-stack/lago-grey/` — does this live elsewhere? TBD during gap analysis).

### Tab 5 — "How are you building the image?"

- [Use an existing image as-is] [Build from a Containerfile I have] [Let Stapeln write a Containerfile for me]
- If "write for me": Stapeln generates a Containerfile based on the answers so far. User can preview and edit.
- If "Containerfile I have": drag-and-drop or file-picker. Stapeln validates it against the verified-container-spec.
- Wires into: Cerro Torre (`container-stack/cerro-torre/`).

### Tab 6 — "Do you want the container sandboxed at runtime?"

- [Yes — Vörðr wraps it with guardrails] [No — run it unsandboxed]
- Default: Yes. Strongly recommended.
- "Tell me more" expands: what Vörðr does, what sandboxing prevents, how much overhead it adds.
- Wires into: Vörðr (`container-stack/vordr/`).

### Tab 7 — "Does the stack need multiple containers?"

- [One container] [Multiple containers working together]
- If multiple: continue to Tab 8.
- If one: skip to Tab 9.

### Tab 8 — "How should the containers be wired together?" (only if Tab 7 said multiple)

- [Compose-style declarative (recommended)] [Let me draw it — opens Cisco view] [I'll handle wiring elsewhere]
- Compose-style: Selur-compose generates a compose file from answers.
- Drawing: opens the Cisco network-topology view; user drags components.
- Wires into: Selur (`container-stack/selur/`) + Selur-compose.

### Tab 9 — "Does this stack have any secrets?"

Examples shown in plain English: "API keys, database passwords, signing keys, TLS certificates, OAuth tokens."

- [Yes, it needs secrets] [No secrets needed]
- If yes: continue to Tab 10.
- If no: skip to Tab 11.

### Tab 10 — "Where should the secrets live?" (only if Tab 9 said yes)

- [Rokur — cross-cutting secrets management, recommended] [Environment variables — not recommended] [Mounted file — OK for some cases]
- Default: Rokur.
- "Tell me more" expands on what Rokur gives you: encrypted at rest, rotated, audit-logged, never in the image layer.
- Wires into: Rokur (`container-stack/rokur/`).

### Tab 11 — "What does this stack talk to from the outside?"

- Select from a checklist: [Nothing — fully isolated] [A specific set of URLs] [One of my other stacks] [The open internet]
- Each choice drives firewall + pinhole policy.
- "The open internet" prompts a second question: "Does it need to be reachable *from* the internet, or just reach *out*?"
- Wires into: Svalinn core gateway (`svalinn/`) + ephemeral pinholes in Stapeln backend.

### Tab 12 — "Review and deploy"

- Shows the full Paragon view of the stack about to be deployed.
- Shows the security score, the compliance dashboard, and any remaining gap-analysis findings.
- If anything is red, the deploy button is disabled until the user either fixes it or explicitly overrides with a typed confirmation.
- Buttons: [Deploy] [Save as template] [Export `.a2ml`] [Open in Cisco view to edit] [Back]

## Skippable tabs and config profiles

Any tab can be skipped if:

1. The answer is determined by an earlier answer (e.g. distroless → Tab 4 skipped).
2. A profile sets the answer already ("Security focus" profile picks Vörðr=yes automatically).
3. The user explicitly says "not applicable / I don't care" — Stapeln applies the safe default and marks the tab as skipped.

**Config profiles** are named bundles of answers. They appear at the top of the wizard and at the top of audit mode. Each profile is one click and sets every relevant answer. Users can combine a profile with manual edits to specific tabs.

Initial profiles (to be iterated):

- **Security focus** — Vörðr on, Rokur on, Chainguard base, all ports closed, ephemeral pinholes only, signatures enforced, SBOM required, post-quantum crypto where available.
- **Performance focus** — Alpine base, minimal sandboxing, static linking where possible, compose-native networking, no audit logging in the hot path.
- **Minimal footprint** — Distroless or Lago Grey custom minimal, single binary if possible, no extra sidecars.
- **Developer convenience** — Debian base, verbose logging, hot-reload where supported, ports open on localhost, secrets in files (with warnings).

Profiles are *templates*, not rules. The user can always override individual answers.

## The audit flow in detail

When a user drags an `.a2ml` file into Stapeln (or runs `stapeln audit <file>`), the following pipeline runs:

1. **Parse** — A2ML parser validates the file. If malformed, show a parser error with line numbers and stop.
2. **Render** — Paragon view shows the stack as it exists.
3. **Gap analysis** — miniKanren engine runs the full ruleset (OWASP Top 10, CIS benchmarks, NIST, project-specific rules) over the stack.
4. **CVE lookup** — every image and base gets checked against the daily NIST NVD sync.
5. **Attack-surface scoring** — the analyzer assigns a security score 0-100 and identifies the biggest attack vectors.
6. **Findings** — results are shown in the gap-analysis sidebar, sorted by severity. Each finding has:
   - A plain-English description of what's wrong.
   - A plain-English description of the consequence.
   - One or more concrete remediations, each expressible as "add this subsystem" or "change this setting".
   - A "tell me more" expansion with the technical detail.
7. **Remediation prompts** — each finding offers yes/no buttons for its remediations. Saying yes applies the fix to an in-memory working copy of the stack; the user can review all accumulated changes before writing them back.
8. **Config profile buttons** — at the top, one-click buttons to apply a whole profile's worth of remediations at once.
9. **Export** — when the user is happy, they export the patched `.a2ml` file, deploy directly, or save as a template.

This is where Stapeln becomes an *educational* tool as well as a configurator. A user who drags in their own stack and reads the findings is learning container security by example without realising it.

## Subsystem wiring map

For implementers: which tab / feature uses which subsystem.

| Tab / feature | Subsystem | Location |
|---|---|---|
| Tab 2 (runtime choice) | Vörðr adapter | `container-stack/vordr/` |
| Tab 4 (distro choice) | Lago Grey base-image selection | `container-stack/lago-grey/` (location TBD — verify) |
| Tab 5 (build) | Cerro Torre | `container-stack/cerro-torre/` |
| Tab 6 (sandboxing) | Vörðr | `container-stack/vordr/` |
| Tab 8 (multi-container wiring) | Selur + Selur-compose | `container-stack/selur/` (compose sub-directory) |
| Tab 9/10 (secrets) | Rokur | `container-stack/rokur/` — **currently scaffold only, 0 source files** |
| Tab 11 (network boundary) | Svalinn core + ephemeral pinholes | `container-stack/svalinn/` + Stapeln backend |
| Audit mode (parse) | A2ML parser | Stapeln backend (not yet built) |
| Audit mode (gap analysis) | miniKanren engine | Stapeln backend (not yet started) |
| Audit mode (CVE lookup) | NVD daily sync | Stapeln backend (not yet wired) |
| Audit mode (attack surface) | Attack-surface analyzer | Stapeln frontend (partial, sample data only) |
| Export / load | `.a2ml` file format | Standards repo |

## Relationship to existing Stapeln implementation

Per the README dated 2026-02-13, Stapeln is ~35% complete. The vision in this doc is not a rewrite — it is the *flow* that ties the already-built pieces together. Mapping vision → current state:

- **Four views exist** (Paragon, Cisco, Lago Grey Designer, Settings). The wizard flow should be a **fifth entry point** that lands in one of these views on completion, not a replacement. First-time users see the wizard; returning users see the view directly; audit-mode users see Paragon with the gap-analysis sidebar lit up.
- **miniKanren engine — not started.** Needed for audit mode (§Tab 12 and §audit). Highest-priority blocker for Mode 3.
- **A2ML parser — not started.** Needed for audit mode and for the export/load path (all three modes).
- **VeriSimDB integration — not started.** Not on the critical path for the wizard itself, but needed for persistence of saved stacks.
- **Authentication — not started.** Needed before real deployment; the wizard can be tested without it.
- **Post-quantum crypto — 0%.** Needed for the Security Focus profile to be honest about what it promises.
- **Subsystems (Cerro Torre, Vörðr, Selur, Lago Grey, Svalinn) — built** and living in `container-stack/`. Wiring them into the wizard is a Stapeln-backend job, not a subsystem job.
- **Rokur — scaffold only, 0 source files.** The only subsystem that needs to be written from scratch before the wizard can honestly offer Mode 3 remediation for secrets-management findings.

So the **critical path to a working wizard** is:

1. A2ML parser (needed by wizard output, wizard load, and audit mode).
2. Rokur implementation (needed for the wizard's secrets tab and for audit remediations).
3. miniKanren engine (needed for audit mode to produce real findings).
4. Wiring Stapeln's existing views into the wizard as terminal states.

The wizard itself is a few days of ReScript-TEA work once the above are in place. None of the subsystems need to be rewritten.

## What this doc is not

- Not a spec. There are no grammar rules, no formal typing, no state machines. Those come next if the vision lands.
- Not a commitment to every tab listed. The wizard chain above is a *starting point*. User testing (the container-hater test) will reshape it.
- Not a promise about the GUI layout. ReScript-TEA lets the implementer make different layout choices without changing the flow semantics.
- Not a rejection of the four existing views. They remain. The wizard lands in them. They are *the views*; the wizard is *the entry*.

## Open questions

1. **Where does Lago Grey live physically?** I see a `LagoGreyImageDesigner` ReScript component in `stapeln/frontend/` but no standalone Lago Grey engine in `stapeln/container-stack/`. README line 539 lists a `hyperpolymath/lago-grey` GitHub repo. Clarify before the wizard depends on it.
2. **Is there an audit-mode profile called "bring this up to my house standard"?** Conceptually useful: a user saves their preferred-remediation set once and re-applies it to any stack they audit. Worth having?
3. **Should the wizard have an "Export Containerfile only" exit** for users who want to use Stapeln's compatibility guidance but run the container elsewhere? Low cost, high value for a certain kind of skeptic.
4. **What's the minimum viable wizard for a first release?** I suspect: Tabs 1, 2, 3, 5, 11, 12 — that's "container or not, runtime, distro-or-not, build how, network boundary, review". Everything else can be post-v1. Worth a design session.

## Revision history

- 2026-04-10 — initial vision doc, drafted by Claude after Jonathan articulated the flow in a single conversation. All subsystem locations verified against `container-stack/` on disk. Rokur confirmed as the only unbuilt subsystem (scaffold, 0 source files).
