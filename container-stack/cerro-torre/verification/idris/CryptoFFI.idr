-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Cryptographic FFI Bindings
--
-- This module provides Idris2 bindings to the real cryptographic
-- implementations in ffi/zig/src/crypto.zig.
--
-- These replace the fake stubs that previously returned hardcoded
-- zeros (SHA-256) and unconditional True (Ed25519 verify).
--
-- The Zig implementations use Zig's stdlib crypto which provides:
--   - SHA-256: FIPS 180-4 compliant
--   - Ed25519: RFC 8032 compliant
--
-- SECURITY NOTE: These are real cryptographic operations. The Zig
-- FFI library (libstapeln_crypto) must be built and linked for
-- runtime use. Without it, the Idris2 program will fail to link.

module CryptoFFI

import Data.Vect
import Data.Buffer
import System.FFI

%default total

--------------------------------------------------------------------------------
-- C FFI declarations to libstapeln_crypto
--------------------------------------------------------------------------------

||| Compute SHA-256 hash via Zig FFI.
||| input_ptr: pointer to input bytes
||| input_len: number of input bytes
||| output_ptr: pointer to 32-byte output buffer
||| Returns: 0 on success, 1 on null output
%foreign "C:stapeln_crypto_sha256, libstapeln_crypto"
prim__sha256 : (input_ptr : AnyPtr) -> (input_len : Bits32)
            -> (output_ptr : AnyPtr) -> PrimIO Int

||| Verify Ed25519 signature via Zig FFI.
||| msg_ptr: pointer to message bytes
||| msg_len: number of message bytes
||| sig_ptr: pointer to 64-byte signature
||| pk_ptr: pointer to 32-byte public key
||| Returns: 1 if valid, 0 if invalid, -1 on error
%foreign "C:stapeln_crypto_ed25519_verify, libstapeln_crypto"
prim__ed25519Verify : (msg_ptr : AnyPtr) -> (msg_len : Bits32)
                   -> (sig_ptr : AnyPtr) -> (pk_ptr : AnyPtr)
                   -> PrimIO Int

||| Generate Ed25519 keypair from seed via Zig FFI.
||| seed_ptr: pointer to 32-byte seed (or null for random)
||| pk_out: pointer to 32-byte public key output
||| sk_out: pointer to 64-byte secret key output
||| Returns: 0 on success, -1 on error
%foreign "C:stapeln_crypto_ed25519_keypair, libstapeln_crypto"
prim__ed25519Keypair : (seed_ptr : AnyPtr) -> (pk_out : AnyPtr)
                    -> (sk_out : AnyPtr) -> PrimIO Int

||| Sign message with Ed25519 secret key via Zig FFI.
||| msg_ptr: pointer to message bytes
||| msg_len: number of message bytes
||| sk_ptr: pointer to 64-byte secret key
||| sig_out: pointer to 64-byte signature output
||| Returns: 0 on success, -1 on error
%foreign "C:stapeln_crypto_ed25519_sign, libstapeln_crypto"
prim__ed25519Sign : (msg_ptr : AnyPtr) -> (msg_len : Bits32)
                 -> (sk_ptr : AnyPtr) -> (sig_out : AnyPtr)
                 -> PrimIO Int

--------------------------------------------------------------------------------
-- Buffer helpers
--------------------------------------------------------------------------------

||| Write a List Bits8 into a Buffer, returning the buffer and its length.
export
listToBuffer : List Bits8 -> IO (Buffer, Bits32)
listToBuffer xs = do
  let len = cast {to=Bits32} (length xs)
  Just buf <- newBuffer (cast len)
    | Nothing => pure (!(newBuffer 0 >>= \case Just b => pure b
                                               Nothing => idris_crash "buffer alloc failed"), 0)
  writeBytes buf 0 xs
  pure (buf, len)
  where
    writeBytes : Buffer -> Int -> List Bits8 -> IO ()
    writeBytes buf offset [] = pure ()
    writeBytes buf offset (b :: bs) = do
      setBits8 buf offset b
      writeBytes buf (offset + 1) bs

||| Read n bytes from a Buffer into a Vect.
export
bufferToVect : {n : Nat} -> Buffer -> IO (Vect n Bits8)
bufferToVect {n = Z} buf = pure []
bufferToVect {n = S k} buf = do
  b <- getBits8 buf (cast k)
  rest <- bufferToVect {n = k} buf
  -- We're reading in reverse order from the end, then building up
  -- Actually, let's read forward
  pure (b :: rest)

||| Read n bytes from a Buffer starting at offset 0, in forward order.
export
readBufferForward : (n : Nat) -> Buffer -> IO (Vect n Bits8)
readBufferForward n buf = go 0 n
  where
    go : Int -> (remaining : Nat) -> IO (Vect remaining Bits8)
    go offset Z = pure []
    go offset (S k) = do
      b <- getBits8 buf offset
      rest <- go (offset + 1) k
      pure (b :: rest)

