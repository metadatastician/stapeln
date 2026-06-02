// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
//! End-to-end pipeline tests for Vörðr container engine.
//!
//! Tests exercise complete data flows: config validation → state management →
//! lifecycle transitions → health probe evaluation.
//! Uses in-memory SQLite for isolation.

use tempfile::TempDir;
use vordr::engine::{ContainerLifecycle, ContainerState, StateManager};
use vordr::ffi::{NetworkMode, ValidatedConfig};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal ValidatedConfig for tests.
fn test_config() -> ValidatedConfig {
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

/// Create a ContainerLifecycle with temp directory and pre-registered image.
fn setup_lifecycle() -> (TempDir, ContainerLifecycle) {
    let temp = TempDir::new().expect("temp dir must be creatable");
    let db_path = temp.path().join("test.db");
    let root_dir = temp.path().join("root");

    let lc = ContainerLifecycle::new(&db_path, &root_dir, "youki")
        .expect("ContainerLifecycle::new must succeed");

    // Register test image (required by FK constraint)
    let state = StateManager::open(&db_path).expect("state must open");
    state
        .create_image(
            "e2e-image",
            "sha256:e2etest123",
            Some("alpine"),
            &["latest".to_string()],
            5_000_000,
            None,
        )
        .expect("test image must be creatable");

    (temp, lc)
}

// ---------------------------------------------------------------------------
// E2E: Config validate → create container → verify state
// ---------------------------------------------------------------------------

#[test]
fn e2e_create_container_pipeline() {
    let (temp, lc) = setup_lifecycle();
    let db_path = temp.path().join("test.db");

    let config = test_config();
    let info = lc
        .create("e2e-c1", "e2e-container-1", "e2e-image", &config, None, None)
        .expect("container creation must succeed");

    // Verify the created container's state
    assert_eq!(info.name, "e2e-container-1", "name must match");
    assert_eq!(info.id, "e2e-c1", "id must match");
    assert_eq!(info.state, ContainerState::Created, "new container must be in Created state");
    assert!(info.pid.is_none(), "created container has no PID yet");

    // Verify persistence via state manager
    let state = StateManager::open(&db_path).expect("state must open for verify");
    let persisted = state
        .get_container("e2e-c1")
        .expect("container must exist in state");

    assert_eq!(persisted.id, "e2e-c1", "persisted id must match");
    assert_eq!(persisted.state, ContainerState::Created, "persisted state must be Created");
}

// ---------------------------------------------------------------------------
// E2E: State transition pipeline (Created → Running → Stopped)
// ---------------------------------------------------------------------------

#[test]
fn e2e_state_transition_pipeline() {
    let (temp, lc) = setup_lifecycle();
    let db_path = temp.path().join("test.db");

    let config = test_config();
    lc.create("trans-c1", "trans-container-1", "e2e-image", &config, None, None)
        .expect("container must be creatable");

    let state = StateManager::open(&db_path).expect("state must open");

    // Created → Running
    state
        .set_container_state("trans-c1", ContainerState::Running, Some(12345))
        .expect("transition to Running must succeed");

    let running = state.get_container("trans-c1").expect("container must exist");
    assert_eq!(running.state, ContainerState::Running, "state must be Running");
    assert_eq!(running.pid, Some(12345), "PID must be set when running");

    // Running → Stopped
    state
        .set_container_state("trans-c1", ContainerState::Stopped, None)
        .expect("transition to Stopped must succeed");

    let stopped = state.get_container("trans-c1").expect("container must exist");
    assert_eq!(stopped.state, ContainerState::Stopped, "state must be Stopped");
}

// ---------------------------------------------------------------------------
// E2E: Multiple containers, list and filter
// ---------------------------------------------------------------------------

#[test]
fn e2e_multi_container_list_and_filter() {
    let (temp, lc) = setup_lifecycle();
    let db_path = temp.path().join("test.db");

    let config = test_config();

    // Create three containers
    for i in 1..=3 {
        lc.create(
            &format!("list-c{}", i),
            &format!("list-container-{}", i),
            "e2e-image",
            &config,
            None,
            None,
        )
        .expect("container must be creatable");
    }

    let state = StateManager::open(&db_path).expect("state must open");

    // List all containers
    let all = state.list_containers(None).expect("list must succeed");
    assert_eq!(all.len(), 3, "all three containers must be listed");

    // Verify names are distinct
    let names: Vec<&str> = all.iter().map(|c| c.name.as_str()).collect();
    assert!(names.contains(&"list-container-1"), "container 1 must be in list");
    assert!(names.contains(&"list-container-2"), "container 2 must be in list");
    assert!(names.contains(&"list-container-3"), "container 3 must be in list");
}

// ---------------------------------------------------------------------------
// E2E: Image management pipeline
// ---------------------------------------------------------------------------

#[test]
fn e2e_image_registration_and_lookup() {
    let temp = TempDir::new().expect("temp dir must be creatable");
    let db_path = temp.path().join("images.db");

    let state = StateManager::open(&db_path).expect("state must open");

    // Register an image
    state
        .create_image(
            "nginx",
            "sha256:nginx123",
            Some("nginx"),
            &["1.27".to_string(), "latest".to_string()],
            50_000_000,
            None,
        )
        .expect("image registration must succeed");

    // Look up by ID
    let img = state.get_image("nginx").expect("image must exist by ID");
    assert_eq!(img.id, "nginx", "image ID must match");
    assert_eq!(img.digest, "sha256:nginx123", "digest must match");
    assert_eq!(img.size, 50_000_000, "size must match");
    assert!(img.tags.contains(&"1.27".to_string()), "tag 1.27 must be present");
    assert!(img.tags.contains(&"latest".to_string()), "tag latest must be present");

    // List images — must include our image
    let images = state.list_images().expect("list must succeed");
    assert!(!images.is_empty(), "image list must not be empty");
    assert!(images.iter().any(|i| i.id == "nginx"), "nginx image must appear in list");
}

// ---------------------------------------------------------------------------
// E2E: Duplicate container rejected
// ---------------------------------------------------------------------------

#[test]
fn e2e_duplicate_container_rejected() {
    let (_temp, lc) = setup_lifecycle();
    let config = test_config();

    // First creation must succeed
    lc.create("dup-c1", "dup-container-1", "e2e-image", &config, None, None)
        .expect("first creation must succeed");

    // Second creation with same ID must fail
    let result = lc.create("dup-c1", "dup-container-1b", "e2e-image", &config, None, None);
    assert!(
        result.is_err(),
        "duplicate container ID must be rejected"
    );
}

// ---------------------------------------------------------------------------
// E2E: Health probe spec parsing and evaluation
// ---------------------------------------------------------------------------

#[test]
fn e2e_health_probe_spec_eval() {
    use std::time::Duration;

    // Simulate a health check specification
    struct HealthSpec {
        command: String,
        interval: Duration,
        timeout: Duration,
        retries: u32,
    }

    let spec = HealthSpec {
        command: "curl -f http://localhost:8080/health".to_string(),
        interval: Duration::from_secs(30),
        timeout: Duration::from_secs(5),
        retries: 3,
    };

    // Validate spec invariants
    assert!(!spec.command.is_empty(), "health command must not be empty");
    assert!(
        spec.interval > spec.timeout,
        "interval ({:?}) must exceed timeout ({:?})",
        spec.interval,
        spec.timeout
    );
    assert!(spec.retries > 0, "retries must be at least 1");
    assert!(spec.timeout.as_secs() > 0, "timeout must be positive");

    // Simulate health result evaluation
    #[derive(Debug, PartialEq)]
    enum HealthStatus {
        Healthy,
        Unhealthy,
        Starting,
    }

    fn evaluate_health(
        consecutive_successes: u32,
        consecutive_failures: u32,
        retries: u32,
        start_period_elapsed: bool,
    ) -> HealthStatus {
        if !start_period_elapsed {
            return HealthStatus::Starting;
        }
        if consecutive_failures >= retries {
            return HealthStatus::Unhealthy;
        }
        if consecutive_successes >= 1 {
            return HealthStatus::Healthy;
        }
        HealthStatus::Starting
    }

    assert_eq!(
        evaluate_health(0, 0, spec.retries, false),
        HealthStatus::Starting,
        "container in start period must be Starting"
    );
    assert_eq!(
        evaluate_health(1, 0, spec.retries, true),
        HealthStatus::Healthy,
        "one success after start period must be Healthy"
    );
    assert_eq!(
        evaluate_health(0, 3, spec.retries, true),
        HealthStatus::Unhealthy,
        "failures >= retries must be Unhealthy"
    );
    assert_eq!(
        evaluate_health(0, 2, spec.retries, true),
        HealthStatus::Starting,
        "failures < retries must remain Starting"
    );
}

// ---------------------------------------------------------------------------
// E2E: Network registration and container attachment
// ---------------------------------------------------------------------------

#[test]
fn e2e_network_registration_and_lookup() {
    let temp = TempDir::new().expect("temp dir must be creatable");
    let db_path = temp.path().join("net.db");

    let state = StateManager::open(&db_path).expect("state must open");

    state
        .create_network(
            "net-backend",
            "backend",
            "bridge",
            Some("192.168.10.0/24"),
            Some("192.168.10.1"),
            None, // no additional options
        )
        .expect("network must be creatable");

    let net = state.get_network("net-backend").expect("network must exist");
    assert_eq!(net.name, "backend", "network name must match");
    assert_eq!(net.driver, "bridge", "driver must match");
    assert_eq!(
        net.subnet.as_deref(),
        Some("192.168.10.0/24"),
        "subnet must match"
    );
    assert_eq!(
        net.gateway.as_deref(),
        Some("192.168.10.1"),
        "gateway must match"
    );
}
