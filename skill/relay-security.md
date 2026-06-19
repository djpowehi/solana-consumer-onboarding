# Relay Security — the part everyone gets wrong

> Load this **whenever** you build or modify a sponsor relay. The relay's value is not that it pays gas — it's that it pays gas **safely**. This file is the moat.

## The core danger (understand this before writing any code)

A sponsor relay holds a keypair with real funds and signs transactions built by **untrusted clients**. When the relay adds its signature at the message level, that signature authorizes the sponsor in **every instruction that lists the sponsor's pubkey** — not just as fee payer.

So a malicious client can craft a transaction where the sponsor appears as:
- the `authority` on an SPL Token transfer → **drains the sponsor's tokens**
- the `from` on a `SystemProgram.transfer` → **drains the sponsor's SOL**
- a writable signer on some other program's "withdraw" → **drains whatever that program lets it**

The sponsor signed once (intending only to pay the fee), but authorized all of it. A relay that does `tx.partialSign(sponsor); broadcast()` without inspecting the contents is a **wallet-drainer with a public HTTP endpoint**.

The fix is a strict, deny-by-default validator that runs on every request **before** the sponsor signs:
1. Allowlist which **programs** may appear.
2. Allowlist which **instructions** (by discriminator) of your program may appear.
3. Verify the **sponsor pubkey appears in no slot except the exact ones you intend** (the fee-payer position, and — only if you must — the rent-payer slot of an ATA-create).
4. Verify the **user's signature is already attached** and only the sponsor's slot is empty.

## Threat models

Written threat-first (impact → mitigation), the way an auditor reads a relay. Each is a real attack against a naive relay; each mitigation is implemented in the reference validator below.

### Threat 1 — Sponsor Authority Escalation *(the one that drains you)*
This is the whole skill in one threat. Read it first; everything else is a variation.
- **Attack:** client adds an SPL Token `transfer` (or any program ix) with the sponsor as the `authority`/source. Message-level sponsor signature authorizes it.
- **Impact:** treasury drain (tokens or SOL), bounded only by the sponsor's balance.
- **Mitigation:** per-instruction role validation. The sponsor pubkey must not appear in any instruction slot other than the fee-payer position. Scan `instruction.keys` of every instruction; reject if the sponsor is referenced anywhere it shouldn't be.

### Threat 2 — Unexpected instruction smuggled into the transaction
- **Attack:** client appends an extra instruction (a different program, or a non-allowlisted instruction of your program) alongside a legitimate-looking one.
- **Impact:** arbitrary sponsored action; the relay becomes a generic "sign anything" oracle.
- **Mitigation:** allowlist by program ID **and** by instruction discriminator. Deny by default. Every instruction must target either your program (with an allowlisted discriminator) or an explicitly allowlisted helper program (ComputeBudget, Token, AssociatedToken). **Do not allowlist SystemProgram** at the top level — a bare `SystemProgram.transfer` with the sponsor as `from` is a SOL drain. (ATA-create CPIs into System internally; that's fine and does not require a top-level System instruction.)

> **Design rationale — why the relay refuses generic `SystemProgram` transfers.** A generic SOL transfer is *inherently value-moving*, and the sponsor is the one account with a balance worth moving. A relay that will sign an arbitrary `SystemProgram.transfer` is, by construction, a faucet for its own treasury. The fix isn't to validate System transfers more carefully — it's to **never sponsor them**. Sponsor only the specific, known application instructions your product needs, each with explicit per-instruction validation. The deny-by-default helper allowlist (ComputeBudget / Token / AssociatedToken, *not* System) encodes exactly this judgment.

### Threat 3 — Sponsor billed for the user's value transfer
- **Attack:** for an instruction that *moves the user's value* (e.g. a deposit where slot 1 = depositor, slot 2 = depositor's token account), the client substitutes the **sponsor** as the depositor.
- **Impact:** the relay funds the user's deposit out of the sponsor's balance — a drain disguised as a normal action.
- **Mitigation:** for any value-moving instruction, assert the sponsor appears **nowhere** in it. The sponsor pays fees and rent — never principal. (In the reference app, `deposit` is excluded from the relay allowlist entirely for exactly this reason, and the value-moving slots are checked to never equal the sponsor.)

### Threat 4 — Account rooted at the sponsor instead of the user
- **Attack:** in a "create account / create family / register" instruction, the client puts the sponsor (not the user) in the owner/authority slot.
- **Impact:** the created PDA is rooted at the sponsor; rent is spent on an account the user can't use and the app can't recover. Griefing → treasury exhaustion.
- **Mitigation:** the sponsor is allowed **only at slot 0 (fee payer)** of a create instruction, never any other slot. Reject if the sponsor pubkey appears at any index `!= 0`.