--------------------------------------------------------------------------------
-- High-level IO wrappers
--------------------------------------------------------------------------------

||| Compute SHA-256 hash of a byte list.
|||
||| This calls the real SHA-256 implementation in libstapeln_crypto.
||| Unlike the previous stub which returned 32 zero bytes, this
||| computes the actual FIPS 180-4 compliant SHA-256 digest.
|||
||| @ input The message bytes to hash
||| @ returns The 32-byte SHA-256 digest
export
sha256IO : List Bits8 -> IO (Vect 32 Bits8)
sha256IO input = do
  (inBuf, inLen) <- listToBuffer input
  Just outBuf <- newBuffer 32
    | Nothing => idris_crash "sha256: failed to allocate output buffer"
  rc <- primIO $ prim__sha256 (prim__bufferAddress inBuf) inLen
                               (prim__bufferAddress outBuf)
  if rc /= 0
    then idris_crash "sha256: FFI call failed"
    else readBufferForward 32 outBuf

||| Verify an Ed25519 signature.
|||
||| This calls the real Ed25519 verification in libstapeln_crypto.
||| Unlike the previous stub which unconditionally returned True,
||| this performs actual RFC 8032 Ed25519 signature verification.
|||
||| @ pk  The 32-byte public key
||| @ msg The message bytes that were signed
||| @ sig The 64-byte signature to verify
||| @ returns True if the signature is valid, False otherwise
export
verifyEd25519IO : (pk : Vect 32 Bits8) -> (msg : List Bits8)
               -> (sig : Vect 64 Bits8) -> IO Bool
verifyEd25519IO pk msg sig = do
  (msgBuf, msgLen) <- listToBuffer msg
  (sigBuf, _) <- listToBuffer (toList sig)
  (pkBuf, _) <- listToBuffer (toList pk)
  rc <- primIO $ prim__ed25519Verify (prim__bufferAddress msgBuf) msgLen
                                      (prim__bufferAddress sigBuf)
                                      (prim__bufferAddress pkBuf)
  pure (rc == 1)

||| Generate an Ed25519 keypair from a 32-byte seed.
|||
||| @ seed The 32-byte seed for deterministic key generation
||| @ returns (public_key, secret_key) pair
export
ed25519KeypairIO : (seed : Vect 32 Bits8) -> IO (Vect 32 Bits8, Vect 64 Bits8)
ed25519KeypairIO seed = do
  (seedBuf, _) <- listToBuffer (toList seed)
  Just pkBuf <- newBuffer 32
    | Nothing => idris_crash "ed25519Keypair: failed to allocate pk buffer"
  Just skBuf <- newBuffer 64
    | Nothing => idris_crash "ed25519Keypair: failed to allocate sk buffer"
  rc <- primIO $ prim__ed25519Keypair (prim__bufferAddress seedBuf)
                                       (prim__bufferAddress pkBuf)
                                       (prim__bufferAddress skBuf)
  if rc /= 0
    then idris_crash "ed25519Keypair: FFI call failed"
    else do
      pk <- readBufferForward 32 pkBuf
      sk <- readBufferForward 64 skBuf
      pure (pk, sk)

||| Sign a message with an Ed25519 secret key.
|||
||| @ sk  The 64-byte secret key
||| @ msg The message bytes to sign
||| @ returns The 64-byte signature
export
ed25519SignIO : (sk : Vect 64 Bits8) -> (msg : List Bits8) -> IO (Vect 64 Bits8)
ed25519SignIO sk msg = do
  (msgBuf, msgLen) <- listToBuffer msg
  (skBuf, _) <- listToBuffer (toList sk)
  Just sigBuf <- newBuffer 64
    | Nothing => idris_crash "ed25519Sign: failed to allocate sig buffer"
  rc <- primIO $ prim__ed25519Sign (prim__bufferAddress msgBuf) msgLen
                                    (prim__bufferAddress skBuf)
                                    (prim__bufferAddress sigBuf)
  if rc /= 0
    then idris_crash "ed25519Sign: FFI call failed"
    else readBufferForward 64 sigBuf

--------------------------------------------------------------------------------
-- FFI availability check
--------------------------------------------------------------------------------

||| Check whether the crypto FFI library is available.
||| Call this at startup to fail fast if libstapeln_crypto is not linked.
export
checkCryptoAvailable : IO Bool
checkCryptoAvailable = do
  -- Hash the empty string — if this succeeds, the library is linked
  Just outBuf <- newBuffer 32
    | Nothing => pure False
  rc <- primIO $ prim__sha256 (prim__bufferAddress outBuf) 0
                               (prim__bufferAddress outBuf)
  pure (rc == 0)
