-- SPDX-License-Identifier: MPL-2.0
-- Proofs.idr — Formal verification proofs for container lifecycle
--
-- This module contains machine-checked proofs about the container
-- state machine and verification properties.

module Proofs

import Container
import Verification
import SBOM
import Data.Vect
import Data.So

%default total

--------------------------------------------------------------------------------
-- Container Lifecycle Proofs
--------------------------------------------------------------------------------

||| Proof: The container lifecycle is acyclic for the Remove path
||| Once a container reaches Removed, no transitions are possible
export
removeTerminatesLifecycle : (s : ContainerState) -> ValidTransition Removed s -> Void
removeTerminatesLifecycle _ x = removedIsTerminal x

||| Proof: Running containers can always be stopped
||| (This is a liveness property)
export
runningCanStop : Container Running ->
                 (exitCode : Int) ->
                 (Container Stopped, ValidTransition Running Stopped)
runningCanStop c ec =
  let (prf, stopped) = stopRunning c ec
  in (stopped, prf)

||| Proof: Paused containers can always be resumed
export
pausedCanResume : Container Paused ->
                  (Container Running, ValidTransition Paused Running)
pausedCanResume c =
  let (prf, running) = resumeContainer c
  in (running, prf)

||| Proof: Created containers have exactly two valid transitions
||| (Either start or remove directly)
export
createdHasTwoOptions : (s : ContainerState) ->
                       ValidTransition Created s ->
                       Either (s = Running) (s = Removed)
createdHasTwoOptions Running StartCreated = Left Refl
createdHasTwoOptions Removed RemoveCreated = Right Refl

