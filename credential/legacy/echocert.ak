use aiken/collection/dict
use aiken/collection/list
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{NoDatum, Output, Transaction, placeholder}

/// Certificate issuance actions.
/// cert_hash = SHA-256(name + "|" + date + "|" + issuer)
pub type CertAction {
  /// Issue a new certificate. Token name will equal cert_hash.
  IssueCert { cert_hash: ByteArray }
  /// Revoke a previously issued certificate.
  RevokeCert
}

pub fn echocert_logic(
  treasury: ByteArray,
  issuer: ByteArray,
  redeemer: CertAction,
  policy_id: PolicyId,
  self: Transaction,
) -> Bool {
  let signed_by_issuer = list.has(self.extra_signatories, issuer)

  when redeemer is {
    IssueCert { cert_hash } -> {
      expect signed_by_issuer

      let minted_tokens = assets.tokens(self.mint, policy_id)
      let minted_pairs = dict.to_pairs(minted_tokens)
      expect [Pair(token_name, quantity)] = minted_pairs
      expect token_name == cert_hash
      expect quantity == 1

      list.any(
        self.outputs,
        fn(output) {
          let cred_match =
            when output.address.payment_credential is {
              VerificationKey(hash) -> hash == treasury
              Script(hash) -> hash == treasury
            }
          cred_match && assets.lovelace_of(output.value) >= 1_000_000
        },
      )
    }

    RevokeCert -> {
      expect signed_by_issuer
      let minted_pairs = dict.to_pairs(assets.tokens(self.mint, policy_id))
      expect [Pair(_token_name, quantity)] = minted_pairs
      quantity == -1
    }
  }
}

validator echocert(treasury: ByteArray, issuer: ByteArray) {
  mint(redeemer: CertAction, policy_id: PolicyId, self: Transaction) {
    echocert_logic(treasury, issuer, redeemer, policy_id, self)
  }

  else(_) {
    fail
  }
}

// ─────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────

fn test_policy_id() -> PolicyId {
  #"abcdef0123456789abcdef0123456789abcdef0123456789abcdef01"
}

fn test_issuer() -> ByteArray {
  #"deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
}

fn test_treasury() -> ByteArray {
  #"cafebabecafebabecafebabecafebabecafebabecafebabecafebabe"
}

fn test_cert_hash() -> ByteArray {
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

fn make_mint_value(
  policy_id: PolicyId,
  token_name: ByteArray,
  qty: Int,
) -> Value {
  assets.from_asset(policy_id, token_name, qty)
}

test issue_cert_succeeds() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_succeeds_with_excess_ada() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [make_treasury_output(treasury, 10_000_000)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_succeeds_script_treasury() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let script_output =
    Output {
      address: Address {
        payment_credential: Script(treasury),
        stake_credential: None,
      },
      value: assets.from_lovelace(5_000_000),
      datum: NoDatum,
      reference_script: None,
    }

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [script_output],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_fails_wrong_signer() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()
  let attacker =
    #"1111111111111111111111111111111111111111111111111111111111111111"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [attacker],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_fails_wrong_token_name() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()
  let wrong_hash =
    #"0000000000000000000000000000000000000000000000000000000000000000"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, wrong_hash, 1),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_fails_quantity_not_one() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 2),
      outputs: [make_treasury_output(treasury, 5_000_000)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_fails_insufficient_fee() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [make_treasury_output(treasury, 999_999)],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test issue_cert_fails_no_treasury_output() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let unrelated =
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
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [unrelated],
    }

  echocert_logic(treasury, issuer, IssueCert { cert_hash }, policy_id, tx)
}

test revoke_cert_succeeds() {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, -1),
      outputs: [],
    }

  echocert_logic(treasury, issuer, RevokeCert, policy_id, tx)
}

test revoke_cert_fails_wrong_signer() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()
  let attacker =
    #"1111111111111111111111111111111111111111111111111111111111111111"

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [attacker],
      mint: make_mint_value(policy_id, cert_hash, -1),
      outputs: [],
    }

  echocert_logic(treasury, issuer, RevokeCert, policy_id, tx)
}

test revoke_cert_fails_positive_quantity() fail {
  let policy_id = test_policy_id()
  let issuer = test_issuer()
  let treasury = test_treasury()
  let cert_hash = test_cert_hash()

  let tx =
    Transaction {
      ..placeholder,
      extra_signatories: [issuer],
      mint: make_mint_value(policy_id, cert_hash, 1),
      outputs: [],
    }

  echocert_logic(treasury, issuer, RevokeCert, policy_id, tx)
}
