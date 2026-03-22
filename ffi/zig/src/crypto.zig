// SPDX-License-Identifier: PMPL-1.0-or-later
// Stapeln Crypto FFI — Real cryptographic operations via Zig stdlib.
//
// Provides C-ABI exports for:
//   - SHA-256 hashing (crypto_sha256)
//   - Ed25519 signature verification (crypto_ed25519_verify)
//   - Ed25519 signing (crypto_ed25519_sign)
//   - Ed25519 keypair generation (crypto_ed25519_keypair)
//
// These replace the fake stubs in CryptoProofs.idr that returned
// hardcoded zeros (SHA-256) and unconditional True (Ed25519 verify).
//
// All functions are pure (deterministic, no side effects) and safe
// to call from Idris2 %foreign declarations.

const std = @import("std");
const crypto = std.crypto;
const Ed25519 = crypto.sign.Ed25519;
const Sha256 = crypto.hash.sha2.Sha256;

// ---------------------------------------------------------------------------
// SHA-256
// ---------------------------------------------------------------------------

/// Compute SHA-256 hash of input data.
///
/// Parameters:
///   input_ptr: pointer to input bytes (may be null if input_len == 0)
///   input_len: length of input data in bytes
///   output_ptr: pointer to 32-byte output buffer (must not be null)
///
/// Returns: 0 on success, 1 on null output pointer
export fn stapeln_crypto_sha256(
    input_ptr: ?[*]const u8,
    input_len: usize,
    output_ptr: ?[*]u8,
) c_int {
    const out = output_ptr orelse return 1;
    const out_buf: *[32]u8 = out[0..32];

    if (input_ptr) |inp| {
        if (input_len > 0) {
            Sha256.hash(inp[0..input_len], out_buf, .{});
            return 0;
        }
    }

    // Hash of empty input
    Sha256.hash("", out_buf, .{});
    return 0;
}

// ---------------------------------------------------------------------------
// Ed25519 Signature Verification
// ---------------------------------------------------------------------------

/// Verify an Ed25519 signature.
///
/// Parameters:
///   msg_ptr:  pointer to message bytes
///   msg_len:  length of message
///   sig_ptr:  pointer to 64-byte signature
///   pk_ptr:   pointer to 32-byte public key
///
/// Returns: 1 if signature is valid, 0 if invalid, -1 on error
export fn stapeln_crypto_ed25519_verify(
    msg_ptr: ?[*]const u8,
    msg_len: usize,
    sig_ptr: ?[*]const u8,
    pk_ptr: ?[*]const u8,
) c_int {
    const sig_bytes = (sig_ptr orelse return -1)[0..64];
    const pk_bytes = (pk_ptr orelse return -1)[0..32];

    const sig = Ed25519.Signature.fromBytes(sig_bytes.*);
    const pk = Ed25519.PublicKey.fromBytes(pk_bytes.*) catch return -1;

    const msg = if (msg_ptr) |p|
        (if (msg_len > 0) p[0..msg_len] else "")
    else
        "";

    sig.verify(msg, pk) catch return 0;
    return 1;
}

// ---------------------------------------------------------------------------
// Ed25519 Signing (for testing and key generation)
// ---------------------------------------------------------------------------

/// Generate an Ed25519 keypair from a 32-byte seed.
///
/// Parameters:
///   seed_ptr:    pointer to 32-byte seed (if null, generates random)
///   pk_out_ptr:  pointer to 32-byte output for public key
///   sk_out_ptr:  pointer to 64-byte output for secret key
///
/// Returns: 0 on success, -1 on error
export fn stapeln_crypto_ed25519_keypair(
    seed_ptr: ?[*]const u8,
    pk_out_ptr: ?[*]u8,
    sk_out_ptr: ?[*]u8,
) c_int {
    const pk_out = pk_out_ptr orelse return -1;
    const sk_out = sk_out_ptr orelse return -1;

    if (seed_ptr) |seed_p| {
        const seed: [32]u8 = seed_p[0..32].*;
        const kp = Ed25519.KeyPair.generateDeterministic(seed) catch return -1;
        @memcpy(pk_out[0..32], &kp.public_key.bytes);
        @memcpy(sk_out[0..64], &kp.secret_key.bytes);
    } else {
        const kp = Ed25519.KeyPair.generate();
        @memcpy(pk_out[0..32], &kp.public_key.bytes);
        @memcpy(sk_out[0..64], &kp.secret_key.bytes);
    }
    return 0;
}

/// Sign a message with an Ed25519 secret key.
///
/// Parameters:
///   msg_ptr:    pointer to message bytes
///   msg_len:    length of message
///   sk_ptr:     pointer to 64-byte secret key
///   sig_out_ptr: pointer to 64-byte output for signature
///
/// Returns: 0 on success, -1 on error
export fn stapeln_crypto_ed25519_sign(
    msg_ptr: ?[*]const u8,
    msg_len: usize,
    sk_ptr: ?[*]const u8,
    sig_out_ptr: ?[*]u8,
) c_int {
    const sk_bytes = (sk_ptr orelse return -1)[0..64];
    const sig_out = sig_out_ptr orelse return -1;

    const sk = Ed25519.SecretKey.fromBytes(sk_bytes.*) catch return -1;
    const kp = Ed25519.KeyPair.fromSecretKey(sk) catch return -1;

    const msg = if (msg_ptr) |p|
        (if (msg_len > 0) p[0..msg_len] else "")
    else
        "";

    const sig = kp.sign(msg, null) catch return -1;
    @memcpy(sig_out[0..64], &sig.toBytes());
    return 0;
}

