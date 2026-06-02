#!/usr/bin/env julia
# SPDX-License-Identifier: MPL-2.0
#
# ct_build.jl — Cerro Torre MVP build from .ctp manifest.
# Parses a .ctp manifest, downloads the upstream source, verifies its
# SHA-256 hash, produces an OCI image layout, then delegates to ct_mvp.jl
# for key generation, trust-store creation, and bundle signing.

using JSON3
using SHA

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

"""
    sha256_hex(data::Vector{UInt8})::String

Return the lowercase hex SHA-256 digest of `data`.
"""
sha256_hex(data::Vector{UInt8})::String = bytes2hex(sha256(data))

"""
    sha256_file(path::String)::String

Stream-hash a file in 1 MiB chunks and return its hex SHA-256 digest.
"""
function sha256_file(path::String)::String
    ctx = SHA.SHA256_CTX()
    open(path, "r") do io
        buf = Vector{UInt8}(undef, 1024 * 1024)
        while !eof(io)
            n = readbytes!(io, buf)
            SHA.update!(ctx, @view(buf[1:n]))
        end
    end
    return bytes2hex(SHA.digest!(ctx))
end

"""
    parse_ctp(path::String)::Dict{String, Dict{String, String}}

Parse an INI-style `.ctp` manifest into a nested dictionary.
"""
function parse_ctp(path::String)::Dict{String, Dict{String, String}}
    data = Dict{String, Dict{String, String}}()
    current = nothing
    for raw in eachline(path)
        line = strip(raw)
        (isempty(line) || startswith(line, "#")) && continue
        if startswith(line, "[") && endswith(line, "]")
            current = line[2:end-1]
            data[current] = Dict{String, String}()
            continue
        end
        if !isnothing(current) && occursin("=", line)
            key, value = split(line, "="; limit=2)
            key = strip(key)
            value = strip(value)
            if startswith(value, "\"") && endswith(value, "\"")
                value = value[2:end-1]
            end
            data[current][key] = value
        end
    end
    return data
end

"""
    download_file(url::String, dest::String)

Download `url` to local path `dest`.
"""
function download_file(url::String, dest::String)
    run(pipeline(`curl -sSfL -o $dest $url`))
end

# ---------------------------------------------------------------------------
# OCI layout writer
# ---------------------------------------------------------------------------

"""
    write_oci_layout(rootfs_dir, out_dir, name, version) -> String

Create a minimal OCI image layout from a root filesystem directory.
Returns the manifest digest string (sha256:...).
"""
function write_oci_layout(rootfs_dir::String, out_dir::String,
                          name::String, version::String)::String
    mkpath(out_dir)
    blobs_dir = joinpath(out_dir, "blobs", "sha256")
    mkpath(blobs_dir)

    # Create layer tarball
    layer_path = joinpath(out_dir, "layer.tar")
    run(pipeline(`tar -cf $layer_path -C $rootfs_dir .`))

    diff_id = sha256_file(layer_path)
    layer_bytes = read(layer_path)
    layer_digest = sha256_hex(layer_bytes)
    layer_size = length(layer_bytes)

    # Build config JSON
    config = Dict(
        "created"      => "2025-01-01T00:00:00Z",
        "architecture" => "amd64",
        "os"           => "linux",
        "config"       => Dict("Labels" => Dict(
            "org.opencontainers.image.ref.name" => "$name:$version"
        )),
        "rootfs"  => Dict("type" => "layers",
                          "diff_ids" => ["sha256:$diff_id"]),
        "history" => [Dict("created"    => "2025-01-01T00:00:00Z",
                           "created_by" => "ct_build")],
    )
    config_bytes = Vector{UInt8}(JSON3.write(config))
    config_digest = sha256_hex(config_bytes)

    write(joinpath(blobs_dir, config_digest), config_bytes)
    write(joinpath(blobs_dir, layer_digest), layer_bytes)

    # Build manifest JSON
    manifest = Dict(
        "schemaVersion" => 2,
        "mediaType"     => "application/vnd.oci.image.manifest.v1+json",
        "config" => Dict(
            "mediaType" => "application/vnd.oci.image.config.v1+json",
            "digest"    => "sha256:$config_digest",
            "size"      => length(config_bytes),
        ),
        "layers" => [Dict(
            "mediaType" => "application/vnd.oci.image.layer.v1.tar",
            "digest"    => "sha256:$layer_digest",
            "size"      => layer_size,
        )],
    )
    manifest_bytes = Vector{UInt8}(JSON3.write(manifest))
    manifest_digest = sha256_hex(manifest_bytes)
    write(joinpath(blobs_dir, manifest_digest), manifest_bytes)

    # Write index.json
    index = Dict(
        "schemaVersion" => 2,
        "manifests" => [Dict(
            "mediaType"   => "application/vnd.oci.image.manifest.v1+json",
            "digest"      => "sha256:$manifest_digest",
            "size"        => length(manifest_bytes),
            "annotations" => Dict(
                "org.opencontainers.image.ref.name" => "$name:$version"
            ),
        )],
    )
    open(joinpath(out_dir, "index.json"), "w") do io
        JSON3.pretty(io, index)
    end

    # Write oci-layout
    open(joinpath(out_dir, "oci-layout"), "w") do io
        JSON3.pretty(io, Dict("imageLayoutVersion" => "1.0.0"))
    end

    return "sha256:$manifest_digest"
