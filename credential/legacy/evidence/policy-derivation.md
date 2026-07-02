# Policy-ID derivation proof — EchoCert live policy is `documint`, not `echocert.ak`

> Captured during the 2026-07 investigation. Everything here is **independently
> reproducible** from the files in this repo + a Blockfrost query. No trust required.

## What this proves

The minting policy that governs every on-chain "EchoCert" certificate —
`32fd4d60…` on mainnet and `4df6ed7f…` on preprod — is derived from **documint's
compiled bytes**, applied with `[treasuryHash, issuerHash]`. The real
`echocert.ak` source (now in `../echocert.ak`) was **never deployed** on either
network.

Root cause: the app's `loadValidator` (`credential/frontend/src/lib/mint.js`)
does `fetch("/plutus.json")`, which serves `credential/frontend/public/plutus.json`.
In that file the `echocert.echocert.mint` entry contains **documint's bytes**
(its `compiledCode` is byte-identical to the `documint.documint.mint` entry).

## Raw (un-parameterised) validator hashes — from `plutus.json`

| entry | source `credential/plutus.json` | frontend `public/plutus.json` |
| --- | --- | --- |
| `documint.documint.mint` | `ee1b606e…` (656 B, header `59028d`) | `ee1b606e…` (same) |
| `echocert.echocert.mint` | `0053a3d5…` (655 B, header `59028c`) — **real echocert** | `ee1b606e…` (656 B, header `59028d`) — **= documint bytes** |

Method (validated against the two known hashes above): a Plutus V3 script hash is
`blake2b_224(0x03 ‖ compiledCode_bytes)`. This reproduces both `ee1b606e…` and
`0053a3d5…` exactly, confirming the method.

## Parameterised derivation — matches the DEPLOYED policies

`loadValidator` applies `[treasuryHash, issuerHash]` via MeshJS
`applyParamsToScript(code, [t, i], "Mesh")`, strips one CBOR layer, then hashes
`blake2b_224(0x03 ‖ singleCBOR)`. On both networks the treasury and issuer were
the same wallet, so `treasuryHash == issuerHash`.

### preprod (`NEXT_PUBLIC_POLICY_ID = 4df6ed7f…`)

- param (treasury == issuer payment cred): `fae5b57155a6ec611dd2513efbe8f8bf4d0d7221606f53563417fc3f`
- from **source echocert.ak** → `beacb0e50ccb14c2eb0ea2964e065a506880eb33390b63d4ec7c7764`  ✗ (not deployed)
- from **frontend echocert (= documint bytes)** → `4df6ed7ffa2b134a2599cf48275f1bb3f0166277b1e99cc2f5ac8198`  ✓ **matches deployed**

### mainnet (`32fd4d60…`) — verified against the ACTUAL on-chain script

Fetched the deployed script from Blockfrost by its hash
(`GET /scripts/32fd4d60…/cbor`, saved in `mainnet-deployed-script.json`):

- deployed script = **725 bytes**; `blake2b_224(0x03 ‖ deployed) == 32fd4d60…`  ✓
  (self-consistency: the fetched bytes really are this policy's script)
- deployed length matches **documint base** (725) not echocert base (724)
- byte-diff vs documint base (zero-param) = **only 56 bytes, in two contiguous
  28-byte regions** (offsets 661–688 and 695–722) = the two applied params;
  everything else identical
- byte-diff vs echocert base = length mismatch → not comparable → not this base
- extracted the two real params from the deployed script (both =
  `2fbe7f5785f672d5ca91e92b97aec4d762956a3f5221cf058fc1dae4`), re-applied them to
  the documint base → **byte-perfect reproduction of the deployed script**, and
  its hash = `32fd4d60…`  ✓

On-chain reality (`mainnet-assets.json`): **3 assets** minted under `32fd4d60…`.

## Consequence

- The certs are still trustworthy: documint's `MintAnchor` predicate enforces the
  same guarantees as echocert's `IssueCert` — `expect signed_by_issuer`, exactly
  one token named after the hash, a treasury payment. The only real differences:
  documint's on-chain treasury floor is **5 ADA** (echocert.ak had 1 ADA), and the
  redeemer/type names differ cosmetically (`doc_hash` vs `cert_hash`).
- **Do NOT "fix" `credential/frontend/public/plutus.json`.** Its `echocert` entry
  is intentionally documint bytes — that is what derives the live policy. Syncing
  it to the real echocert source would change the policy id to the `beacb0e5…`
  family and orphan every existing certificate.
