# SPDX-License-Identifier: PMPL-1.0-or-later
# Containerfile -- Multi-stage build for Cerro Torre (ct)
#
# Stage 1: Build Ada/SPARK binary and Rust signing utility
# Stage 2: Minimal runtime with ct + ct-sign binaries
#
# Build:  podman build -f Containerfile -t ct:latest .
# Run:    podman run --rm ct:latest --version

# ---------------------------------------------------------------------------
# Stage 1 -- ada-builder
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS ada-builder

# Avoid interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# Install Ada/SPARK toolchain, Alire prerequisites, Rust, and libcurl dev
RUN apt-get update && apt-get install -y --no-install-recommends \
        gnat-14 \
        gprbuild \
        libcurl4-openssl-dev \
        curl \
        ca-certificates \
        git \
        unzip \
        make \
    && rm -rf /var/lib/apt/lists/*

# Install Alire — use the explicit-version download URL (not /latest/download/),
# because GitHub's /latest/download/<filename> redirect requires <filename>
# to be an asset of the *current* latest release. Alire's asset filenames
# embed the version (alr-X.Y.Z-bin-...), so a hardcoded version in the URL
# silently breaks the moment a new Alire release ships.
ARG ALIRE_VERSION=2.1.0
# The release zip lays the binary out as `bin/alr` (not a bare `alr` at the
# archive root), so unzip into /tmp and install the located binary. This is
# robust to either layout and avoids the `chmod /usr/local/bin/alr: No such
# file or directory` failure that the naive `unzip -d /usr/local/bin` form hits.
RUN curl -fsSL "https://github.com/alire-project/alire/releases/download/v${ALIRE_VERSION}/alr-${ALIRE_VERSION}-bin-x86_64-linux.zip" \
        -o /tmp/alr.zip \
    && unzip /tmp/alr.zip -d /tmp/alr-extract \
    && install -m 0755 "$(find /tmp/alr-extract -type f -name alr | head -n 1)" \
        /usr/local/bin/alr \
    && rm -rf /tmp/alr.zip /tmp/alr-extract

# Install Rust toolchain (minimal, stable)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Copy Ada/SPARK sources and build
WORKDIR /build
COPY alire.toml cerro_torre.gpr ./
COPY src/ src/
# tests/ is a Source_Dir of cerro_torre.gpr for every Feature_Set (it holds
# the ct_test_* mains), so the project does not build without it.
COPY tests/ tests/

# config/ is intentionally NOT copied: Alire generates
# config/cerro_torre_config.gpr (referenced by cerro_torre.gpr) during
# `alr build`. The directory is gitignored and absent on a clean checkout,
# so `COPY config/ config/` broke builds from a fresh clone (stapeln#17).
#
# -n keeps the build non-interactive: with no prior settings Alire would
# otherwise prompt for a toolchain; -n auto-selects the default gnat_native
# + gprbuild and provisions them without blocking on stdin.
RUN alr -n build

# Build the Rust signing utility
COPY Cargo.toml Cargo.lock ./
COPY src-rust/ src-rust/

RUN cargo build --release

# ---------------------------------------------------------------------------
# Stage 2 -- runtime
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base:latest AS runtime

# Install libcurl runtime for HTTP/TLS operations
RUN apk add --no-cache libcurl-openssl4

# Copy the Ada ct binary from the builder stage
COPY --from=ada-builder /build/bin/ct /usr/local/bin/ct

# Copy the Rust ct-sign binary from the builder stage
COPY --from=ada-builder /build/target/release/cerro-sign /usr/local/bin/ct-sign

# Non-root user for runtime
RUN addgroup -S cerro && adduser -S cerro -G cerro
USER cerro

ENTRYPOINT ["ct"]
