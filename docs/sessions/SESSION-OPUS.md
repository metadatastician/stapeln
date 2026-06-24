# SPDX-License-Identifier: CC-BY-SA-4.0
# Stapeln — Opus session brief

**Model:** Claude Opus
**Repo:** `fleet-ecosystem/stapeln` (at `/var/mnt/eclipse/repos/fleet-ecosystem/stapeln`)
**Tasks:** WS-2, F-1, P-1 through P-7
**Prerequisite:** Sonnet session complete — channels defined, auth wired, VeriSimDB live

---

## Context

Stapeln is an Elixir/Phoenix backend + ReScript frontend container-management GUI.
Formal verification lives in `container-stack/cerro-torre/verification/idris/`.
Runtime crypto is in Zig at `ffi/zig/src/crypto.zig`.

echidnabot will execute the proofs drafted in this session. Your job is to draft
them with enough precision that echidnabot has zero ambiguity. Each proof also gets
a `.idr.draft` file with the Idris2 type signature — not compiled, just the statement.

**Proof draft format (use for every proof):**
```
Proof opportunity: <name>
Claim: <precise formal statement>
Strategy: <Idris2 structural / ECHIDNA dispatch / Coq lemma / property test>
Buys: <correctness guarantee / CRG lift / security property>
Blocked on: <any stubs or partials that must resolve first>
Idris2 sketch: <minimal type signature or theorem statement>
```

---

## WS-2 — Wire live events to SimulationMode and SecurityInspector

The Sonnet session created `EventsChannel` with a ping/pong stub. Wire real events:

**Backend:** In `simulation_controller.ex` and `simulation_engine.ex`, find where
simulation state changes. After each state change, broadcast:
```elixir
Phoenix.PubSub.broadcast(Stapeln.PubSub, "events:simulation", {:simulation_update, state})
```

In `security_controller.ex`, broadcast after scanner status changes:
```elixir
Phoenix.PubSub.broadcast(Stapeln.PubSub, "events:security", {:security_update, result})
```

In `EventsChannel`, handle these in `handle_info`:
```elixir
def handle_info({:simulation_update, state}, socket) do
  push(socket, "simulation:update", state)
  {:noreply, socket}
end
```

**Frontend:** In `Socket.res`, add `on` handlers for `"simulation:update"` and
`"security:update"` that dispatch the appropriate `Msg` constructors. In
`SimulationMode.res` and `SecurityInspector.res`, handle the new messages in
`Update.res` to refresh the view state.

Keep it minimal — working push path, not a full realtime system.

---

## F-1 — Auth seam review

Read: `ApiClient.res`, `LoginPage.res`, `RegisterPage.res`, `Socket.res`,
`backend/lib/stapeln_web/router.ex`.

Verify:
1. Every route under `RequireApiToken` in the router has a corresponding
   authenticated call in `ApiClient.res`
2. `Socket.res` sends the access token in connection params so `UserSocket.connect`
   can verify it
3. The 401 refresh loop in `ApiClient.res` cannot infinite-loop — a failed refresh
   must not trigger another refresh attempt

Fix any gaps. Create `docs/AUTH-SEAM.adoc`:
```adoc
// SPDX-License-Identifier: CC-BY-SA-4.0
= Stapeln Authentication Seam

Documents the full auth boundary: token generation, storage, transmission,
refresh, and expiry handling. One source of truth for the seam contract.
```

Document each verified property in the adoc.

---

## P-1 — `config_value_safety`

**Claim:** `PipelineEngine.config_value/2` never raises on any binary key,
regardless of atom table state, after the Map.fetch fix.

**Strategy:** ECHIDNA property test over random maps + random string keys;
Idris2 total function proof over Map semantics.

**Buys:** Eliminates the entire atom-interning crash class. CRG lift.

**Blocked on:** Nothing — fix is already merged.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/ConfigValueSafety.idr.draft`
```idris
-- configValueSafe : for all maps m and string keys k,
--   configValue m k returns Maybe Value, never diverges
configValueSafe : (m : SortedMap String Value) -> (k : String) -> Maybe Value
```

---

## P-2 — `auth_login_constant_time`

**Claim:** `Auth.login/2` calls `hash_password/1` exactly once regardless of
whether the email is found in the store (timing-attack resistance).

**Strategy:** ECHIDNA timing-trace property — instrument hash calls, assert
count = 1 on both branches. Idris2 type-level: encode hash-call count as a
`Nat` phantom.

**Buys:** Closes timing oracle on user enumeration.

**Blocked on:** Nothing.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/LoginConstantTime.idr.draft`
```idris
-- Both branches of login call hashPassword exactly once.
-- Encoded as a type-level count invariant.
data HashCount : Nat -> Type where
  ZeroHashes : HashCount 0
  OneHash    : HashCount 1

loginHashCount : LoginResult -> HashCount 1
```

---

## P-3 — `token_refresh_soundness`

**Claim:** `Token.refresh/1` only issues token pairs from valid, unexpired tokens
where `typ = "refresh"`. If it returns `{:ok, pair}`, the input was a valid
refresh token at call time.

