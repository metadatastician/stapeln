#!/usr/bin/env julia
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# ct_pack.jl — Cerro Torre MVP pack (wrap an existing OCI image).
# Fetches the image digest via `oras`, then delegates to ct_mvp.jl for
# key generation, trust-store creation, and attestation bundle signing.

using JSON3

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""
    get_digest(image_ref::String)::String

Use `oras manifest fetch --descriptor` to retrieve the digest of an OCI
image reference.
"""
function get_digest(image_ref::String)::String
    raw = read(`oras manifest fetch --descriptor $image_ref`, String)
    payload = JSON3.read(raw)
    digest = get(payload, :digest, "")
    isempty(digest) && error("oras did not return an image digest")
    return string(digest)
end

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

function main()
    # --- Argument parsing ---
    image        = ""
    out_dir      = ""
    image_digest = ""
    log_id       = "verified-container-log-mvp"
    log_url      = "https://logs.mvp.local"
    log_operator = "Cerro Torre MVP Log"
    store_id     = "cerro-torre-mvp"
    signer_owner = "cerro-torre-mvp"
    attach       = false

    i = 1
    while i <= length(ARGS)
        arg = ARGS[i]
        if arg == "--image"
            i += 1; image = ARGS[i]
        elseif arg == "--out-dir"
            i += 1; out_dir = ARGS[i]
        elseif arg == "--image-digest"
            i += 1; image_digest = ARGS[i]
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
        elseif arg == "--attach"
            attach = true
        else
            error("Unknown argument: $arg")
        end
        i += 1
    end

    isempty(image)   && error("--image is required")
    isempty(out_dir) && error("--out-dir is required")

    mkpath(out_dir)
    keys_dir = joinpath(out_dir, "keys")
    mkpath(keys_dir)

    # Resolve digest if not explicitly provided
    if isempty(image_digest)
        image_digest = get_digest(image)
    end

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
        --image-name   $image
        --image-digest $image_digest
        --signer-key   $(joinpath(keys_dir, "signer.key"))
        --signer-pub   $(joinpath(keys_dir, "signer.pub"))
        --log-key      $(joinpath(keys_dir, "log.key"))
        --log-id       $log_id
        --out          $(joinpath(out_dir, "bundle.json"))`))

    if attach
        run(pipeline(`tools/mvp/publish_bundle.sh
            $image
            $(joinpath(out_dir, "bundle.json"))
            application/vnd.verified-container.bundle+json`))
    end

    # Write summary
    summary = Dict(
        "image"      => image,
        "digest"     => image_digest,
        "bundle"     => joinpath(out_dir, "bundle.json"),
        "trustStore" => joinpath(out_dir, "trust-store.json"),
        "keysDir"    => keys_dir,
        "attached"   => attach,
    )
    open(joinpath(out_dir, "summary.json"), "w") do io
        JSON3.pretty(io, summary)
    end
end

# Run when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
