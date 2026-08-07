<!--
SPDX-License-Identifier: CC-BY-SA-4.0
SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell (hyperpolymath)
-->

# Badge Register — restore these

**Status as of 2026-08-07.** This is the working list of every badge stapeln wants on its
README, what each one asserts, and exactly what is needed to put it back. Five were removed
on 2026-08-07 because nothing in the repository verified them — **they are wanted, and this
file exists so they get restored as soon as the evidence is in place, not quietly forgotten.**

A badge is a public claim. The bar is simple: **the claim must resolve to something a
stranger can check.** A shields.io image with no artefact behind it is decoration; worse, it
is decoration that looks like assurance.

---

## Restore ASAP — evidence needed

These five are the priority. Each row says precisely what unblocks it.

### 1. WCAG 2.3 AAA — accessibility

| | |
|---|---|
| **Asserts** | The UI meets WCAG 2.3 at level AAA |
| **Why removed** | Static image. `docs/ACCESSIBILITY-AUDIT-2026-03-29.adoc` exists but does not certify AAA |
| **Closest existing asset** | That audit, plus [`ACCESSIBILITY.md`](../ACCESSIBILITY.md) |
| **To restore** | Complete a dated AAA conformance audit and commit it, then link the badge to the audit file rather than to nothing. If the honest level is AA, badge **AA** — an accurate AA badge is worth more than an unbacked AAA one |
| **Owner action** | Confirm the target level |

### 2. OWASP Compliant — security posture

| | |
|---|---|
| **Asserts** | Compliance with OWASP guidance (ASVS level unstated) |
| **Why removed** | Static image, no gate, no date, no named standard |
| **Closest existing asset** | [`SECURITY-STACK-AUDIT.md`](../SECURITY-STACK-AUDIT.md), [`ATTACK-SURFACE-GAPS.md`](../ATTACK-SURFACE-GAPS.md), the live Hypatia scan |
| **To restore** | Name the standard and level (e.g. *OWASP ASVS 4.0 L2*), record the assessment, link to it. "Compliant" with nothing after it is unfalsifiable |
| **Owner action** | Pick the standard and level to claim |

### 3. SOC 3

| | |
|---|---|
| **Asserts** | A SOC 3 report exists for this project |
| **Why removed** | Linked to `github.com/organizations/metadatastician/settings/compliance` — a **private settings page**, not an attestation. No reader can verify it |
| **To restore** | Link to the **public SOC 3 report** (SOC 3 reports are, by design, freely distributable — this is the one SOC report you *can* publish). Add the report or its URL to the repo |
| **Owner action** | **If this attestation exists, this badge should go back immediately** — supply the public report URL |

### 4. ISO 27001

| | |
|---|---|
| **Asserts** | ISO/IEC 27001 certification |
| **Why removed** | Same private settings link |
| **To restore** | Link to the certificate, and state the **certificate number, certification body and scope** — 27001 certifies an ISMS of defined scope, so an unscoped claim is meaningless |
| **Owner action** | **If certified, restore immediately** — supply certificate number and scope |

### 5. CIAQ

| | |
|---|---|
| **Asserts** | CIAQ compliance |
| **Why removed** | Same private settings link |
| **To restore** | Link to the issuing body's public record |
| **Owner action** | Confirm what CIAQ certifies here and where it is published |

> **If any of items 3–5 are genuine, the correct fix is to revert the removal and add the
> link — not to re-derive anything.** The badges were removed for want of a verifiable
> reference, not because the certification was judged false.

---

## Also wanted — was present, dropped in the same pass

### 6. Green Hosting (The Green Web Foundation)

| | |
|---|---|
| **Was** | `api.thegreenwebfoundation.org/greencheckimage/svalinnproject.org` |
| **Why dropped** | It checked **`svalinnproject.org`** — a sibling project's domain, not stapeln's. The badge was live and real, but pointed at the wrong subject |
| **To restore** | Re-point at stapeln's own deployment domain and restore. This is a live API badge, so it stays honest by construction |
| **Owner action** | Name the correct domain |

---

## Blocked by a bug

### 7. CRG grade

| | |
|---|---|
| **Asserts** | The project's Component Readiness Grade |
| **Status** | The repo *ships its own generator* — `just crg-badge` and `just crg-grade`, reading `**Current Grade:** X` from `READINESS.md` |
| **Blocker** | **Both recipes currently fail**: `sh: 1: Syntax error: "(" unexpected` (Justfile lines 69 and 80 — bash-isms executed under `sh`) |
| **To restore** | Fix the two recipes (set a bash shebang for them or drop the bash-only syntax), then publish the grade |
| **Note** | Recorded as debt CI-6 |

---

## Currently displayed and verified — keep

| Badge | Why it is honest |
|---|---|
| **License MPL-2.0** | Accurate; matches `LICENSE`, which GitHub detects. See [`LICENSING.md`](../LICENSING.md) |
| **OpenSSF Scorecard** | Live API badge, resolves to a public scorecard page. *Caveat: the Scorecard workflow is currently `startup_failure`ing daily (debt CI-1), so the score may be stale — fixing that is what makes this badge meaningful* |
| **OpenSSF Best Practices** | Live badge, public project record ([project 8509](https://www.bestpractices.dev/projects/8509)). Was silently broken by an `nimage:` typo; fixed 2026-08-07 |
| **ReScript / Elixir / Idris2** | Descriptive technology badges, not compliance claims. Accurate |

---

## Candidates worth adding

Not previously present, but cheap and genuinely verifiable:

- **REUSE compliance** — `api.reuse.software/badge/github.com/metadatastician/stapeln`. Live
  and automatic. Now plausible: the tree is uniformly MPL-2.0 + CC-BY-SA-4.0 as of
  2026-08-07. Run `reuse lint` first.
- **CI status** — a workflow badge, once a workflow actually runs the tests (debt T-1/T-2).
  Adding it *before* then would advertise a gate that does not gate.
- **Latest release** — automatic from GitHub once tagged.

---

## The standing rule

**No badge without a resolvable reference.** Before adding one, answer: *if a stranger clicks
this, do they reach something that could contradict the claim?* If the honest answer is no,
the badge is decoration and does not go on the README.

Related: [`DEBT.md`](../DEBT.md) D-2 · [`LICENSING.md`](../LICENSING.md)
