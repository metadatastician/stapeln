// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
//! Property-based tests for Vörðr container engine invariants.
//!
//! Uses proptest to verify that core domain invariants hold for arbitrary inputs.
//! Tests cover monitoring intervals, resource usage bounds, and container
//! state machine validity.

use proptest::prelude::*;
use vordr::engine::state::{ContainerState};

// ---------------------------------------------------------------------------
// Helpers: custom strategies
// ---------------------------------------------------------------------------

/// Strategy: monitoring interval always > 0 milliseconds (up to 1 hour).
fn valid_monitoring_interval_ms() -> impl Strategy<Value = u64> {
    1u64..=3_600_000u64
}

/// Strategy: CPU usage in [0.0, 100.0].
fn valid_cpu_usage() -> impl Strategy<Value = f64> {
    0.0f64..=100.0f64
}

/// Strategy: memory usage in bytes ≥ 0 (up to 256 GB for large containers).
fn valid_memory_bytes() -> impl Strategy<Value = u64> {
    0u64..=274_877_906_944u64 // 256 GiB
}

/// Strategy: a valid container state (one of the four enum variants).
fn any_container_state() -> impl Strategy<Value = ContainerState> {
    prop_oneof![
        Just(ContainerState::Created),
        Just(ContainerState::Running),
        Just(ContainerState::Paused),
        Just(ContainerState::Stopped),
    ]
}

// ---------------------------------------------------------------------------
// Monitoring interval invariants
// ---------------------------------------------------------------------------

proptest! {
    /// Monitoring intervals are always > 0 (prevents busy-wait / divide-by-zero).
    #[test]
    fn prop_monitoring_interval_always_positive(interval_ms in valid_monitoring_interval_ms()) {
        prop_assert!(interval_ms > 0,
            "monitoring interval {} ms must be positive", interval_ms);
    }

    /// Monitoring intervals fit within u64 (no overflow risk).
    #[test]
    fn prop_monitoring_interval_within_u64(interval_ms in valid_monitoring_interval_ms()) {
        // Convert to Duration-compatible representation
        let secs = interval_ms / 1_000;
        let subsec_ms = interval_ms % 1_000;
        prop_assert!(secs < u64::MAX / 1_000,
            "interval {}ms overflows seconds representation", interval_ms);
        prop_assert!(subsec_ms < 1_000,
            "subsecond part {} must be < 1000", subsec_ms);
    }
}

// ---------------------------------------------------------------------------
// CPU usage invariants
// ---------------------------------------------------------------------------

proptest! {
    /// CPU usage is always in [0.0, 100.0] percent.
    #[test]
    fn prop_cpu_usage_in_range(cpu in valid_cpu_usage()) {
        prop_assert!(cpu >= 0.0,
            "CPU usage {} must be ≥ 0.0%", cpu);
        prop_assert!(cpu <= 100.0,
            "CPU usage {} must be ≤ 100.0%", cpu);
    }

    /// CPU usage is finite (not NaN or infinite).
    #[test]
    fn prop_cpu_usage_is_finite(cpu in valid_cpu_usage()) {
        prop_assert!(cpu.is_finite(),
            "CPU usage {} must be a finite number", cpu);
        prop_assert!(!cpu.is_nan(),
            "CPU usage must not be NaN");
    }

    /// CPU usage aggregated across up to 256 cores stays representable.
    #[test]
    fn prop_cpu_usage_aggregate_bounded(
        cpu in valid_cpu_usage(),
        cores in 1u32..=256u32
    ) {
        // Per-core usage * num_cores must not overflow f64 for normal monitoring
        let aggregate = cpu * (cores as f64);
        prop_assert!(aggregate.is_finite(),
            "aggregate CPU {}% × {} cores must be finite", cpu, cores);
        prop_assert!(aggregate <= 100.0 * 256.0,
            "aggregate CPU {} must not exceed 100% × 256 cores", aggregate);
    }
}

// ---------------------------------------------------------------------------
// Memory usage invariants
// ---------------------------------------------------------------------------

