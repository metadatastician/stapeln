#!/usr/bin/env julia
# SPDX-License-Identifier: PMPL-1.0-or-later
#
# ct_mvp.jl — Cerro Torre MVP bundle helper.
# Provides three sub-commands:
#   keygen      — Generate Ed25519 signer and log key pairs via OpenSSL.
#   trust-store — Create a trust-store JSON file.
#   bundle      — Create an attestation bundle (SLSA provenance + SBOM).

using JSON3
using SHA
using Base64
using Dates

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PAYLOAD_TYPE = "application/vnd.in-toto+json"

# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

"""
    canonical_json_bytes(value)::Vector{UInt8}

Produce a deterministic (sorted-key, compact) JSON encoding of `value`.
"""
function canonical_json_bytes(value)::Vector{UInt8}
    # JSON3.write with sorting isn't built-in, so we serialise via a
    # recursive sort then compact-write approach.
    return Vector{UInt8}(JSON3.write(sort_keys_recursive(value)))
end

"""
    sort_keys_recursive(v)

Recursively sort dictionary keys so that canonical_json_bytes is
deterministic.
"""
function sort_keys_recursive(v::AbstractDict)
    sorted = sort(collect(v); by=first)
    return OrderedPairList([(k, sort_keys_recursive(val)) for (k, val) in sorted])
end
sort_keys_recursive(v::AbstractVector) = [sort_keys_recursive(x) for x in v]
sort_keys_recursive(v) = v

"""Wrapper so JSON3 serialises pairs in insertion order."""
struct OrderedPairList
    pairs::Vector{Tuple{Any,Any}}
end
function JSON3.write(io::IO, opl::OrderedPairList)
    print(io, '{')
    for (i, (k, v)) in enumerate(opl.pairs)
        i > 1 && print(io, ',')
        JSON3.write(io, string(k))
        print(io, ':')
        JSON3.write(io, v)
    end
    print(io, '}')
end
function JSON3.write(opl::OrderedPairList)
    buf = IOBuffer()
    JSON3.write(buf, opl)
    return String(take!(buf))
end

"""Return lowercase hex SHA-256 of raw bytes."""
sha256_hex(data::Vector{UInt8})::String = bytes2hex(sha256(data))

# ---------------------------------------------------------------------------
# OpenSSL wrappers
# ---------------------------------------------------------------------------

"""Ensure `openssl` is available on PATH."""
function require_openssl()
    try
        run(pipeline(`openssl version`; stdout=devnull))
    catch
        error("openssl not found; required for MVP signing")
    end
end

"""Run an openssl command, optionally piping `input_bytes` to stdin.
   Returns captured stdout as a `Vector{UInt8}`."""
function run_openssl(args::Vector{String};
                     input_bytes::Union{Nothing,Vector{UInt8}}=nothing)::Vector{UInt8}
    cmd = `openssl $args`
    if isnothing(input_bytes)
        return read(cmd)
    else
        buf = IOBuffer(input_bytes)
        return read(pipeline(cmd; stdin=buf))
    end
end

# ---------------------------------------------------------------------------
# Cryptographic helpers
# ---------------------------------------------------------------------------

"""DSSE Pre-Authentication Encoding."""
function dsse_pae(payload_type::String, payload_b64::String)::Vector{UInt8}
    pt = Vector{UInt8}(payload_type)
    pb = Vector{UInt8}(payload_b64)
    enc(part) = Vector{UInt8}(string(length(part))) * UInt8[0x20] * part
    return Vector{UInt8}("DSSEv1 ") * enc(pt) * UInt8[0x20] * enc(pb)
end

"""Sign `message_bytes` with Ed25519 private key at `priv_key_path`."""
function ed25519_sign(priv_key_path::String,
                      message_bytes::Vector{UInt8})::Vector{UInt8}
    return run_openssl(["pkeyutl", "-sign", "-inkey", priv_key_path, "-rawin"];
                       input_bytes=message_bytes)
end

"""Read the DER encoding of a public key."""
function public_key_der(pub_key_path::String)::Vector{UInt8}
    return run_openssl(["pkey", "-pubin", "-in", pub_key_path, "-outform", "DER"])
