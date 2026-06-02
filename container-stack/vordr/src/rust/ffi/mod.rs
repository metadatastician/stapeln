// SPDX-License-Identifier: MPL-2.0
//! Foreign Function Interface bindings

pub mod gatekeeper;

pub use gatekeeper::{
    init as init_gatekeeper, version as gatekeeper_version,
    validate_image,
    ConfigValidator, NetworkMode, ValidatedConfig,
};