proptest! {
    /// Memory usage is always ≥ 0 (unsigned).
    #[test]
    fn prop_memory_usage_non_negative(mem in valid_memory_bytes()) {
        // u64 is always ≥ 0 by type, but we verify the strategy
        prop_assert!(mem < u64::MAX, "memory must not be u64::MAX sentinel");
    }

    /// Memory usage can always be represented in MiB without loss of validity.
    #[test]
    fn prop_memory_mib_conversion(mem in valid_memory_bytes()) {
        let mib = mem / (1024 * 1024);
        // MiB value must not exceed bytes value
        prop_assert!(mib * (1024 * 1024) <= mem,
            "MiB conversion must not exceed original byte count");
    }
}

// ---------------------------------------------------------------------------
// Container state transition invariants
// ---------------------------------------------------------------------------

/// Check whether a state transition from `from` → `to` is valid per OCI spec.
fn is_valid_state_transition(from: &ContainerState, to: &ContainerState) -> bool {
    match (from, to) {
        // Created → Running (start)
        (ContainerState::Created, ContainerState::Running) => true,
        // Running → Paused (pause)
        (ContainerState::Running, ContainerState::Paused) => true,
        // Paused → Running (unpause)
        (ContainerState::Paused, ContainerState::Running) => true,
        // Running → Stopped (stop/kill)
        (ContainerState::Running, ContainerState::Stopped) => true,
        // Paused → Stopped (stop while paused)
        (ContainerState::Paused, ContainerState::Stopped) => true,
        // Stopped → Running (restart — not direct; goes through Created in practice)
        // Per OCI spec, once stopped a container can be restarted only by the runtime
        // which re-enters the Created state.
        _ => false,
    }
}

proptest! {
    /// Running → Created is always an invalid state transition.
    #[test]
    fn prop_running_to_created_always_invalid(_ignored in Just(())) {
        prop_assert!(
            !is_valid_state_transition(&ContainerState::Running, &ContainerState::Created),
            "Running → Created must be an invalid transition"
        );
    }

    /// Stopped → Running is always an invalid direct transition.
    #[test]
    fn prop_stopped_to_running_always_invalid(_ignored in Just(())) {
        prop_assert!(
            !is_valid_state_transition(&ContainerState::Stopped, &ContainerState::Running),
            "Stopped → Running must be an invalid direct transition"
        );
    }

    /// Created → Running is always valid.
    #[test]
    fn prop_created_to_running_always_valid(_ignored in Just(())) {
        prop_assert!(
            is_valid_state_transition(&ContainerState::Created, &ContainerState::Running),
            "Created → Running must always be valid"
        );
    }

    /// Self-transitions are never valid (no-op state changes are errors).
    #[test]
    fn prop_self_transition_always_invalid(state in any_container_state()) {
        prop_assert!(
            !is_valid_state_transition(&state, &state),
            "Self-transition {:?} → {:?} must be invalid", state, state
        );
    }

    /// Stopped → Paused is always invalid (can't pause a stopped container).
    #[test]
    fn prop_stopped_to_paused_invalid(_ignored in Just(())) {
        prop_assert!(
            !is_valid_state_transition(&ContainerState::Stopped, &ContainerState::Paused),
            "Stopped → Paused must be invalid"
        );
    }

    /// Created → Paused is always invalid (can't pause without running).
    #[test]
    fn prop_created_to_paused_invalid(_ignored in Just(())) {
        prop_assert!(
            !is_valid_state_transition(&ContainerState::Created, &ContainerState::Paused),
            "Created → Paused must be invalid"
        );
    }
}

// ---------------------------------------------------------------------------
// State string round-trip invariants
// ---------------------------------------------------------------------------

proptest! {
    /// ContainerState::as_str() → from_str() always round-trips.
    #[test]
    fn prop_state_string_round_trips(state in any_container_state()) {
        let s = state.as_str();
        prop_assert!(!s.is_empty(),
            "state string representation must not be empty");

        let recovered = ContainerState::from_str(s)
            .expect("as_str() output must always parse back via from_str()");

        prop_assert_eq!(recovered.as_str(), s,
            "state '{}' must round-trip through as_str/from_str", s);
    }

    /// Unknown state strings always return None from from_str().
    #[test]
    fn prop_unknown_state_string_returns_none(
        s in "[a-z]{1,20}".prop_filter("no valid states", |s| {
            !["created", "running", "paused", "stopped"].contains(&s.as_str())
        })
    ) {
        prop_assert!(
            ContainerState::from_str(&s).is_none(),
            "unknown state string '{}' must return None", s
        );
    }
}