end

"""Compute a key-id from the SHA-256 of the public key's DER encoding."""
function key_id_from_pub(pub_key_path::String)::String
    return "sha256:" * sha256_hex(public_key_der(pub_key_path))
end

"""Generate an Ed25519 key pair via OpenSSL.  Returns (priv_path, pub_path)."""
function generate_keypair(out_dir::String, prefix::String)::Tuple{String,String}
    priv_path = joinpath(out_dir, "$prefix.key")
    pub_path  = joinpath(out_dir, "$prefix.pub")
    run_openssl(["genpkey", "-algorithm", "ED25519", "-out", priv_path])
    run_openssl(["pkey", "-in", priv_path, "-pubout", "-out", pub_path])
    return (priv_path, pub_path)
end

# ---------------------------------------------------------------------------
# In-toto / DSSE helpers
# ---------------------------------------------------------------------------

"""Build an in-toto Statement v1."""
function build_statement(subject_name::String, subject_digest::String,
                         predicate_type::String, predicate::Dict)::Dict
    return Dict(
        "_type"         => "https://in-toto.io/Statement/v1",
        "subject"       => [Dict(
            "name"   => subject_name,
            "digest" => Dict("sha256" => replace(subject_digest, "sha256:" => "")),
        )],
        "predicateType" => predicate_type,
        "predicate"     => predicate,
    )
end

"""Create a DSSE envelope around a statement, signed with `signer_priv_key`."""
function dsse_envelope(statement::Dict, signer_key_id::String,
                       signer_priv_key::String)::Dict
    payload = base64encode(canonical_json_bytes(statement))
    pae = dsse_pae(PAYLOAD_TYPE, payload)
    signature = ed25519_sign(signer_priv_key, pae)
    return Dict(
        "payloadType" => PAYLOAD_TYPE,
        "payload"     => payload,
        "signatures"  => [Dict(
            "keyid" => signer_key_id,
            "sig"   => base64encode(signature),
        )],
    )
end

"""Create a transparency-log entry for an attestation."""
function log_entry_for_attestation(attestation_digest::String,
                                   subject_digest::String,
                                   predicate_type::String,
                                   log_key_path::String,
                                   log_id::String)::Dict
    timestamp = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS") * "Z"
    entry = Dict(
        "version"   => 1,
        "timestamp" => timestamp,
        "entryType" => "attestation",
        "body"      => Dict(
            "attestationDigest" => attestation_digest,
            "subjectDigest"     => subject_digest,
            "predicateType"     => predicate_type,
        ),
    )
    entry_bytes = canonical_json_bytes(entry)
    leaf_hash = sha256_hex(vcat(UInt8[0x00], entry_bytes))
    signed_entry_timestamp = ed25519_sign(log_key_path, entry_bytes)
    return Dict(
        "logId"          => log_id,
        "logIndex"       => 0,
        "integratedTime" => timestamp,
        "inclusionProof" => Dict(
            "logIndex" => 0,
            "rootHash" => leaf_hash,
            "treeSize" => 1,
            "hashes"   => String[],
        ),
        "signedEntryTimestamp" => base64encode(signed_entry_timestamp),
    )
end

# ---------------------------------------------------------------------------
# Sub-command implementations
# ---------------------------------------------------------------------------

function command_keygen(args::Dict{String,String})
    require_openssl()
    out_dir       = args["out-dir"]
    signer_prefix = get(args, "signer-prefix", "signer")
    log_prefix    = get(args, "log-prefix",    "log")
    mkpath(out_dir)

    signer_priv, signer_pub = generate_keypair(out_dir, signer_prefix)
    log_priv, log_pub       = generate_keypair(out_dir, log_prefix)

    output = Dict(
        "signer" => Dict(
            "privateKey" => signer_priv,
            "publicKey"  => signer_pub,
            "keyId"      => key_id_from_pub(signer_pub),
        ),
        "log" => Dict(
            "privateKey" => log_priv,
            "publicKey"  => log_pub,
            "keyId"      => key_id_from_pub(log_pub),
        ),
    )
    println(JSON3.pretty(output))