### Threat 5 — Sponsored-creation spam
- **Attack:** a bot hammers the relay with valid-but-throwaway create/onboard requests.
- **Impact:** treasury exhaustion via thousands of small rent payments; the attack is "legitimate" per the allowlist.
- **Mitigation:** rate limits + per-identity quotas + a treasury balance cap with monitoring/alerting. Pair with **lazy creation** (see `transaction-bundling.md`): don't pay rent until the user takes a real, value-bearing action, so a signup that never converts costs the sponsor nothing.

### Threat 6 — Positional assumptions broken by a future program update
- **Attack:** not malicious — your own dependency changes. You validated "sponsor is at slot 0" assuming a fixed account ordering; a protocol upgrade reorders accounts and your positional check now validates the wrong slot.
- **Impact:** silent validation bypass.
- **Mitigation:** validate by **explicit role**, not by slot index — ask "is this key the sponsor? is it a signer? is it writable?" rather than "is the sponsor at index 0?". Pin the program IDs and instruction layouts you depend on, and treat account ordering as a versioned contract: re-verify it on every dependency bump. (Slot-0 checks are acceptable only for layouts you control and pin, like the ATA-create rent payer.)

## The invariants (reason from these, not from prose)

A safe relay holds these at all times. An agent should treat them as hard rules and reject any transaction that violates one — they are not recommendations.

- **Invariant 1 — Fee-payer-only.** The sponsor may appear *only* as the fee payer. If the sponsor appears as an authority or signer on any value-moving instruction, **reject**.
- **Invariant 2 — Deny by default.** Every program and every instruction must be explicitly allowlisted. Anything not on the list → **reject**.
- **Invariant 3 — Sponsor pays fees and rent, never principal.** The sponsor must appear in no instruction account except the fee-payer position (and, if strictly needed, the ATA-create rent-payer at slot 0). Any other occurrence → **reject**.
- **Invariant 4 — User signs first.** The user's signature must already be attached; only the sponsor's slot may be empty when the relay receives the transaction. Otherwise → **reject**.

The dangerous/safe pairs below are these invariants, violated and upheld.

## Dangerous pattern → safe pattern

### Blind sponsorship
```ts
// ❌ DANGEROUS — signs and broadcasts anything the client sends.
const tx = Transaction.from(Buffer.from(body.tx, "base64"));
tx.partialSign(sponsorKeypair);
return send(await connection.sendRawTransaction(tx.serialize()));
```
```ts
// ✅ SAFE — validate every instruction, then sign only if it passes.
const tx = Transaction.from(Buffer.from(body.tx, "base64"));
assertOnlyAllowlistedPrograms(tx);          // Threat 2
assertAllowlistedDiscriminators(tx);        // Threat 2
assertSponsorOnlyAtFeePayer(tx, sponsor);   // Threats 1, 3, 4
assertUserAlreadySigned(tx, sponsor);       // see below
tx.partialSign(sponsorKeypair);
return send(await connection.sendRawTransaction(tx.serialize()));
```

### Trusting the fee payer field alone
```ts
// ❌ DANGEROUS — fee_payer is right, but an inner ix lists sponsor as a token authority.
if (tx.feePayer.equals(sponsor)) { tx.partialSign(sponsorKeypair); /* ... */ }
```
```ts
// ✅ SAFE — fee_payer check is necessary but NOT sufficient. Also scan every key.
if (!tx.feePayer?.equals(sponsor)) reject("fee_payer is not the sponsor");
for (const ix of tx.instructions) {
  for (let i = 0; i < ix.keys.length; i++) {
    if (!ix.keys[i].pubkey.equals(sponsor)) continue;
    if (isLegalSponsorSlot(ix, i)) continue;   // ONLY fee-payer, or ATA-create payer at slot 0
    reject(`sponsor referenced at illegal slot ${i} of ${ix.programId}`);
  }
}
```

### Allowlisting SystemProgram "to be safe"
```ts
// ❌ DANGEROUS — now a SystemProgram.transfer{ from: sponsor } drains SOL.
const ALLOWED_PROGRAMS = new Set([MY_PROGRAM, ComputeBudget, Token, AssociatedToken, SystemProgram]);
```
```ts
// ✅ SAFE — System is intentionally omitted. ATA-create CPIs into it internally; you
//    never need a TOP-LEVEL System instruction in an onboarding flow.
const ALLOWED_HELPER_PROGRAMS = new Set([ComputeBudget, Token, AssociatedToken]);
```

## Reference validator (annotated)

This is the validation spine, distilled from a relay running on Solana mainnet. Logic is shown with classic web3.js (`Transaction`, `instruction.keys`) because it maps 1:1 to what's on-chain; the Kit/v2 equivalent inspects the decompiled message instructions the same way (`programAddress`, `accounts[].address`, `.role`). The *checks* are what matter, not the API surface.

