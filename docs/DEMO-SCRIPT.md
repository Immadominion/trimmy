# Demo video, 2:20

Every command below was checked against the code that runs it, not written from
memory. Where a step cannot be done live in the time, that is said rather than
faked.

## Read this first: two things that decide the shape of the video

**1. All four rules on the contract are `[finished]`.** There is nothing live
for a keeper to fire, and `trimmy.xyz/rules/` currently shows four spent rules.
You have to arm a fresh one, and it has to happen before you press record.

**2. Arming cannot be shown end to end in real time.** The XRPL payment has to
settle, then FDC has to attest it in a voting round. Measured: **p50 131
seconds, p95 170 seconds** from XRPL validation to FXRP minted. That is most of
your 140 second budget spent watching a terminal.

So the video has exactly one cut, at the FDC wait, and you say what the cut is.
An unexplained jump looks like something was hidden; a narrated one ("this takes
about two minutes, here it is arriving") looks like a person who knows their own
system.

---

## Before you press record

Open two terminals. Both need the environment loaded.

```bash
cd ~/Documents/codes/opensauce/flare/trimmy
source ~/.flare-dart/xrpl-testnet.env     # XRPL_TEST_SEED, XRPL_TEST_ADDRESS
source ~/.flare-dart/coston2-test.env     # COSTON2_TEST_KEY, COSTON2_TEST_ADDRESS
export TRIMMY_ADDRESS=0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C
```

### Step 0, arm a rule that has runs left

`arm.dart` arms a vault deposit on a 60 second schedule. `--runs 6` is what
gives the keeper something to fire more than once, so the rule is still live
when you get to the keeper shot.

```bash
cd arming
dart run bin/arm.dart --xrpl $XRPL_TEST_ADDRESS --runs 6
```

It prints the 42-byte memo and the user-operation pre-image, and writes them to
`out/`. Copy the memo.

```bash
cd xrpl
node send.mjs --memo <the-84-hex-memo> --amount-xrp 8 --dry-run   # check first
node send.mjs --memo <the-84-hex-memo> --amount-xrp 8             # then send
```

`--dry-run` first, always. This payment is irreversible, and `send.mjs` refuses
rather than sends if the memo is not exactly 42 bytes, does not start with
`0xFE`, or the amount does not clear the live fee floor.

Now wait. Check it landed:

```bash
curl -s https://trimmy.xyz/rules/ >/dev/null && open https://trimmy.xyz/rules/
```

When a fifth rule appears and reads **live** rather than finished, you are ready
to record. If no public executor picks it up within a few minutes:

```bash
cd ~/Documents/codes/opensauce/flare/trimmy
python3 tools/execute_arming.py --xrpl-tx <tx-hash> --preimage-file arming/out/preimage-v4.hex
```

### Step 1, confirm the keeper has work

Do this before recording so you know the shot will land.

```bash
cd keeper
dart run bin/keeper.dart --once
```

If it executes, good, that is proof the path works. Arm again with `--runs 6` so
there is still something to fire on camera. If it says nothing is eligible, the
rule's next window has not opened yet, which is the 60 second interval.

---

## The shot list

Total 2:20. Times are cumulative.

### 0:00 to 0:18, the problem

**Screen:** trimmy.xyz, top of the page.

> "If you hold XRP and you want to sell when it drops, you have two options.
> Watch the chart yourself, or give your keys to somebody who will. The first
> one does not work while you are asleep. This is a third option."

Scroll once, slowly, so the headline and the rule card are both seen.

### 0:18 to 0:45, an agent composes the rule

**Screen:** Claude Desktop, or any MCP client with the Trimmy server connected.

Type:

> "What rules do I have on Trimmy, and compose one that deposits into the vault
> every hour, twelve times."

**Say:**

> "Trimmy ships an MCP server. Four tools, all read only. The assistant can read
> what is armed and compose a new rule, and what it hands back is a payment for
> me to sign. It cannot sign and it cannot send. Watch what happens if I ask it
> to handle a secret price."

Then type:

> "Set the threshold to 150 on a private rule."

**Say, over the refusal:**

> "It refuses. A threshold that reaches an agent is a threshold that has left
> the enclave."

That refusal is the single best twenty seconds in this video. It is the whole
"AI-friendly, still not in charge" argument, demonstrated instead of claimed.

### 0:45 to 1:12, one signature

**Screen:** terminal, the two commands from Step 0.

**Say:**

> "One payment, from my own XRPL account, in a wallet I already have. The memo
> is 42 bytes and it is the only thing that decides what happens on Flare. The
> sender refuses if it is the wrong length, if it has a destination tag, or if
> the amount is inside the dead zone where FAssets delivers exactly zero and the
> protocol's own warning flag stays false. We found that one by losing money to
> it."

Show the `--dry-run` output, then the real send, then the XRPL transaction hash.

### 1:12 to 1:25, the cut

**Say, over the wait:**

> "FDC now proves that payment happened. That takes about two minutes, so here
> it is arriving."

Cut to `trimmy.xyz/rules/` with the new rule showing **live**.

### 1:25 to 1:55, it fires without you

**Screen:** terminal, split with the rules page if you can.

```bash
cd keeper && dart run bin/keeper.dart --once
```

**Say:**

> "Nobody is logged in now. The keeper is permissionless, anyone can run it, and
> it is paid a fee the rule itself carries. It simulates first, so a rule that
> would revert costs a round trip instead of gas. My key is not involved. If
> this keeper key leaked tomorrow, the attacker gains nothing the public does
> not already have, because every bound is re-derived on chain."

Refresh `/rules/`. Show the run count drop and the progress bar move.

### 1:55 to 2:20, the close

**Screen:** `/rules/`, scrolled to the two `cast` commands.

**Say:**

> "That page has no backend. It reads the contract from your browser, and these
> two commands reproduce it without me. Every number in the documentation has
> the command that produced it recorded next to it. Trimmy is one XRPL payment
> that leaves behind a rule that keeps working after you stop."

End on trimmy.xyz.

---

## If it goes wrong on camera

- **Keeper says nothing is eligible.** The 60 second window has not opened. Wait
  it out or cut. Do not re-arm mid take.
- **The rule never appears.** No public executor picked it up. Run
  `tools/execute_arming.py`. This is a known Coston2 behaviour, not a bug in
  Trimmy: executors skip what they earn nothing on.
- **`send.mjs` refuses.** Read the message; it is refusing for one of three
  specific reasons and all three are real. Do not work around it.

## What not to claim

- Do not say "non-custodial" and leave it there. Say what is checked and where.
- Do not present a private rule as trustless. It needs one enclave to be
  running, and its operator can censor it by declining to act. The other three
  triggers are permissionless. That difference is in the docs and should stay in
  your mouth too.
- Do not call the schedule trigger new. XRPL Escrow has done non-custodial time
  locks through `FinishAfter` for years. What is new is that the money then does
  something, and that nobody has to be online when it comes due.
