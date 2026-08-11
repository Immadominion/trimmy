# trimmy-mcp

**Let an agent compose a rule over someone's XRP that it cannot spend.**

Every agentic wallet reaches for the same shape: give the agent a bounded permission instead of the
keys. Botwallet does it with spending limits and co-signing, Phantom with rules set in advance, Cobo
with Pacts, MoonPay by splitting the key with MPC. In all of them the bound lives in the vendor's
infrastructure, so the agent's authority is exactly as durable as that company's servers.

A Trimmy rule is the same bound, enforced by a contract:

- the allowance is **exact**, sized to the rule, never unlimited
- the action, the venue and the token pair are fixed in the constructor and no code path changes them
- the budget and the expiry are fixed when the rule is armed
- one write to `epoch` cancels every rule on the account
- `PersonalAccount.executeUserOp` is `onlyController`, so **a compromised agent extracts zero**

This server exposes that as MCP tools.

## The two things it cannot do

**It cannot sign or send.** `trimmy_compose_rule` returns fields for a human to enter in their own
XRPL wallet. There is no signing tool, no key, and no broadcast path.

**It cannot learn a private rule's threshold.** This one shaped the design. A `PRIVATE` rule's
threshold is encrypted to the enclave, so whoever builds that payload holds the number in plaintext
for a moment. If that were the agent, "the agent never learns your price" would be false. So
`trimmy_compose_rule` **refuses a threshold argument for private rules outright** and returns the
provisioning command for the person to run themselves. The agent composes the shape of the mandate;
the number travels from the person to the enclave without passing through the model.

Accepting it and promising not to look would be more convenient and would make the product's best
claim a lie.

Both guarantees are enforced by [`test/readonly_test.dart`](test/readonly_test.dart), which
enumerates the tool list, asserts the read-only annotations, greps this package for the realistic
routes to spending (`sendRawTransaction`, `Platform.environment`, `File`, `Process`), and drives the
private-threshold refusal through a client factory that throws, proving the refusal happens *before*
any network work rather than after.

## Install

```jsonc
{
  "mcpServers": {
    "trimmy": { "command": "dart", "args": ["run", "trimmy_mcp:trimmy-mcp"] }
  }
}
```

## Tools

| Tool | Reads the chain | What it does |
| --- | --- | --- |
| `trimmy_check_address` | no | Verifies an XRPL address against its own four byte checksum, offline |
| `trimmy_list_rules` | yes | Every rule armed on the contract, with status and remaining budget |
| `trimmy_describe_rule` | yes | One rule in full |
| `trimmy_compose_rule` | yes | Builds the payment a human then signs themselves |

`trimmy_check_address` needs no network on purpose. Flare derives a personal account from the
address **string** and the derivation never fails: one changed character yields a different, valid
looking account the sender does not control, there is no on-chain check that catches it, and the
XRPL payment cannot be recalled. A check that needs the network is a check that fails open when the
network is down, and this one guards an irreversible payment.

## What a session looks like

```
> sell half an XRP twice if the price drops, and keep my price private

  trimmy_check_address  -> OK, rDE4JUm2... passes its own checksum
  trimmy_compose_rule   -> Composed. Nothing has been sent, and this server cannot send it.

                           Amount      : 1.2 XRP
                           Memo (hex)  : FE0000000000000186A050851F8B00...

                           1. Allow Trimmy to move at most 1.0188 FXRP. Exact, not unlimited.
                           2. Arm a rule: sell on a market, 0.5 FXRP at a time, up to 2 times,
                              a private price held inside the enclave.

                           The threshold is NOT in the payment above and is not known to this
                           conversation. Run this yourself after the rule is armed:
                             cd fcc/extension/tools && go run ./cmd/trimmy-private ...
```

Pass a threshold for a private rule and the tool refuses, before it reads anything.

## Scope

Flare **Coston2 testnet**. Nothing here has run on Flare mainnet, and the XRP in these flows is
testnet XRP.

The JSON-RPC layer (`src/protocol.dart`, `src/transport.dart`) is copied from
[Plimsoll's MCP server](https://github.com/Immadominion/plimsoll) rather than shared, so the two
repositories stay independent. MCP is a JSON-RPC loop over two pipes; a framework would add a supply
chain to a process an agent consults before a person signs something irreversible.
