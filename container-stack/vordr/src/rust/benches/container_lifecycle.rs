// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
//! Benchmarks for container lifecycle operations.
//!
//! Measures the cost of state manager operations, container creation,
//! state transitions, and bulk list queries. Uses tempfile for isolation.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use tempfile::TempDir;
use vordr::engine::{ContainerLifecycle, ContainerState, StateManager};
use vordr::ffi::{NetworkMode, ValidatedConfig};

/// Create a minimal ValidatedConfig for benchmarks.
fn bench_config() -> ValidatedConfig {
    ValidatedConfig {
        privileged: false,
        user_namespace: true,
        user_id: 1000,
        network_mode: NetworkMode::Unprivileged,
        capabilities: vec![],
        no_new_privileges: true,
        readonly_rootfs: false,
    }
}

/// Set up a lifecycle with a pre-registered test image.
/// Returns both the TempDir (to keep it alive) and the lifecycle.
fn setup_lifecycle() -> (TempDir, ContainerLifecycle) {
    let temp_dir = TempDir::new().unwrap();
    let db_path = temp_dir.path().join("bench.db");
    let root_dir = temp_dir.path().join("root");

    let lifecycle = ContainerLifecycle::new(&db_path, &root_dir, "youki").unwrap();

    // Register image required by foreign key constraint
    let state = StateManager::open(&db_path).unwrap();
    state
        .create_image(
            "bench-image",
            "sha256:bench123",
            Some("alpine"),
            &["latest".to_string()],
            10_000_000,
            None,
        )
        .unwrap();

    (temp_dir, lifecycle)
}

fn bench_state_manager_creation(c: &mut Criterion) {
    c.bench_function("state_manager_create", |b| {
        b.iter(|| {
            let temp_dir = TempDir::new().unwrap();
            let db_path = temp_dir.path().join("bench.db");
            black_box(StateManager::open(&db_path).unwrap());
        })
    });
}

fn bench_container_creation(c: &mut Criterion) {
    let (temp, lifecycle) = setup_lifecycle();
    let db_path = temp.path().join("bench.db");
    let config = bench_config();

    let mut counter = 0u32;
    c.bench_function("container_create", |b| {
        b.iter(|| {
            counter += 1;
            let id = format!("bench-{}", counter);
            let name = format!("bench-container-{}", counter);
            black_box(
                lifecycle
                    .create(&id, &name, "bench-image", &config, None, None)
                    .unwrap(),
            );
        })
    });

    // Keep temp alive for the duration of the bench
    let _ = db_path;
    let _ = temp;
}

fn bench_container_list(c: &mut Criterion) {
    let (temp, lifecycle) = setup_lifecycle();
    let db_path = temp.path().join("bench.db");
    let config = bench_config();

    // Pre-populate 100 containers
    for i in 0..100 {
        lifecycle
            .create(
                &format!("bulk-{}", i),
                &format!("container-{}", i),
                "bench-image",
                &config,
                None,
                None,
            )
            .unwrap();
    }

    let state = StateManager::open(&db_path).unwrap();
    c.bench_function("container_list_100", |b| {
        b.iter(|| {
            black_box(state.list_containers(None).unwrap());
        })
    });

    let _ = temp;
}

fn bench_container_get(c: &mut Criterion) {
    let (temp, lifecycle) = setup_lifecycle();
    let db_path = temp.path().join("bench.db");
    let config = bench_config();

    lifecycle
        .create("get-target", "get-target-container", "bench-image", &config, None, None)
        .unwrap();

    let state = StateManager::open(&db_path).unwrap();

    c.bench_function("container_get_by_id", |b| {
        b.iter(|| {
            black_box(state.get_container("get-target").unwrap());
        })
    });

    c.bench_function("container_get_by_name", |b| {
        b.iter(|| {
            black_box(state.get_container("get-target-container").unwrap());
        })
    });

    let _ = temp;
}

fn bench_state_transitions(c: &mut Criterion) {
    let (temp, lifecycle) = setup_lifecycle();
    let db_path = temp.path().join("bench.db");
    let config = bench_config();

    let state = StateManager::open(&db_path).unwrap();

    c.bench_function("state_transition_create_to_running", |b| {
        let mut counter = 0u32;
        b.iter(|| {
            counter += 1;
            let id = format!("trans-{}", counter);
            let name = format!("trans-container-{}", counter);
            lifecycle
                .create(&id, &name, "bench-image", &config, None, None)
                .unwrap();
            black_box(
                state
                    .set_container_state(&id, ContainerState::Running, Some(1234))
                    .unwrap(),
            );
        })
    });

    let _ = temp;
}

criterion_group!(
    benches,
    bench_state_manager_creation,
    bench_container_creation,
    bench_container_list,
    bench_container_get,
    bench_state_transitions
);
criterion_main!(benches);