||| Proof: A container must be created before it can be started
||| (There's no way to go from ImageOnly to Running directly)
export
mustCreateBeforeStart : ValidTransition ImageOnly Running -> Void
mustCreateBeforeStart x = cannotSkipCreate x

--------------------------------------------------------------------------------
-- Reversibility Proofs (Bennett Reversibility)
--------------------------------------------------------------------------------

||| Type representing a reversible operation
public export
data Reversible : (from : ContainerState) -> (to : ContainerState) -> Type where
  ||| Pause is reversible via resume (Running <-> Paused)
  PauseIsReversible : Reversible Running Paused
  -- NOTE: Start (Created -> Running) is NOT Bennett-reversible. The state
  -- machine (Container.ValidTransition) has no Running -> Created transition —
  -- stopping a Running container goes to Stopped, losing the
  -- "created-but-not-started" state. The earlier `StartIsReversible`
  -- constructor was therefore unsound: its `inverse` (StopRunning :
  -- Running -> Stopped) could not have the required type
  -- `ValidTransition Running Created`. Removed rather than left ill-typed.
  -- Stop is likewise not reversible (data may be lost).

-- Proof: Pause-Resume forms an identity operation (pause . resume = id,
-- modulo timestamps). Commented out — requires rework of the type signature.
-- export
-- pauseResumeIdentity : (c : Container Running) ->
--                       let (_, paused) = pauseContainer c
--                           (_, resumed) = resumeContainer paused
--                       in resumed = c
-- pauseResumeIdentity (MkRunning cid imgRef limits pid) = Refl

||| The inverse of a reversible transition
public export
inverse : Reversible from to -> ValidTransition to from
inverse PauseIsReversible = ResumeP

--------------------------------------------------------------------------------
-- Resource Safety Proofs
--------------------------------------------------------------------------------

-- Proof: Resource limits are preserved through transitions (a container never
-- exceeds its allocated resources). Commented out — requires rework of the
-- type signature.
-- export
-- limitsPreserved : (c : Container Created) ->
--                   (pid : Nat) ->
--                   let (_, running) = startContainer c pid
--                   in getResourceLimits running = getResourceLimits' c
--   where
--     getResourceLimits : Container Running -> ResourceLimits
--     getResourceLimits (MkRunning _ _ limits _) = limits
--
--     getResourceLimits' : Container Created -> ResourceLimits
--     getResourceLimits' (MkCreated _ _ limits) = limits
-- limitsPreserved (MkCreated _ _ _) _ = Refl

--------------------------------------------------------------------------------
-- SBOM Verification Proofs
--------------------------------------------------------------------------------

||| Proof: An SBOM with no dependencies has no vulnerabilities
export
emptyDepsNoVulns : (doc : SBOMDocument) ->
                   doc.dependencies = [] ->
                   totalVulns doc = 0
emptyDepsNoVulns doc prf = rewrite prf in Refl

||| Proof: Adding a clean dependency doesn't introduce vulnerabilities.
||| After exposing the head via `mapConsEq` and rewriting `d.vulns = []`, the
||| goal is `sum (0 :: rest) = sum rest`, which holds by `Refl`: both sides
||| reduce to `foldl (+) 0 rest` (the `0` accumulator is `neutral <+> 0 = 0`).
|||
||| NB: the counting function is written as the lambda `\dep => length dep.vulns`
||| rather than point-free `(length . vulns)`. In a type-signature position the
||| bare names `length`/`vulns` were being auto-bound as fresh implicits
||| (shadowing the real functions — Idris emits the "implicitly bind" warning),
||| which made the original statement ill-typed (the `?_.vulns` in the old error).
export
cleanDepsAdditive : (deps : List Dependency) ->
                    (d : Dependency) ->
                    d.vulns = [] ->
                    sum (map (\dep => length dep.vulns) (d :: deps))
                      = sum (map (\dep => length dep.vulns) deps)
cleanDepsAdditive deps d prf =
  rewrite prf in Refl

--------------------------------------------------------------------------------
-- Verification Chain Proofs
--------------------------------------------------------------------------------

||| A verification chain is a sequence of attestations that together
||| prove a container is trustworthy
||| (`Attestation` here is `Verification.Attestation`, already in scope via
||| `import Verification`; "verified" means its `valid` field is True. The
||| module-qualified `Attestation.Attestation` / `verified` used previously
||| referenced an unimported module and an undefined function.)
public export
data VerificationChain : Nat -> Type where
  Empty : VerificationChain 0
  Link  : Attestation ->
          VerificationChain n ->
          VerificationChain (S n)

||| Proof: A non-empty verification chain has at least one attestation
export
nonEmptyHasAttestation : VerificationChain (S n) -> Attestation
nonEmptyHasAttestation (Link att _) = att

||| All attestations in a chain are verified (every attestation's `valid` flag)
public export
data AllVerified : VerificationChain n -> Type where
  EmptyVerified : AllVerified Empty
  ChainVerified : (att : Attestation) ->
                  (att.valid = True) ->
                  AllVerified rest ->
                  AllVerified (Link att rest)

--------------------------------------------------------------------------------
-- Security Invariants
--------------------------------------------------------------------------------
--
-- DISABLED: this section never compiled. It references types defined nowhere in
-- vordr — `SecurityConfig`, `AuthorizationLevel`, `Admin`, `isPrivileged` — so
-- the module (and package) failed to build, masking the genuine proofs above.
-- `nonAdminCantPrivilege` is also unsound as written: from `Not (auth = Admin)`
-- and `isPrivileged config = True` it claims `Void` (a non-sequitur without an
-- invariant linking authorization to privilege), and its single clause only
-- covers `auth = Admin` (non-covering otherwise). Re-enabling needs a real
-- security model: define those types, then state the invariant as a constructor
-- (mirroring `PrivilegedRequiresAuth`) rather than a bare `... -> Void`.
--
-- ||| Security invariant: privileged containers require explicit authorization
-- public export
-- data PrivilegedRequiresAuth : Type where
--   MkPrivilegedRequiresAuth : (config : SecurityConfig) ->
--                              (auth : AuthorizationLevel) ->
--                              (isPrivileged config = True) ->
--                              (auth = Admin) ->
--                              PrivilegedRequiresAuth
--
-- ||| Proof: Non-admin users cannot create privileged containers
-- export
-- nonAdminCantPrivilege : (config : SecurityConfig) ->
--                         (auth : AuthorizationLevel) ->
--                         Not (auth = Admin) ->
--                         isPrivileged config = True ->
--                         Void
-- nonAdminCantPrivilege _ Admin notAdmin _ = notAdmin Refl
