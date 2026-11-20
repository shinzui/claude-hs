# Downstream Claude HTTP trial

The trial switches the live Messages driver of `mori://shinzui/baikai/packages/baikai-claude` to the local `claude-hs` package. Baikai still shapes the provider request, decides which API version and beta headers to send, projects decoded events into its assembler and accounts for timeouts and cancellation at its existing boundary. The bridge retains original event JSON for Mercury event types still used by that assembler. The recorded patch retains Baikai's explicit manager-injection helper for its raw response fixtures and low-level callers.

The downstream cohort follows the Cabal project at `mori://shinzui/shikigami/repos/shikigami`.

| Repository | Revision | Selected packages |
|---|---|---|
| `mori://shinzui/baikai/repos/baikai` | `cdb79e5805613ab60074bb2c9279d779af610c05` | Baikai core 0.10.1.0 and Claude and OpenAI adapters 0.7.3.0 |
| `mori://shinzui/shikumi/repos/shikumi` | `4fec9169d97a85f5e0e38246347f6c70ef555d7e` | Shikumi 0.5.1.0 |
| `mori://shinzui/shikigami/repos/shikigami` | `d9d18d23b456f25a6b507a60514bcd90e796392b` | Shikigami core 0.1.0.0 |

Each patch applies to its named checkout using `git apply`. Prepare a fresh trial from the client repository with the three upstream source repositories available through Mori.

```bash
trial_project=$(bash integration/consumers/prepare.sh)
cd "$trial_project"
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u SHIKUMI_LIVE \
  cabal test baikai-claude:test:baikai-claude-test shikumi:test:shikumi-test \
  shikigami-core:test:shikigami-core-test --test-show-details=direct --test-options='--num-threads=1 +RTS -N4 -RTS' -j8
```

The trial uses Shikigami's locked GHC 9.12.4 development shell with its native libraries. The selected suites use loopback fixtures with synthetic keys. The Cabal project keeps the upstream Hackage index-state, constraints and source pins. Verify in `dist-newstyle/cache/plan.json` that the local Baikai Claude library depends on `claude-hs-0.1.0.0-inplace`. [Resolved Cabal components](resolved-cohort.json)

The focused fixtures are the Baikai candidate HTTP tool rounds and cancellation, the Shikumi typed prediction and structured 429, and the Shikigami governed attempts. Use each suite's Tasty `-p` filter to replay them.

```bash
nix develop --no-write-lock-file -c cabal test baikai-claude:test:baikai-claude-test \
  --test-show-details=direct --test-options='-p candidate --num-threads=1 +RTS -N4 -RTS'
nix develop --no-write-lock-file -c cabal test shikumi:test:shikumi-test \
  --test-show-details=direct --test-options='-p candidate --num-threads=1 +RTS -N4 -RTS'
nix develop --no-write-lock-file -c cabal test shikigami-core:test:shikigami-core-test \
  --test-show-details=direct --test-options='-p candidate --num-threads=1 +RTS -N4 -RTS'
```

For the direct 2026-10-21 API use the client default and audit removed sampling parameters. Existing Baikai calls retain their explicit 2023-06-01 version during this trial, including legacy sampling settings and empty histories. The HTTP transport owns authentication, version and framing headers after Baikai resolves their values. Additional provider metadata such as session affinity passes through the trial driver.

## Results

Fresh checkouts passed 475 Baikai tests and 301 Shikumi tests. Shikigami passed 820 tests with serial Tasty scheduling. The governed fixture recorded one attempt per wire dispatch on success, terminal HTTP failure and cancellation. Success retained the provider request ID and cached token counts. Terminal failure retained its request ID. Cancellation recorded an unknown terminal and closed the socket.

Running the full Shikigami suite with multiple Tasty workers hit local HTTP fixture deadlines. The serial setting is recorded in [FRIC-2](../../docs/friction-log/2-concurrent-shikigami-fixture-deadlines-expire-during-the-consumer-trial.md).

## Mercury parity projections