end

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

function main()
    # --- Argument parsing (manual, mirrors the Python argparse interface) ---
    manifest_path = ""
    out_dir       = ""
    attach        = false
    log_id        = "verified-container-log-mvp"
    log_url       = "https://logs.mvp.local"
    log_operator  = "Cerro Torre MVP Log"
    store_id      = "cerro-torre-mvp"
    signer_owner  = "cerro-torre-mvp"

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--manifest"
            i += 1; manifest_path = ARGS[i]
        elseif arg == "--out-dir"
            i += 1; out_dir = ARGS[i]
        elseif arg == "--attach"
            attach = true
        elseif arg == "--log-id"
            i += 1; log_id = ARGS[i]
        elseif arg == "--log-url"
            i += 1; log_url = ARGS[i]
        elseif arg == "--log-operator"
            i += 1; log_operator = ARGS[i]
        elseif arg == "--store-id"
            i += 1; store_id = ARGS[i]
        elseif arg == "--signer-owner"
            i += 1; signer_owner = ARGS[i]
        else
            error("Unknown argument: $arg")
        end
        i += 1
    end

    isempty(manifest_path) && error("--manifest is required")
    isempty(out_dir)       && error("--out-dir is required")

    # Parse .ctp manifest
    data       = parse_ctp(manifest_path)
    metadata   = get(data, "metadata",   Dict{String,String}())
    provenance = get(data, "provenance", Dict{String,String}())
    name          = get(metadata,   "name",          "ct-image")
    version       = get(metadata,   "version",       "0.0.0")
    upstream      = get(provenance, "upstream",      "")
    upstream_hash = get(provenance, "upstream_hash", "")

    if isempty(upstream) || !startswith(upstream_hash, "sha256:")
        error("manifest requires provenance.upstream and sha256 upstream_hash")
    end

    mkpath(out_dir)
    keys_dir = joinpath(out_dir, "keys")
    mkpath(keys_dir)

    # Download and verify upstream source
    temp_dir = mktempdir()
    try
        archive_path = joinpath(temp_dir, "source.tar.gz")
        download_file(upstream, archive_path)
        digest = sha256_file(archive_path)
        if digest != replace(upstream_hash, "sha256:" => "")
            error("upstream hash mismatch")
        end

        rootfs_dir = joinpath(out_dir, "rootfs")
        isdir(rootfs_dir) && rm(rootfs_dir; recursive=true)
        mkpath(rootfs_dir)
        run(pipeline(`tar -xf $archive_path -C $rootfs_dir`))

        oci_dir = joinpath(out_dir, "oci")
        isdir(oci_dir) && rm(oci_dir; recursive=true)
        mkpath(oci_dir)
        image_digest = write_oci_layout(rootfs_dir, oci_dir, name, version)
    finally
        rm(temp_dir; recursive=true, force=true)
    end

    # Delegate to ct_mvp.jl for key generation, trust-store, and bundle
    ct_mvp = joinpath(@__DIR__, "ct_mvp.jl")

    run(pipeline(`julia $ct_mvp keygen --out-dir $keys_dir`))

    run(pipeline(`julia $ct_mvp trust-store
        --signer-pub $(joinpath(keys_dir, "signer.pub"))
        --log-pub    $(joinpath(keys_dir, "log.pub"))
        --log-id     $log_id
        --log-url    $log_url
        --log-operator $log_operator
        --store-id   $store_id
        --signer-owner $signer_owner
        --out        $(joinpath(out_dir, "trust-store.json"))`))

    run(pipeline(`julia $ct_mvp bundle
        --image-name   $name:$version
        --image-digest $image_digest
        --signer-key   $(joinpath(keys_dir, "signer.key"))
        --signer-pub   $(joinpath(keys_dir, "signer.pub"))
        --log-key      $(joinpath(keys_dir, "log.key"))
        --log-id       $log_id
        --out          $(joinpath(out_dir, "bundle.json"))`))

    if attach
        run(pipeline(`tools/mvp/publish_bundle.sh
            $name:$version
            $(joinpath(out_dir, "bundle.json"))
            application/vnd.verified-container.bundle+json`))
    end

    # Write summary
    summary = Dict(
        "name"        => name,
        "version"     => version,
        "imageDigest" => image_digest,
        "rootfs"      => joinpath(out_dir, "rootfs"),
        "ociLayout"   => joinpath(out_dir, "oci"),
        "bundle"      => joinpath(out_dir, "bundle.json"),
        "trustStore"  => joinpath(out_dir, "trust-store.json"),
    )
    open(joinpath(out_dir, "summary.json"), "w") do io
        JSON3.pretty(io, summary)
    end
end

# Run when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
