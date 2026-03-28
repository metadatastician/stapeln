// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Stapeln V-lang API — Container stack management client.
module stapeln

pub enum StackState {
	stopped
	starting
	running
	stopping
	failed
	unknown
}

pub struct Stack {
pub:
	name       string
	state      StackState
	containers int
	image      string
}

pub struct DeployRequest {
pub:
	stack_name string
	image      string
	replicas   int
	port       int
}

fn C.stapeln_valid_state_transition(from int, to int) int
fn C.stapeln_clamp_replicas(count int) int
fn C.stapeln_normalize_path(path_ptr &u8, out_ptr &&u8) int

// can_transition checks if a stack state transition is valid.
pub fn can_transition(from StackState, to StackState) bool {
	return C.stapeln_valid_state_transition(int(from), int(to)) == 1
}

// clamp_replicas ensures replica count is within bounds [1, 100].
pub fn clamp_replicas(count int) int {
	return C.stapeln_clamp_replicas(count)
}
