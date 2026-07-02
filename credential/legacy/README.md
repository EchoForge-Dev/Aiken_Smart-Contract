# credential/legacy — the real `echocert.ak` source (UN-DEPLOYED)

This folder preserves the original `echocert.ak` minting validator and the
evidence proving it was **never the contract actually deployed** for EchoCert.

## TL;DR

EchoCert's live minting policy — `32fd4d6013971be1074d83dc9b4ae3f9512184f10bfad9d1b8e7a158`
on mainnet, `4df6ed7ffa2b134a2599cf48275f1bb3f0166277b1e99cc2f5ac8198` on preprod —
runs **`documint`'s** logic, not this `echocert.ak`. The decision (2026-07) was to
**keep documint as EchoCert's contract** rather than recompile/migrate, because
documint enforces the same trust guarantees (see `evidence/policy-derivation.md`).

`echocert.ak` is kept here for historical reference only. It is out of
`validators/` so `aiken build` no longer compiles it.

## Timeline (how it happened)

1. **First there was `documint`.** The minting validator was originally written and
   named `documint` (document anchoring: `MintAnchor`/`BurnAnchor`, `doc_hash`).
2. **`echocert.ak` was added later** as a distinct validator (`IssueCert`/`RevokeCert`,
   `cert_hash`; 1 ADA treasury floor vs documint's 5 ADA). Both were committed together,
   so `credential/plutus.json` contains **both** entries with **distinct** bytes
   (documint `ee1b606e…`, echocert `0053a3d5…`).
3. **Only the frontend copy's name was changed.** When wiring the frontend, the
   `documint` entry in `credential/frontend/public/plutus.json` was relabeled to
   `echocert.echocert.mint` — but its **bytes stayed documint's**. So the frontend's
   "echocert" entry is documint's compiledCode under echocert's title.
4. **documint was deployed (under the EchoCert name).** Because `loadValidator` does
   `fetch("/plutus.json")` → the frontend copy → applies `[treasury, issuer]` params,
   every "EchoCert" NFT minted on preprod and mainnet is governed by **documint**.
5. **2026-07 — located.** A byte-level audit + on-chain cross-verification (mainnet
   asset query + deployed script fetched by hash + parameterised policy-id derivation)
   proved the live policy is documint on **both** networks, independently.

## Contents

| file | what it is |
| --- | --- |
| `echocert.ak` | the real, un-deployed echocert validator source (moved from `validators/`) |
| `evidence/policy-derivation.md` | reproducible proof that the live policy = documint bytes (preprod + mainnet) |
| `evidence/mainnet-assets.json` | the 3 assets actually minted under `32fd4d60…` on mainnet |
| `evidence/mainnet-deployed-script.json` | the deployed script fetched from chain by hash + self-hash check |
| `evidence/plutus-source-correct.json` | frozen `credential/plutus.json` (echocert entry = real `0053a3d5…`) |
| `evidence/plutus-frontend-deployed.json` | frozen `frontend/public/plutus.json` (echocert entry = documint bytes = live policy source) |

