-- SPDX-License-Identifier: MPL-2.0
-- Cryptographic spec stubs for Idris2 proof layer.
--
-- The actual cryptographic runtime (SHA-256, Ed25519) lives entirely in
-- ffi/zig/src/crypto.zig, which exports a C ABI consumed directly by the
-- application layer. This module provides only the type signatures that
-- the proof modules (CryptoProofs.idr, Theorems.idr) reference.
--
-- Per the estate ABI/FFI standard: Idris2 = proof layer, Zig = runtime layer.
-- These stubs are partial (IO operations depend on runtime), and that is
-- by design — the proofs themselves are total.

module CryptoFFI

import Data.Vect

%default total

||| SHA-256 spec stub — runtime implemented in ffi/zig/src/crypto.zig.
||| The 32-byte output type is enforced at the type level; correctness
||| of the hash algorithm is assumed here and proven in CryptoProofs.idr.
export partial
sha256IO : List Bits8 -> IO (Vect 32 Bits8)
sha256IO _ = idris_crash "sha256IO: link ffi/zig/src/crypto.zig to use at runtime"

||| Ed25519 verify spec stub — runtime in ffi/zig/src/crypto.zig.
export partial
verifyEd25519IO : (pk : Vect 32 Bits8) -> (msg : List Bits8)
               -> (sig : Vect 64 Bits8) -> IO Bool
verifyEd25519IO _ _ _ = idris_crash "verifyEd25519IO: link ffi/zig/src/crypto.zig"

||| Ed25519 keypair generation stub — runtime in ffi/zig/src/crypto.zig.
export partial
ed25519KeypairIO : (seed : Vect 32 Bits8) -> IO (Vect 32 Bits8, Vect 64 Bits8)
ed25519KeypairIO _ = idris_crash "ed25519KeypairIO: link ffi/zig/src/crypto.zig"

||| Ed25519 sign stub — runtime in ffi/zig/src/crypto.zig.
export partial
ed25519SignIO : (sk : Vect 64 Bits8) -> (msg : List Bits8) -> IO (Vect 64 Bits8)
ed25519SignIO _ _ = idris_crash "ed25519SignIO: link ffi/zig/src/crypto.zig"

||| FFI availability check — always false in proof-only build.
||| Returns True only when the libstapeln_crypto shared object is linked.
export partial
checkCryptoAvailable : IO Bool
checkCryptoAvailable = pure False