```ts
const ALLOWED_DISCRIMINATORS = new Set<number>([/* your user-action ixs ONLY */]);
const ALLOWED_HELPER_PROGRAMS = new Set([ComputeBudget, Token, AssociatedToken]); // NO System

function validateForSponsorship(tx: Transaction, sponsor: PublicKey) {
  // 1. fee_payer must be the sponsor (necessary, not sufficient)
  if (!tx.feePayer?.equals(sponsor)) throw reject("fee_payer is not the sponsor");

  // 2. every instruction: allowlisted program, and your-program ixs have allowlisted discriminators
  const mine = tx.instructions.filter((i) => i.programId.equals(MY_PROGRAM));
  for (const ix of mine) {
    if (ix.data.length === 0 || !ALLOWED_DISCRIMINATORS.has(ix.data[0]))
      throw reject(`discriminator ${ix.data[0]} not allowlisted`);
  }
  for (const ix of tx.instructions) {
    if (ix.programId.equals(MY_PROGRAM)) continue;
    if (!ALLOWED_HELPER_PROGRAMS.has(ix.programId.toBase58()))
      throw reject(`non-allowlisted program ${ix.programId}`);
  }

  // 3. sponsor appears in NO slot except fee-payer / ATA-create payer (slot 0)
  for (const ix of tx.instructions) {
    const isCreateAta = ix.programId.equals(ASSOCIATED_TOKEN_PROGRAM_ID);
    for (let i = 0; i < ix.keys.length; i++) {
      if (!ix.keys[i].pubkey.equals(sponsor)) continue;
      if (isCreateAta && i === 0) continue;       // ATA rent payer — the only legal inner slot
      throw reject(`sponsor referenced at illegal slot ${i} of ${ix.programId}`);
    }
  }

  // 4. user already signed; only the sponsor's slot is empty
  const sponsorSlotEmpty = tx.signatures.some(
    (s) => s.publicKey.equals(sponsor) && s.signature === null
  );
  const othersSigned = tx.signatures
    .filter((s) => !s.publicKey.equals(sponsor))
    .every((s) => s.signature !== null);
  if (!sponsorSlotEmpty) throw reject("sponsor slot missing/already filled");
  if (!othersSigned) throw reject("user signature missing — sign client-side first");
}
```

### Same validator, Solana Kit (web3.js v2)

Decode the wire transaction, decompile the message, and run the identical checks against the friendlier shape (`programAddress`, `accounts[].address`, `signatures` map). Wire it into the Kit server handler in `sponsor-relays.md`.

```ts
function validateForSponsorship(message, transaction, sponsor /* Address */) {
  // 1. fee payer = first key of the ordered signatures map
  if (Object.keys(transaction.signatures)[0] !== sponsor) throw reject("fee_payer is not the sponsor");

  // 2. allowlist programs + your-program discriminators
  for (const ix of message.instructions) {
    if (ix.programAddress === MY_PROGRAM) {
      const disc = ix.data?.[0];
      if (disc === undefined || !ALLOWED_DISCRIMINATORS.has(disc)) throw reject(`disc ${disc} not allowlisted`);
    } else if (!ALLOWED_HELPER_PROGRAMS.has(ix.programAddress)) {
      throw reject(`non-allowlisted program ${ix.programAddress}`);
    }
  }

  // 3. sponsor appears in NO instruction account except ATA-create payer (slot 0)
  for (const ix of message.instructions) {
    const isCreateAta = ix.programAddress === ASSOCIATED_TOKEN_PROGRAM_ADDRESS;
    (ix.accounts ?? []).forEach((acc, i) => {
      if (acc.address !== sponsor) return;
      if (isCreateAta && i === 0) return;
      throw reject(`sponsor at illegal slot ${i} of ${ix.programAddress}`);
    });
  }

  // 4. user already signed; only the sponsor slot is empty
  const sigs = transaction.signatures;                  // Record<Address, SignatureBytes | null>
  if (sigs[sponsor] != null) throw reject("sponsor slot already filled");
  for (const [addr, sig] of Object.entries(sigs)) if (addr !== sponsor && sig == null) throw reject("a required signer is missing");
}
```

## Review checklist (run before shipping a relay)

- [ ] Deny by default: every program and every instruction is explicitly allowlisted.
- [ ] Value-moving instructions are **excluded** from the allowlist (or assert sponsor ∉ instruction).
- [ ] Sponsor pubkey is rejected in every slot except fee-payer (and ATA-create payer slot 0).
- [ ] `feePayer === sponsor` is checked **and** is not the only check.
- [ ] User signature is verified present; only the sponsor slot is signed by the relay.
- [ ] Rate limits + per-identity quota + treasury balance cap + alerting (see `production-checklist.md`).
- [ ] Role checks (signer/writable) preferred over positional assumptions where feasible.
- [ ] Sponsor secret key is server-only, never logged, never importable from a client bundle.