In a disposable checkout of `mori://shinzui/baikai/repos/baikai` at
`87481ea7ff867a37bf602b0dc1ac8caa9e2e2710`, apply
[`baikai.patch`](baikai.patch) followed by
[`baikai-parity-projections.patch`](baikai-parity-projections.patch).
Add the candidate directory as a Cabal package in `cabal.project.local`.

```bash
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u ANTHROPIC_KEY \
  cabal test baikai-claude:test:baikai-claude-test --test-show-details=direct \
  --test-options='-p candidate --num-threads=1 +RTS -N4 -RTS' -j8
```

The request comparison covers empty legacy history, legacy sampling, native
schema output and two current-version errors before dispatch. The stream
comparison covers refusal details and cumulative usage alongside speed and
service tier. Five selected cases passed, including the three transport fixtures.

## Mercury-free migration trial

Prepare both cohorts with the same Baikai, Shikumi and Shikigami revisions
from the parity plan. Both select local Baikai 0.10.1.1, Baikai Claude
0.7.3.0 and Baikai OpenAI 0.7.3.1. The migrated project removes the exact
`claude` pin and its TLS override.

```bash
baseline=$(bash integration/consumers/prepare-parity.sh baseline)
migrated=$(bash integration/consumers/prepare-parity.sh migrated)
```

Run from each generated Shikigami root. The local candidate is the checkout
that supplied the script, so use the same committed candidate for both runs.

```bash
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u ANTHROPIC_KEY -u SHIKUMI_LIVE \
  cabal test baikai-claude:test:baikai-claude-test shikumi:test:shikumi-test \
  shikigami-core:test:shikigami-core-test --test-show-details=direct \
  --test-options='--num-threads=1 +RTS -N4 -RTS' -j8
```

From the migrated root, confirm the solver selects the candidate through the
provider library and omits Mercury.

```bash
jq -e 'all(."install-plan"[]; ."pkg-name" != "claude")' dist-newstyle/cache/plan.json
jq -e 'any(."install-plan"[]; ."pkg-name" == "claude-hs" and ."pkg-src".type == "local")' \
  dist-newstyle/cache/plan.json
jq -e 'any(."install-plan"[]; ."pkg-name" == "baikai-claude" and ."component-name" == "lib" and
  any(.depends[]; startswith("claude-hs-0.1.0.0-")))' dist-newstyle/cache/plan.json
```

The [migration patch](baikai-migration.patch) builds the provider, request
mapper and stream assembler against `claude-hs`. It exercises redirects,
cancellation, malformed frames, signed reasoning and independent legacy
and current sampling behavior through the public Baikai paths.

### Compare requests and evidence

Apply [the probe patch](baikai-wire-probe.patch) to each prepared Baikai
checkout. Run the full provider suite from both Baikai roots in their locked
shells. Save the output from each run.

```bash
nix develop --no-write-lock-file -c env -u ANTHROPIC_API_KEY -u ANTHROPIC_KEY \
  cabal test baikai-claude:test:baikai-claude-test --test-show-details=direct \
  --test-options='--num-threads=1 +RTS -N4 -RTS' -j8 > wire.log
sed -n 's/.*PARITY_WIRE //p' wire.log | jq -sS 'sort_by(.case)' > wire.json
```

The five [recorded snapshots](baikai-wire-parity.json) matched as JSON
across both builds. They cover schema-only and named tool choice, cached
and sampled prompts, and both signed and redacted tool rounds. The first
four also matched the request, configuration and response commitments.

### Results

The migrated cohort passed all 475 Baikai, 301 Shikumi and 820 Shikigami
tests. The prepared patch reapplied in fresh checkouts, and the Baikai
provider suite passed again in the copied Baikai project's own shell.
Shikumi retained the structured 429, and Shikigami recorded one attempt
per dispatch on success, terminal failure and cancellation.
[Resolved Cabal components](resolved-mercury-parity.json)

### Adoption gate

Baikai's checked-in dependency source is Hackage. The final adoption check
requires a published `claude-hs` package and a fresh Baikai checkout of the
adoption commit. Hackage returned 404 for `claude-hs`, and `cabal check`
reported that its missing license blocks the release. The local
`cabal.project.local` used here is specific to the pinned trial.