// ---------------------------------------------------------------------------
// Tests — verify the crypto actually works
// ---------------------------------------------------------------------------

test "sha256 of empty string" {
    var hash: [32]u8 = undefined;
    const rc = stapeln_crypto_sha256(null, 0, &hash);
    try std.testing.expectEqual(@as(c_int, 0), rc);

    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    const expected = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "sha256 of 'hello'" {
    const msg = "hello";
    var hash: [32]u8 = undefined;
    const rc = stapeln_crypto_sha256(msg.ptr, msg.len, &hash);
    try std.testing.expectEqual(@as(c_int, 0), rc);

    // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    const expected = [_]u8{
        0x2c, 0xf2, 0x4d, 0xba, 0x5f, 0xb0, 0xa3, 0x0e,
        0x26, 0xe8, 0x3b, 0x2a, 0xc5, 0xb9, 0xe2, 0x9e,
        0x1b, 0x16, 0x1e, 0x5c, 0x1f, 0xa7, 0x42, 0x5e,
        0x73, 0x04, 0x33, 0x62, 0x93, 0x8b, 0x98, 0x24,
    };
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}

test "sha256 deterministic" {
    const msg = "determinism test input";
    var hash1: [32]u8 = undefined;
    var hash2: [32]u8 = undefined;
    _ = stapeln_crypto_sha256(msg.ptr, msg.len, &hash1);
    _ = stapeln_crypto_sha256(msg.ptr, msg.len, &hash2);
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "sha256 different inputs give different hashes" {
    const msg1 = "input one";
    const msg2 = "input two";
    var hash1: [32]u8 = undefined;
    var hash2: [32]u8 = undefined;
    _ = stapeln_crypto_sha256(msg1.ptr, msg1.len, &hash1);
    _ = stapeln_crypto_sha256(msg2.ptr, msg2.len, &hash2);
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "ed25519 sign and verify roundtrip" {
    // Generate keypair from fixed seed for reproducibility
    const seed = [_]u8{0x42} ** 32;
    var pk: [32]u8 = undefined;
    var sk: [64]u8 = undefined;
    const kp_rc = stapeln_crypto_ed25519_keypair(&seed, &pk, &sk);
    try std.testing.expectEqual(@as(c_int, 0), kp_rc);

    // Sign a message
    const msg = "test message for signing";
    var sig: [64]u8 = undefined;
    const sign_rc = stapeln_crypto_ed25519_sign(msg.ptr, msg.len, &sk, &sig);
    try std.testing.expectEqual(@as(c_int, 0), sign_rc);

    // Verify — should succeed
    const verify_rc = stapeln_crypto_ed25519_verify(msg.ptr, msg.len, &sig, &pk);
    try std.testing.expectEqual(@as(c_int, 1), verify_rc);
}

test "ed25519 verify rejects wrong message" {
    const seed = [_]u8{0x42} ** 32;
    var pk: [32]u8 = undefined;
    var sk: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_keypair(&seed, &pk, &sk);

    const msg = "original message";
    var sig: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_sign(msg.ptr, msg.len, &sk, &sig);

    // Verify with different message — should fail
    const wrong_msg = "tampered message";
    const verify_rc = stapeln_crypto_ed25519_verify(wrong_msg.ptr, wrong_msg.len, &sig, &pk);
    try std.testing.expectEqual(@as(c_int, 0), verify_rc);
}

test "ed25519 verify rejects wrong key" {
    const seed1 = [_]u8{0x42} ** 32;
    const seed2 = [_]u8{0x43} ** 32;
    var pk1: [32]u8 = undefined;
    var sk1: [64]u8 = undefined;
    var pk2: [32]u8 = undefined;
    var sk2: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_keypair(&seed1, &pk1, &sk1);
    _ = stapeln_crypto_ed25519_keypair(&seed2, &pk2, &sk2);

    const msg = "signed by key 1";
    var sig: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_sign(msg.ptr, msg.len, &sk1, &sig);

    // Verify with wrong public key — should fail
    const verify_rc = stapeln_crypto_ed25519_verify(msg.ptr, msg.len, &sig, &pk2);
    try std.testing.expectEqual(@as(c_int, 0), verify_rc);
}

test "ed25519 verify rejects tampered signature" {
    const seed = [_]u8{0x42} ** 32;
    var pk: [32]u8 = undefined;
    var sk: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_keypair(&seed, &pk, &sk);

    const msg = "important data";
    var sig: [64]u8 = undefined;
    _ = stapeln_crypto_ed25519_sign(msg.ptr, msg.len, &sk, &sig);

    // Tamper with signature
    sig[0] ^= 0xFF;

    const verify_rc = stapeln_crypto_ed25519_verify(msg.ptr, msg.len, &sig, &pk);
    try std.testing.expectEqual(@as(c_int, 0), verify_rc);
}

test "ed25519 null pointer handling" {
    const rc1 = stapeln_crypto_ed25519_verify(null, 0, null, null);
    try std.testing.expectEqual(@as(c_int, -1), rc1);

    const rc2 = stapeln_crypto_ed25519_sign(null, 0, null, null);
    try std.testing.expectEqual(@as(c_int, -1), rc2);

    const rc3 = stapeln_crypto_ed25519_keypair(null, null, null);
    try std.testing.expectEqual(@as(c_int, -1), rc3);
}

test "sha256 null output pointer" {
    const rc = stapeln_crypto_sha256(null, 0, null);
    try std.testing.expectEqual(@as(c_int, 1), rc);
}
