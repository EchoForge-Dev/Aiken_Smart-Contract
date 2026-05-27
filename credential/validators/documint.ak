use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{NoDatum, Output, Transaction, placeholder}

/// Redeemer actions for the DocuMint minting policy.
pub type Action {
  /// Mint a new document anchor token. The `doc_hash` is the SHA-256 hash of the document.
  MintAnchor { doc_hash: ByteArray }
  /// Burn a previously minted document anchor token.
  BurnAnchor
}

/// Core validation logic for the DocuMint minting policy.
///
/// Parameters:
///   - `treasury`: The payment credential hash where the 5 ADA fee must be sent.
///   - `issuer`: The pubkey hash of the authorized minter.
///   - `redeemer`: The action being performed (MintAnchor or BurnAnchor).
///   - `policy_id`: The policy ID of this minting policy.
///   - `self`: The transaction being validated.
///
/// Rules:
///   - MintAnchor: issuer must sign, exactly 1 token minted with name == doc_hash,
///     and an output paying >= 5 ADA to the treasury address.
///   - BurnAnchor: issuer must sign, exactly -1 total minted under this policy.
pub fn documint_logic(
  treasury: ByteArray,
  issuer: ByteArray,
  redeemer: Action,
  policy_id: PolicyId,
  self: Transaction,
) -> Bool {
  let signed_by_issuer = list.has(self.extra_signatories, issuer)

  when redeemer is {
    MintAnchor { doc_hash } -> {
      // 1. Must be signed by the issuer
      expect signed_by_issuer

      // 2. The minted tokens under this policy must be exactly 1 token with name == doc_hash
      let minted_tokens = assets.tokens(self.mint, policy_id)
      let minted_pairs = dict.to_pairs(minted_tokens)
      expect [Pair(token_name, quantity)] = minted_pairs
      expect token_name == doc_hash
      expect quantity == 1

      // 3. There must be an output paying >= 5_000_000 lovelace to the treasury
      list.any(
        self.outputs,
        fn(output) {
          let credential_matches =
            when output.address.payment_credential is {
              VerificationKey(hash) -> hash == treasury
              Script(hash) -> hash == treasury
            }

          let lovelace = assets.lovelace_of(output.value)

          credential_matches && lovelace >= 5_000_000
        },
      )
    }

    BurnAnchor -> {
      // 1. Must be signed by the issuer
      expect signed_by_issuer

      // 2. The total minted under this policy must be exactly -1
      let minted_tokens = assets.tokens(self.mint, policy_id)
      let minted_pairs = dict.to_pairs(minted_tokens)
      expect [Pair(_token_name, quantity)] = minted_pairs

      quantity == -1
    }
  }
}

/// DocuMint minting policy validator.
///
/// A thin wrapper around `documint_logic` for on-chain use.
validator documint(treasury: ByteArray, issuer: ByteArray) {
  mint(redeemer: Action, policy_id: PolicyId, self: Transaction) {
    documint_logic(treasury, issuer, redeemer, policy_id, self)
  }

  else(_) {
    fail
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn test_policy_id() -> PolicyId {
  #"abcdef0123456789abcdef0123456789abcdef0123456789abcdef01"
}

fn test_issuer() -> ByteArray {
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
}

fn test_treasury() -> ByteArray {
  #"cafebabecafebabecafebabecafebabecafebabecafebabecafebabe"
}

fn test_doc_hash() -> ByteArray {
  #"aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd"
}

fn make_treasury_output(treasury: ByteArray, lovelace: Int) -> Output {
  Output {
    address: Address {
      payment_credential: VerificationKey(treasury),
      stake_credential: None,
    },
    value: assets.from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn make_treasury_script_output(treasury: ByteArray, lovelace: Int) -> Output {
  Output {
    address: Address {
      payment_credential: Script(treasury),
      stake_credential: None,
    },
    value: assets.from_lovelace(lovelace),
    datum: NoDatum,
    reference_script: None,
  }
}

fn make_mint_value(
  policy_id: PolicyId,
  token_name: ByteArray,
  qty: Int,
) -> Value {
  assets.from_asset(policy_id, token_name, qty)
}

// ---------------------------------------------------------------------------
// MintAnchor – success tests
// ---------------------------------------------------------------------------

test mint_anchor_succeeds() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_succeeds_with_extra_lovelace() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_output(treasury, 10_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_succeeds_treasury_is_script() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_script_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_succeeds_with_multiple_outputs() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let other_output =
    Output {
      address: Address {
        payment_credential: VerificationKey(
          #"11111111111111111111111111111111111111111111111111111111",
        ),
        stake_credential: None,
      },
      value: assets.from_lovelace(2_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [other_output, make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

// ---------------------------------------------------------------------------
// MintAnchor – failure tests
// ---------------------------------------------------------------------------

test mint_anchor_fails_without_issuer_signature() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()
  let attacker = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [attacker],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_fails_with_wrong_token_name() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()
  let wrong_hash =
    #"0000000000000000000000000000000000000000000000000000000000000000"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, wrong_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_fails_with_quantity_not_one() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 2),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_fails_insufficient_treasury_payment() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_output(treasury, 4_999_999)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_fails_no_treasury_output() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let unrelated_output =
    Output {
      address: Address {
        payment_credential: VerificationKey(
          #"11111111111111111111111111111111111111111111111111111111",
        ),
        stake_credential: None,
      },
      value: assets.from_lovelace(10_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [unrelated_output],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

test mint_anchor_fails_no_signature_at_all() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  documint_logic(treasury, issuer, MintAnchor { doc_hash }, policy_id, tx)
}

// ---------------------------------------------------------------------------
// BurnAnchor – success tests
// ---------------------------------------------------------------------------

test burn_anchor_succeeds() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, -1),
      outputs: [],
    }

  documint_logic(treasury, issuer, BurnAnchor, policy_id, tx)
}

// ---------------------------------------------------------------------------
// BurnAnchor – failure tests
// ---------------------------------------------------------------------------

test burn_anchor_fails_without_issuer_signature() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()
  let attacker = #"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [attacker],
      mint: make_mint_value(policy_id, doc_hash, -1),
      outputs: [],
    }

  documint_logic(treasury, issuer, BurnAnchor, policy_id, tx)
}

test burn_anchor_fails_with_positive_quantity() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, doc_hash, 1),
      outputs: [],
    }

  documint_logic(treasury, issuer, BurnAnchor, policy_id, tx)
}

test burn_anchor_fails_no_signature_at_all() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let doc_hash = test_doc_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [],
      mint: make_mint_value(policy_id, doc_hash, -1),
      outputs: [],
    }

  documint_logic(treasury, issuer, BurnAnchor, policy_id, tx)
}
