# EchoForge Aiken Smart Contracts

> Cardano on-chain validators written in [Aiken](https://aiken-lang.org/) (Plutus v3, stdlib v3.0.0).

---

## Repository Structure

```
LICENSE                                 # Apache-2.0 – source code
LICENSE-BRAND                           # CC BY-NC-ND 4.0 – logos and brand assets
NOTICE                                  # Copyright, licence split, trademarks
EC.svg / ED.svg / EF.svg / EU.svg       # Brand assets (CC BY-NC-ND 4.0)

credential/
├── aiken.toml                          # Project manifest
├── aiken.lock                          # Dependency lock file
├── plutus.json                         # Compiled Plutus blueprint
├── LICENSE                             # Apache-2.0
├── validators/
│   └── documint.ak                     # DocuMint – Document/certificate anchor minting policy (production EchoCert logic)
├── lib/
│   └── benchmarks/
│       ├── clausify/benchmark.ak       # Clausify benchmark
│       └── knights/                    # Knight's tour benchmark suite
│           ├── benchmark.ak
│           ├── chess_set.ak
│           ├── heuristic.ak
│           ├── queue.ak
│           ├── sort.ak
│           └── types.ak
└── legacy/                             # Archived, never-deployed echocert.ak + audit trail
    ├── README.md                       # Timeline + explanation of the documint/echocert discrepancy
    ├── echocert.ak                     # Original EchoCert source (not compiled by aiken build)
    └── evidence/
        ├── policy-derivation.md        # Reproducible proof of the deployed policy's derivation
        ├── mainnet-assets.json
        ├── mainnet-deployed-script.json
        ├── plutus-frontend-deployed.json
        ├── plutus-source-correct.json
        └── IMG_5085.jpg
```

---

## Contracts

> **⚠️ Important:** The on-chain EchoCert minting policy deployed on mainnet and preprod runs **`documint`'s validator logic**, not the separate `echocert.ak`. See [`credential/legacy/README.md`](credential/legacy/README.md) for the historical background and reproducible proof. For more context, see [echoforgellc.tech/blog](https://echoforgellc.tech/blog).

### 1. EchoCert.ak- Not in use

The **production minting policy** for issuing and revoking on-chain credential certificates as Cardano native tokens.

**Note:** The production implementation uses `documint.ak` (see below). The original `echocert.ak` was never deployed; its source code is archived in [`credential/legacy/`](credential/legacy/) for historical reference.

#### Purpose

EchoCert turns a credential (name + date + issuer) into a **unique, non-fungible token** anchored on Cardano. Each token name equals `SHA-256(name | date | issuer)`, making the token name itself a cryptographic commitment to the certificate content.

#### Parameters (applied at compile time)

| Parameter  | Type        | Description                                              |
|-----------|-------------|----------------------------------------------------------|
| `treasury` | `ByteArray` | Payment credential hash that receives the 1 ADA issuance fee |
| `issuer`   | `ByteArray` | Public key hash of the certificate issuer's own wallet. Under this permissionless design, anyone can be an `issuer` for their own certificates (see Trust Tier model below); this parameter identifies *who* issued a given certificate, not *whether* they were authorised to. |

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
| Impersonating another issuer | Every mint requires an `extra_signatories` check against the `issuer` key hash — no one can mint under a policy parameterised to someone else's key. (This does not restrict *who* may become an issuer — see Trust Tier model.) |
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

### 2. DocuMint – The Deployed EchoCert Validator (`credential/validators/documint.ak`)

**This is the production-deployed minting validator for EchoCert.** Although named `documint`, it enforces the same security guarantees as the separate `echocert.ak` design. All EchoCert credentials minted on mainnet and preprod are governed by this validator.

A **minting policy** for anchoring document hashes on Cardano as native tokens — a tamper-evident notarisation primitive.

#### Purpose

DocuMint creates a **unique on-chain anchor** for any document. The token name equals `SHA-256(document_bytes)`, so the token itself proves that a specific byte sequence existed at block time. Burning the token formally revokes the anchor.

When used as EchoCert's production validator, it anchors credential credentials (name + date + issuer) as immutable on-chain records.

#### Parameters (applied at compile time)

| Parameter  | Type        | Description                                              |
|-----------|-------------|----------------------------------------------------------|
| `treasury` | `ByteArray` | Payment credential hash that receives the 5 ADA notarisation fee |
| `issuer`   | `ByteArray` | Public key hash of the certificate issuer's own wallet. Under this permissionless design, anyone can be an `issuer` for their own certificates (see Trust Tier model below); this parameter identifies *who* issued a given certificate, not *whether* they were authorised to. |

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
| Impersonating another issuer | Every mint requires an `extra_signatories` check against the `issuer` key hash — no one can anchor under a policy parameterised to someone else's key. (This does not restrict *who* may become an issuer — see Trust Tier model.) |
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

## Deployment Status

### Production (Live on Mainnet & Preprod)

The production EchoCert system runs **`documint.ak`**, not a separate `echocert.ak` deployment. This decision was made in July 2026 after an on-chain audit confirmed that documint and echocert enforce equivalent trust and security properties (see [`credential/legacy/evidence/policy-derivation.md`](credential/legacy/evidence/policy-derivation.md) for reproducible verification).

### Archive

The original `echocert.ak` validator was never deployed to mainnet or preprod. Its source code is preserved in [`credential/legacy/echocert.ak`](credential/legacy/echocert.ak) along with a full audit trail proving the discrepancy and explaining the timeline (see [`credential/legacy/README.md`](credential/legacy/README.md)).

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

## Trust Tier Model

This platform records certificate content and issuance time. Unverified certificates do not represent the issuer's true identity. Domain verification only proves the issuer controls the domain, not institutional qualifications or content authenticity. **Certificate authenticity is the responsibility of the issuer.**

### Why Is There No Single "Official" Policy ID?

`treasury` and `issuer` are both **compile-time parameters** baked into the validator script (see `validator documint(treasury, issuer)` in [`documint.ak`](credential/validators/documint.ak)). Applying a different `issuer` key produces a different compiled script, and therefore a **different script hash — a different Policy ID.** Since this is a permissionless system (Tier 1), any wallet can become an issuer, so there is no one Policy ID that "is" EchoCert the way a single NFT collection has one canonical Policy ID. Checking "is this Policy ID the official one?" is not a well-formed question here.

Genuineness is instead established as a **three-layer model**, which separates "is this certificate real" from "is this issuer trustworthy":

1. **Structural verification (protocol conformance).** Independent of which Policy ID is involved, anyone can confirm the minting transaction satisfies the validator's hard rules: exactly one token name is minted under the policy, in a quantity of exactly one (no batch minting), that name equals the SHA-256 hash of the certificate/document content, and the script's compiled bytes match the published `documint` validator in [`plutus.json`](credential/plutus.json) (a Plutus script hash is deterministic from its bytes plus its applied parameters — see [`credential/legacy/evidence/policy-derivation.md`](credential/legacy/evidence/policy-derivation.md) for a worked, reproducible example of this check). This proves the token was minted by *a* genuine copy of the validator — not that it came from the official platform.

2. **Treasury anchoring (platform anchor).** Structural conformance alone isn't sufficient — anyone can compile their own copy of the same validator with their own `issuer` key, satisfying layer 1 while having nothing to do with EchoForge. The differentiator is the `treasury` parameter: every certificate issued through the official platform pays its fee to the published EchoForge treasury address, regardless of which `issuer` key signed it. [^1] A transaction that is structurally correct but pays a treasury address outside that set did not come from the official platform, no matter how correct its logic looks. This is the one constant across every legitimate issuer, in place of a single Policy ID.

   [^1]: *For developers reconciling this against the authenticity-check implementation: "the published treasury address" is not always a single unchanging constant — it may be rotated for security (e.g. a cold-wallet migration), in which case it resolves to a small set of historical addresses, each valid for the time window it was in effect. Verification matches a certificate's mint time to the official address in effect during that window; older, superseded addresses remain recognized as valid for certificates minted while they were current. This detail is omitted from the main text above for readability; general readers can treat "the treasury address" as effectively a single constant.*

3. **Issuer trust tier (real-world identity).** Passing layers 1–2 only proves the certificate is authentic *to the protocol* — it says nothing about who the specific issuer is or whether they can be trusted. That question is answered separately by the three tiers below (Unverified / Domain-Linked / On-Chain Identity).

In short: **the Policy ID identifies *which issuer* minted a token, not *whether it's genuine*.** Genuineness comes from structure + treasury anchor (layers 1–2); trustworthiness of the issuer is a separate judgment made via the tier system (layer 3).

### Tier 1 · Active—Permissionless — Unverified Issuance

- Anyone can issue certificates without any identity verification.
- Certificates carry an "Unverified Issuer" watermark.
- Suitable for personal use, small events, and informal certificates.
- ⚠️ **This platform does not verify any issuer information.**

### Tier 2 · Active—Domain-Linked — Domain Verification

- Issuers prove domain control via DNS TXT records to unlock the green-label professional style.
- Certificate displays "Issued by [Name] ✓"; the lookup page shows a green checkmark next to the wallet address.
- Trust comes from the issuer's own domain reputation; the platform provides the verification tool.
- ⚠️ **This platform only verifies the issuer's control over the stated domain — not institutional qualifications or certificate content.**

#### Domain Spoofing Risk

The system cannot distinguish lookalike domains (e.g. `stonepark.edu` vs `st0nepark.edu`). Always verify the domain spelling against the institution's official website. The recipient bears responsibility for this check; the platform provides the domain display as a verification aid.

### Tier 3 · Coming Soon—On-Chain Identity — DID Verification

- Only wallets holding specific Governance Tokens or verified via Cardano DID may issue certificates with the official color scheme.
- Trust is derived from on-chain data — transactions originating from a known DAO multisig wallet are verifiably authentic.
- **Certificate authenticity is the responsibility of the issuer, not the platform.**

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
| License | Apache-2.0 (code) / CC BY-NC-ND 4.0 (brand assets) |
| Network | Cardano (mainnet / preprod) |

---

## License

This repository is dual-licensed. See [NOTICE](NOTICE) for the full statement.

- **[Apache-2.0](LICENSE)** — Aiken source code (`*.ak`), manifests, compiled
  blueprints, and documentation. Free to use, modify, and deploy commercially.
- **[CC BY-NC-ND 4.0](LICENSE-BRAND)** — brand assets: the EchoForge / EchoCert
  logos and marks (`EC.svg`, `ED.svg`, `EF.svg`, `EU.svg`, and any logo, icon,
  wordmark, seal or badge added later). Redistribution is allowed unmodified and
  non-commercially, with attribution to "EchoForge —
  [echoforgellc.tech](https://echoforgellc.tech)"; modification or commercial use
  requires prior written permission.

**Trademarks:** "EchoForge", "EchoCert", "DocuMint" and the associated logos are
trademarks of EchoForge. Neither license grants trademark rights — forks must
not imply endorsement by or affiliation with EchoForge.
