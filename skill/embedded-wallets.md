# Embedded Wallets — identity without a seed phrase

> Load this for the email/social-login path: give a non-crypto user a Solana wallet they never have to think about. For existing-wallet users (Phantom/Solflare), use the wallet-adapter / `phantom-connect` path instead.
>
> Stack note: Privy examples below target `@privy-io/react-auth`. To use these with Solana Kit, expose the embedded wallet as a Kit `TransactionSigner` — `@solana/react` provides `useWalletAccountTransactionSendingSigner` / `createTransactionSignerFromWalletAccount` for wallet-standard wallets, or wrap Privy's `signTransaction` in a small partial-signer adapter. The relay flow in `sponsor-relays.md` consumes that signer.

## Goal

The user logs in with email or Google and gets a Solana keypair created and custodied for them — no seed phrase, no extension, no popup. Signing is invisible: the app calls `signTransaction` and the user sees nothing crypto-flavored.

## Privy setup (invisible chain)

This is the config shape as shipped on mainnet — note the exact nesting; it's easy to get wrong.

```tsx
import { PrivyProvider } from "@privy-io/react-auth";
import { toSolanaWalletConnectors } from "@privy-io/react-auth/solana";
import { createSolanaRpc, createSolanaRpcSubscriptions } from "@solana/kit";

const solanaConnectors = toSolanaWalletConnectors(); // lets power users attach Phantom/Solflare

<PrivyProvider
  appId={PRIVY_APP_ID}
  config={{
    appearance: {
      walletChainType: "solana-only",   // Solana-only login screen
    },
    embeddedWallets: {
      solana: {
        createOnLogin: "users-without-wallets",  // auto-create a wallet for normies
        // Keep the chain invisible: suppress Privy's built-in tx-confirm modal.
        // Your form's CTA is already the user's confirmation; the popup adds a
        // second "are you sure" tap non-crypto users don't expect and surfaces
        // wallet jargon that contradicts the "no wallet needed" promise.
        // Security is unchanged — the user still explicitly triggered the action.
        // NOTE: showWalletUIs lives HERE (inside embeddedWallets.solana), NOT
        // under `appearance`.
        showWalletUIs: false,
      },
    },
    externalWallets: {
      solana: { connectors: solanaConnectors },   // both audiences, one screen
    },
    solana: {
      // Privy wants a Kit RPC OBJECT per chain you expose — not a URL string.
      rpcs: {
        "solana:mainnet": {
          rpc: createSolanaRpc(MAINNET_RPC),
          rpcSubscriptions: createSolanaRpcSubscriptions(MAINNET_WSS),
        },
      },
    },
  }}
>
  {children}
</PrivyProvider>
```

## The wallet shape your code should depend on

Don't couple your transaction code to a specific provider. Depend on a minimal interface so embedded and external wallets are interchangeable:

```ts
// Sign-only (sponsored/relay path): the server broadcasts, the wallet never needs to.
type SigningWallet = {
  publicKey: PublicKey | null;
  signTransaction: <T>(tx: T) => Promise<T>;
};

// Send-capable (self-funded path): wallet signs AND broadcasts.
type SendingWallet = {
  publicKey: PublicKey | null;
  sendTransaction: (tx, connection) => Promise<string>;
};
```

For the sponsored path you only need `SigningWallet` — Privy fills the user's signature slot, the relay adds the sponsor's. A thin `useWallet()` compatibility shim lets the same call sites work whether the active wallet is Privy-embedded or an attached Phantom.

## Signing — the real flow (hard-won)

Privy's Solana signing hooks take **serialized transaction bytes**, not a transaction object, and return the signed transaction as bytes. The production shim:

```ts
import { useSignTransaction } from "@privy-io/react-auth/solana";

const { signTransaction: privySign } = useSignTransaction();

// Prefer the embedded wallet Privy created on signup; fall back to a connected one.
const wallet = wallets.find((w) => w.standardWallet?.name === "Privy") ?? wallets[0];

// Serialize WITHOUT requiring all signatures — the sponsor (fee payer) slot is
// intentionally empty; the relay fills it. Requiring all sigs here throws.
const serialized = tx.serialize({ requireAllSignatures: false, verifySignatures: false });

const { signedTransaction } = await privySign({
  transaction: new Uint8Array(serialized),
  wallet,
  chain: "solana:mainnet",
});

// Privy returns fully-serialized bytes with the user's signature attached —
// re-deserialize back to your working type before POSTing to the relay.
const userSigned = Transaction.from(signedTransaction);   // or VersionedTransaction.deserialize(...)
```

This API is stack-agnostic (it's just bytes), so it works whether you build the tx with classic web3.js or Kit. For a Kit-native `TransactionSigner` abstraction instead, use `@solana/react` (`createTransactionSignerFromWalletAccount`) — Privy's embedded wallet is a wallet-standard wallet, so it qualifies.

## Supporting both audiences

Offer embedded as the default; let power users attach Phantom/Solflare alongside. Route signing to whichever wallet is active. This keeps the normie path frictionless without locking out crypto-native users.

## Pairs with

- **No SOL?** Embedded-wallet users have 0 SOL by definition → `sponsor-relays.md` + `relay-security.md`.
- **First action needs accounts?** → `transaction-bundling.md`.