**Strategy:** Idris2 — phantom type distinguishing `AccessToken` from
`RefreshToken`; `refresh` only accepts `RefreshToken`.

**Buys:** Formal auth boundary guarantee. Prevents access tokens being used
to obtain new pairs.

**Blocked on:** Token type encoding not yet in the codebase — proof is forward-looking.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/TokenRefreshSound.idr.draft`
```idris
data TokenType = Access | Refresh

data Token : TokenType -> Type where
  MkToken : String -> Token t

-- refresh only accepts Refresh-typed tokens
tokenRefresh : Token Refresh -> IO (Token Access, Token Refresh)

-- soundness: if refresh succeeds, input had typ=refresh
refreshSound : (t : Token Refresh) -> tokenRefresh t = pure pair ->
               tokenType t = Refresh
```

---

## P-4 — `dbstore_availability_monotone`

**Claim:** No code path writes to a GenServer store when `DbStore.available?()`
returns true. The GenServer stores are dead when VeriSimDB is up.

**Strategy:** ECHIDNA reachability — static call-graph analysis showing every
`StackStore.*` / `SettingsStore.*` / `PipelineStore.*` call is guarded by
`not DbStore.available?()`. After DB-4 (Sonnet session), this becomes trivially
true (those modules are deleted) — the proof validates the deletion was complete.

**Buys:** Proves persistence is exclusive. No dual-write, no silent data loss.

**Blocked on:** DB-4 (Sonnet session) — stores must be deleted first.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/PersistenceExclusive.idr.draft`
```idris
-- After DB-4: GenServer stores do not exist.
-- Proof reduces to: all write paths go through DbStore.
persistenceExclusive : DbStoreAvailable -> WriteTarget = VeriSimDB
```

---

## P-5 — `pipeline_validation_total`

**Claim:** `PipelineEngine.validate/1` terminates on all inputs, including
pipelines with cycles.

**Strategy:** Idris2 structural induction — show the graph traversal uses a
monotonically shrinking `visited : SortedSet NodeId`, or a `fuel : Nat`
parameter. ECHIDNA property test with randomly generated cyclic graphs.

**Buys:** Totality guarantee — no infinite loop on malformed user input.

**Blocked on:** Needs cycle-detection code audit in `pipeline_engine.ex` first.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/PipelineValidationTotal.idr.draft`
```idris
-- validate terminates: formalized via fuel or visited-set shrinkage
validateTerminates : (p : Pipeline) -> (fuel : Nat) -> Maybe ValidationResult
-- key lemma: visited set grows monotonically, graph is finite
validationProgress : Visited n -> Visited (S n)
```

---

## P-6 — `verisimdb_audit_append_only`

**Claim:** The audit client (`backend/lib/stapeln/verisimdb.ex`) only exposes
`record/2` and `query/1`. No update or delete path exists on audit records.

**Strategy:** Static analysis (grep-provable) + Idris2 API type where the
`AuditClient` type has no `update` or `delete` constructor.

**Buys:** Tamper-evidence guarantee for the audit log. Required for any
compliance claim.

**Blocked on:** Nothing.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/AuditAppendOnly.idr.draft`
```idris
-- AuditClient is an abstract type with only two operations.
-- No update or delete is expressible.
data AuditOp : Type where
  Record : EventType -> Payload -> AuditOp
  Query  : Filter -> AuditOp
  -- NB: no Update or Delete constructor — append-only by construction

auditAppendOnly : AuditOp -> Not (IsUpdate auditOp)
auditAppendOnly (Record _ _) = absurd
auditAppendOnly (Query _)    = absurd
```

---

## P-7 — `token_generate_uniqueness`

**Claim:** Two `Token.generate/1` calls at different system times produce
distinct tokens. No replay is possible within the token TTL.

**Strategy:** ECHIDNA property test — generate 1000 tokens for the same user_id
at 1ms intervals, assert all distinct. Idris2 sketch: payload includes `iat`
(issued-at timestamp) which strictly increases.

**Buys:** Anti-replay guarantee. Together with P-3, closes the token-reuse
attack surface.

**Blocked on:** Nothing.

**Idris2 sketch file:** `container-stack/cerro-torre/verification/idris/TokenUniqueness.idr.draft`
```idris
-- Tokens generated at distinct times are distinct.
-- Follows from iat : SystemTime being strictly monotone.
tokenDistinct : (t1 : SystemTime) -> (t2 : SystemTime) ->
                t1 < t2 ->
                generate userId t1 `neq` generate userId t2
```

---

## Done

```bash
just e2e        # 0 failures
mix compile     # 0 warnings
```

Verify `docs/sessions/` contains all three briefs and `docs/AUTH-SEAM.adoc` exists.
Verify `.idr.draft` files exist for P-1 through P-7.

Commit:
```
feat(stapeln): Opus session — WS live events, auth seam review, 7 proof drafts for echidnabot

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

Push to `origin main`.
