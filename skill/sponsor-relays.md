# Sponsor Relays — the fee-payer relay

> Build a server endpoint that pays gas + rent for users with 0 SOL. **Pair every relay with `relay-security.md`** — an unvalidated relay is a wallet-drainer.

## The shape

Two halves: a **client** that builds a transaction with the sponsor as fee payer and signs as the user, and a **server** that validates, co-signs as fee payer, and broadcasts.

```
client: build ix → fee payer = sponsor → sign as user (partial) → POST base64 wire tx
server: decode → VALIDATE (relay-security.md) → add sponsor signature → broadcast → return signature
client: confirm(signature)
```

This skill ships **two reference implementations of the same relay**:
- **✓ Modern (Solana Kit / web3.js v2)** — the current 2026 stack; use this for new code.
- **✓ Mainnet-validated (web3.js 1.x)** — the exact patterns shipped and battle-tested on a live mainnet app, translated forward.

The validation checks are identical across both — see `relay-security.md`. Only the API surface differs.

---

## Modern reference — Solana Kit (`@solana/kit`, web3.js v2)

This mirrors the canonical fee-payer-relay pattern in Solana's own Kora docs: the user signs the message, then the relay adds the fee-payer signature to the compiled transaction.

### Client

```ts
import {
  pipe, address, createNoopSigner, createSolanaRpc,
  createTransactionMessage, setTransactionMessageFeePayerSigner,
  setTransactionMessageLifetimeUsingBlockhash, appendTransactionMessageInstructions,
  partiallySignTransactionMessageWithSigners, getBase64EncodedWireTransaction,
} from "@solana/kit";

// userSigner : a TransactionSigner from the embedded wallet (e.g. Privy via @solana/react),
//              attached as the signer on the program instruction's account(s).
// sponsorAddress : the relay's public key — the client holds the ADDRESS only, never the key.
const rpc = createSolanaRpc(RPC_URL);
const { value: latestBlockhash } = await rpc.getLatestBlockhash().send();

const message = pipe(
  createTransactionMessage({ version: 0 }),
  // Sponsor pays. A noop signer reserves the fee-payer slot without signing —
  // the relay fills that signature server-side.
  (m) => setTransactionMessageFeePayerSigner(createNoopSigner(address(sponsorAddress)), m),
  (m) => setTransactionMessageLifetimeUsingBlockhash(latestBlockhash, m),
  (m) => appendTransactionMessageInstructions(instructions, m),
);

// Signs with the user's attached signer; the noop fee-payer (sponsor) stays unsigned.
const partiallySigned = await partiallySignTransactionMessageWithSigners(message);
const wire = getBase64EncodedWireTransaction(partiallySigned);

const res = await fetch("/api/sponsor-broadcast", {
  method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ tx: wire }),
});
const raw = await res.text();                  // read text first — timeouts return empty/HTML
let json; try { json = JSON.parse(raw); }
catch { throw new Error(`Relay non-JSON (HTTP ${res.status}): ${raw.slice(0,200) || "<empty>"}`); }
if (!res.ok || "error" in json) throw new Error("error" in json ? json.error : `HTTP ${res.status}`);
// client confirms — the relay only broadcasts (see "hard-won details")
```

### Server

```ts
import {
  getBase64Encoder, getTransactionDecoder, getCompiledTransactionMessageDecoder,
  decompileTransactionMessage, getBase64EncodedWireTransaction,
  partiallySignTransaction, createKeyPairFromBytes, createSolanaRpc,
} from "@solana/kit";

export async function POST(req) {
  const { tx: b64 } = await req.json();

  // 1. decode wire → compiled Transaction { messageBytes, signatures: Record<Address, Sig|null> }
  const transaction = getTransactionDecoder().decode(getBase64Encoder().encode(b64));

  // 2. fee payer = first key of the ordered signatures map — must be the sponsor
  const feePayer = Object.keys(transaction.signatures)[0];
  if (feePayer !== SPONSOR_ADDRESS) return Response.json({ error: "fee_payer is not the sponsor" }, { status: 400 });

  // 3. decompile for human-friendly instruction inspection (programAddress, accounts[].role/.address)
  const message = decompileTransactionMessage(
    getCompiledTransactionMessageDecoder().decode(transaction.messageBytes)
  );

  validateForSponsorship(message, transaction, SPONSOR_ADDRESS);   // ← relay-security.md. The whole point.

  // 4. add the sponsor (fee payer) signature to the compiled transaction
  const sponsorKeyPair = await createKeyPairFromBytes(SPONSOR_SECRET_64);   // CryptoKeyPair (64-byte secret)
  const signed = await partiallySignTransaction([sponsorKeyPair], transaction);

  // 5. broadcast ONLY — client confirms (serverless times out before finalization)
  const rpc = createSolanaRpc(RPC_URL);
  const signature = await rpc
    .sendTransaction(getBase64EncodedWireTransaction(signed), { encoding: "base64", preflightCommitment: "confirmed" })
    .send();
  return Response.json({ signature });
}
```

---

> **Address Lookup Tables:** `decompileTransactionMessage` covers plain v0 transactions (the common onboarding case). If your transactions use ALTs, swap in the async `decompileTransactionMessageFetchingLookupTables(compiled, rpc)` so the looked-up account addresses resolve before you validate them — otherwise an ALT-referenced account could slip past the sponsor checks.

## Mainnet-validated reference — web3.js 1.x

The same relay as shipped on mainnet. Use when an existing codebase is on classic web3.js.

### Client
```ts
const tx = new Transaction().add(...ixs);
tx.feePayer = sponsorPubkey;                                  // sponsor pays
tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
const partial = await wallet.signTransaction(tx);             // Privy invisible signing; user slot only
await fetch("/api/sponsor-broadcast", {
  method: "POST", headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    tx: Buffer.from(partial.serialize({ requireAllSignatures: false, verifySignatures: false })).toString("base64"),
  }),
});
```

### Server
```ts
const tx = Transaction.from(Buffer.from(b64, "base64"));
validateForSponsorship(tx, sponsorPubkey);                    // relay-security.md
tx.partialSign(sponsorKeypair);                               // only runs if validation passed
const signature = await connection.sendRawTransaction(tx.serialize(), {
  skipPreflight: false, preflightCommitment: "confirmed",
});
return Response.json({ signature });
```

---

## Hard-won details (from a mainnet relay)

- **Broadcast-only, client-confirms.** Confirming on the server is the #1 cause of "Unexpected end of JSON input" in production — the serverless function times out before finalization. Return the signature immediately; let the client poll.
- **Client reads the response as text before `JSON.parse`.** A timeout returns an empty body or HTML; calling `.json()` directly throws and hides the real cause.
- **Wrap the whole handler in try/catch returning JSON.** Unhandled throws (env load, key decode, signing) otherwise return an empty 500 body the client can't parse.
- **1.x serialize uses `requireAllSignatures: false`** — the sponsor slot is intentionally empty when the client serializes; the server fills it.
- **`maxDuration`** must exceed your RPC's preflight-simulation time. Broadcast itself is fast.
- **Sponsor key is server-only:** load from an env secret, cache across requests, never log it, never let it be importable from a client bundle (`import "server-only"`). See `production-checklist.md`.

## Don't forget

`partialSign(sponsor)` / `partiallySignTransaction([sponsor], tx)` on an **unvalidated** transaction is the entire vulnerability class this skill exists to prevent. Go to `relay-security.md` now.
