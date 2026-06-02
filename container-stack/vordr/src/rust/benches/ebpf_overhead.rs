// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
//! Benchmarks for eBPF monitoring overhead.
//!
//! Measures the cost of syscall event creation, anomaly detection, and
//! syscall policy evaluation in the userspace eBPF monitoring stack.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use vordr::ebpf::{AnomalyDetector, MonitorConfig, SyscallPolicy};
use vordr::ebpf::events::{ContainerEvent, SyscallEvent};

/// Build a minimal SyscallEvent for benchmarks.
fn make_syscall_event(syscall_nr: i64) -> SyscallEvent {
    SyscallEvent {
        pid: 1234,
        tid: 1234,
        uid: 1000,
        gid: 1000,
        syscall_nr,
        args: [0; 6],
        ret: None,
        timestamp_ns: 1_000_000_000,
        comm: "bench".to_string(),
        cgroup_id: 0,
    }
}

/// Build a ContainerEvent wrapping a syscall event.
fn make_container_event(syscall_nr: i64) -> ContainerEvent {
    ContainerEvent::syscall("bench-container".to_string(), make_syscall_event(syscall_nr))
}

fn bench_syscall_event_create(c: &mut Criterion) {
    c.bench_function("syscall_event_create", |b| {
        b.iter(|| {
            black_box(make_syscall_event(1));
        })
    });
}

fn bench_monitor_config_default(c: &mut Criterion) {
    c.bench_function("monitor_config_default", |b| {
        b.iter(|| {
            black_box(MonitorConfig::default());
        })
    });
}

fn bench_syscall_policy_evaluate(c: &mut Criterion) {
    let policy = SyscallPolicy::strict();

    c.bench_function("syscall_policy_evaluate_allowed", |b| {
        b.iter(|| {
            // read() syscall (nr=0) — typically allowed
            black_box(policy.evaluate(0, 1000, 1000, "bench"));
        })
    });

    c.bench_function("syscall_policy_evaluate_denied", |b| {
        b.iter(|| {
            // kexec_load (nr=246) — blocked in strict mode
            black_box(policy.evaluate(246, 1000, 1000, "bench"));
        })
    });
}

fn bench_anomaly_detector_check(c: &mut Criterion) {
    let detector = AnomalyDetector::new(0.8);

    // Pre-populate with baseline events
    for nr in 0..20i64 {
        let event = make_container_event(nr % 20);
        let _ = detector.check_event(&event);
    }

    c.bench_function("anomaly_detect_normal", |b| {
        let event = make_container_event(10); // Frequent syscall
        b.iter(|| {
            black_box(detector.check_event(&event));
        })
    });

    c.bench_function("anomaly_detect_rare", |b| {
        let event = make_container_event(999); // Rarely seen syscall
        b.iter(|| {
            black_box(detector.check_event(&event));
        })
    });
}

criterion_group!(
    benches,
    bench_syscall_event_create,
    bench_monitor_config_default,
    bench_syscall_policy_evaluate,
    bench_anomaly_detector_check,
);
criterion_main!(benches);
