# EchoForge Aiken Smart Contracts

> Cardano on-chain validators written in [Aiken](https://aiken-lang.org/) (Plutus v3, stdlib v3.0.0).

---

## Repository Structure

```
credential/
├── aiken.toml                          # Project manifest
├── aiken.lock                          # Dependency lock file
├── plutus.json                         # Compiled Plutus blueprint
├── LICENSE                             # Apache-2.0
├── validators/
│   ├── echocert.ak                     # EchoCert – Certificate minting policy
│   └── documint.ak                     # DocuMint – Document anchor minting policy
└── lib/
    └── benchmarks/
        ├── clausify/benchmark.ak       # Clausify benchmark
        └── knights/                    # Knight's tour benchmark suite
            ├── benchmark.ak
            ├── chess_set.ak
            ├── heuristic.ak
            ├── queue.ak
            ├── sort.ak
            └── types.ak
```

---

## Contracts

### 1. EchoCert (`credential/validators/echocert.ak`)

A **minting policy** for issuing and revoking on-chain credential certificates as Cardano native tokens.

#### Purpose

EchoCert turns a credential (name + date + issuer) into a **unique, non-fungible token** anchored on Cardano. Each token name equals `SHA-256(name | date | issuer)`, making the token name itself a cryptographic commitment to the certificate content.

#### Parameters (applied at compile time)

| Parameter  | Type        | Description                                              |
|-----------|-------------|----------------------------------------------------------|
| `treasury` | `ByteArray` | Payment credential hash that receives the 1 ADA issuance fee |
| `issuer`   | `ByteArray` | Public key hash of the entity authorised to issue/revoke |

#### Redeemer

```aiken
pub type CertAction {
  IssueCert { cert_hash: ByteArray }
  RevokeCert
}
```

#### Validation Rules

**`IssueCert { cert_hash }`**

1. Transaction must be signed by `issuer` (`extra_signatories` contains `issuer`).
2. Exactly **one token** is minted under this policy; its name must equal `cert_hash`.
3. The minted quantity must be exactly **1** (no batch minting).
4. At least one transaction output must pay **≥ 1 ADA (1,000,000 lovelace)** to the `treasury` address (supports both `VerificationKey` and `Script` treasury credentials).

**`RevokeCert`**

1. Transaction must be signed by `issuer`.
2. Exactly **one token** is burned under this policy (quantity = **−1**).

#### Security Properties

| Threat | Mitigation |
|--------|-----------|
| Unauthorised issuance | Every mint requires an `extra_signatories` check against the `issuer` key hash — no signature, no mint. |
| Token name forgery | Token name is enforced to equal the `cert_hash` supplied in the redeemer; mismatching names cause immediate script failure. |
| Batch inflation | The validator pattern-matches `[Pair(token_name, quantity)]` — any attempt to mint more than one token name or more than 1 unit under the policy is rejected at the pattern-match. |
| Free minting (no fee) | `IssueCert` requires at least one output ≥ 1 ADA to the treasury; a transaction that omits this output fails. |
| Burn-as-mint attack | `RevokeCert` enforces quantity = −1; passing a positive quantity causes the equality check to fail. |
| Non-issuer revocation | `RevokeCert` also requires `issuer` signature — holders cannot burn certificates they did not issue. |
| `else` clause | The `else(_) { fail }` catch-all ensures the policy rejects any purpose other than minting (e.g. accidental spend). |

#### Test Coverage

| Test | Expected |
|------|---------|
| `issue_cert_succeeds` | ✅ Pass |
| `issue_cert_succeeds_with_excess_ada` | ✅ Pass |
| `issue_cert_succeeds_script_treasury` | ✅ Pass |
| `issue_cert_fails_wrong_signer` | ❌ Fail (expected) |
| `issue_cert_fails_wrong_token_name` | ❌ Fail (expected) |
| `issue_cert_fails_quantity_not_one` | ❌ Fail (expected) |
| `issue_cert_fails_insufficient_fee` | ❌ Fail (expected) |
| `issue_cert_fails_no_treasury_output` | ❌ Fail (expected) |
| `revoke_cert_succeeds` | ✅ Pass |
| `revoke_cert_fails_wrong_signer` | ❌ Fail (expected) |
| `revoke_cert_fails_positive_quantity` | ❌ Fail (expected) |

---

### 2. DocuMint (`credential/validators/documint.ak`) — The first version of EchoCert

A **minting policy** for anchoring document hashes on Cardano as native tokens — a tamper-evident notarisation primitive.

#### Purpose

DocuMint creates a **unique on-chain anchor** for any document. The token name equals `SHA-256(document_bytes)`, so the token itself proves that a specific byte sequence existed at block time. Burning the token formally revokes the anchor.

#### Parameters (applied at compile time)

| Parameter  | Type        | Description                                              |
|-----------|-------------|----------------------------------------------------------|
| `treasury` | `ByteArray` | Payment credential hash that receives the 5 ADA notarisation fee |
| `issuer`   | `ByteArray` | Public key hash of the authorised notary |

#### Redeemer

```aiken
pub type Action {
  MintAnchor { doc_hash: ByteArray }
  BurnAnchor
}
```

#### Validation Rules

**`MintAnchor { doc_hash }`**

1. Transaction must be signed by `issuer`.
2. Exactly **one token** is minted under this policy; its name must equal `doc_hash`.
3. The minted quantity must be exactly **1**.
4. At least one transaction output must pay **≥ 5 ADA (5,000,000 lovelace)** to the `treasury` address (supports both `VerificationKey` and `Script` treasury credentials).

**`BurnAnchor`**

1. Transaction must be signed by `issuer`.
2. Exactly **one token** is burned under this policy (quantity = **−1**).

#### Security Properties

| Threat | Mitigation |
|--------|-----------|
| Unauthorised anchoring | Every mint requires an `extra_signatories` check against `issuer`; unsigned transactions are rejected. |
| Hash substitution | Token name is enforced to equal `doc_hash` from the redeemer; a forged or different hash fails the equality check. |
| Duplicate anchors | One token per transaction prevents bulk minting; the pattern-match `[Pair(...)]` rejects any multi-name or multi-quantity mint. |
| Fee evasion | `MintAnchor` requires an output ≥ 5 ADA to the treasury — no payment, no anchor. |
| Positive-quantity burn attempt | `BurnAnchor` enforces quantity = −1; passing +1 (or any positive value) fails the final equality check. |
| Unauthorised revocation | `BurnAnchor` requires `issuer` signature — third parties cannot destroy anchors. |
| `else` clause | `else(_) { fail }` rejects all non-mint purposes (spend, certify, etc.). |

#### Test Coverage

| Test | Expected |
|------|---------|
| `mint_anchor_succeeds` | ✅ Pass |
| `mint_anchor_succeeds_with_extra_lovelace` | ✅ Pass |
| `mint_anchor_succeeds_treasury_is_script` | ✅ Pass |
| `mint_anchor_succeeds_with_multiple_outputs` | ✅ Pass |
| `mint_anchor_fails_without_issuer_signature` | ❌ Fail (expected) |
| `mint_anchor_fails_with_wrong_token_name` | ❌ Fail (expected) |
| `mint_anchor_fails_with_quantity_not_one` | ❌ Fail (expected) |
| `mint_anchor_fails_insufficient_treasury_payment` | ❌ Fail (expected) |
| `mint_anchor_fails_no_treasury_output` | ❌ Fail (expected) |
| `mint_anchor_fails_no_signature_at_all` | ❌ Fail (expected) |
| `burn_anchor_succeeds` | ✅ Pass |
| `burn_anchor_fails_without_issuer_signature` | ❌ Fail (expected) |
| `burn_anchor_fails_with_positive_quantity` | ❌ Fail (expected) |

---

## Shared Design Patterns & Security Model

Both validators follow the same defence-in-depth pattern:

```
Issuer key check  →  Token name binding  →  Quantity check  →  Fee / output check
```

1. **Issuer-gated minting** — All actions require an explicit signature from the configured `issuer` key hash, checked via `list.has(self.extra_signatories, issuer)`. This is a hard on-chain constraint; no off-chain bypass is possible.

2. **Hash-bound token names** — Token names equal the document/certificate hash supplied at call time, creating a cryptographic link between the token and its real-world content.

3. **Singleton enforcement** — The pattern match `expect [Pair(token_name, quantity)]` ensures exactly one token entry exists under the policy per transaction. Any attempt to mint multiple names or batch-mint multiple units fails at deserialization.

4. **Fail-fast with `expect`** — The validators use Aiken's `expect` keyword, which immediately aborts with a script error on any violated constraint rather than silently continuing.

5. **Exhaustive `else` branch** — `else(_) { fail }` prevents the policy from being used as a spend or other validator kind, eliminating unexpected attack surfaces.

6. **Treasury as payment commitment** — Requiring a minimum lovelace payment to a fixed treasury address prevents free-of-cost minting and creates a financial stake in every issuance.

---

## Plutus Blueprint

The compiled validator schemas and their CBOR-encoded scripts are published in [`credential/plutus.json`](credential/plutus.json) (Plutus v3, generated by Aiken v1.1.21).

| Validator | Entry Point |
|-----------|-------------|
| `documint.documint` | `documint.documint.mint` |
| `echocert.echocert` | `echocert.echocert.mint` |

---

## Getting Started

### Prerequisites

- [Aiken CLI](https://aiken-lang.org/installation-instructions) ≥ v1.1.21

### Build

```bash
cd credential
aiken build
```

This produces (or updates) `plutus.json` with the compiled scripts.

### Run Tests

```bash
cd credential
aiken check
```

All tests (success and expected-failure cases) should pass.

### Run Benchmarks

```bash
cd credential
aiken bench
```

---

## Project Info

| Field | Value |
|-------|-------|
| Compiler | Aiken v1.1.21 |
| Plutus version | v3 |
| Standard library | aiken-lang/stdlib v3.0.0 |
| License | Apache-2.0 |
| Network | Cardano (mainnet / preprod) |

---

## License

[Apache-2.0](credential/LICENSE)