end

function command_trust_store(args::Dict{String,String})
    signer_key_id = key_id_from_pub(args["signer-pub"])
    log_key_id    = key_id_from_pub(args["log-pub"])

    trust_store = Dict(
        "\$schema" => "https://verified-container.org/schema/trust-store-v1.json",
        "version"  => 1,
        "id"       => get(args, "store-id", "cerro-torre-mvp"),
        "updated"  => Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS") * "Z",
        "keys" => Dict(
            "builders" => [Dict(
                "id"        => signer_key_id,
                "algorithm" => "ed25519",
                "publicKey" => base64encode(public_key_der(args["signer-pub"])),
                "validFrom" => get(args, "valid-from", "2024-01-01T00:00:00Z"),
                "metadata"  => Dict("owner" => get(args, "signer-owner", "cerro-torre-mvp")),
            )],
        ),
        "thresholds" => Dict(),
        "logs" => Dict(
            args["log-id"] => Dict(
                "operator"  => get(args, "log-operator", "Cerro Torre MVP Log"),
                "publicKey" => base64encode(public_key_der(args["log-pub"])),
                "url"       => args["log-url"],
                "algorithm" => "ed25519",
            ),
        ),
        "metadata" => Dict(
            "mvp"      => true,
            "logKeyId" => log_key_id,
        ),
    )
    open(args["out"], "w") do io
        JSON3.pretty(io, trust_store)
    end
end

function command_bundle(args::Dict{String,String})
    require_openssl()
    signer_key_id = key_id_from_pub(args["signer-pub"])

    slsa_statement = build_statement(
        args["image-name"], args["image-digest"],
        "https://slsa.dev/provenance/v1",
        Dict(
            "buildType"  => "https://cerro-torre.org/build/mvp",
            "builder"    => Dict("id" => "cerro-torre-mvp"),
            "invocation" => Dict(),
        ),
    )
    sbom_statement = build_statement(
        args["image-name"], args["image-digest"],
        "https://spdx.dev/Document",
        Dict("spdxVersion" => "SPDX-2.3", "name" => "mvp-sbom"),
    )

    slsa_dsse = dsse_envelope(slsa_statement, signer_key_id, args["signer-key"])
    sbom_dsse = dsse_envelope(sbom_statement, signer_key_id, args["signer-key"])

    slsa_digest = "sha256:" * sha256_hex(canonical_json_bytes(slsa_dsse))
    sbom_digest = "sha256:" * sha256_hex(canonical_json_bytes(sbom_dsse))

    log_entries = [
        log_entry_for_attestation(
            slsa_digest, args["image-digest"],
            slsa_statement["predicateType"],
            args["log-key"], args["log-id"],
        ),
        log_entry_for_attestation(
            sbom_digest, args["image-digest"],
            sbom_statement["predicateType"],
            args["log-key"], args["log-id"],
        ),
    ]

    bundle = Dict(
        "mediaType"    => "application/vnd.verified-container.bundle+json",
        "version"      => "0.1.0",
        "attestations" => [slsa_dsse, sbom_dsse],
        "logEntries"   => log_entries,
    )
    open(args["out"], "w") do io
        JSON3.pretty(io, bundle)
    end
end

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------

"""Parse ARGS into (command, named_args_dict)."""
function parse_args()
    isempty(ARGS) && error("Usage: ct_mvp.jl <keygen|trust-store|bundle> [options]")
    command = ARGS[1]
    named = Dict{String,String}()
    i = 2
    while i <= length(ARGS)
        arg = ARGS[i]
        if startswith(arg, "--")
            key = arg[3:end]
            if i < length(ARGS) && !startswith(ARGS[i+1], "--")
                i += 1
                named[key] = ARGS[i]
            else
                named[key] = "true"
            end
        end
        i += 1
    end
    return (command, named)
end

function main()
    command, args = parse_args()
    if command == "keygen"
        command_keygen(args)
    elseif command == "trust-store"
        command_trust_store(args)
    elseif command == "bundle"
        command_bundle(args)
    else
        error("Unknown command: $command. Use keygen, trust-store, or bundle.")
    end
end

# Run when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
