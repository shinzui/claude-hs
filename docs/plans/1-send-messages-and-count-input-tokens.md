---
id: 1
slug: send-messages-and-count-input-tokens
title: "Send messages and count input tokens"
kind: exec-plan
created_at: 2026-11-20T19:36:14Z
master_plan: "docs/masterplans/1-build-a-haskell-client-for-the-claude-messages-api.md"
provenance:
  created_by:
    model: "gpt-6.2-astra"
    harness: "codex-cli"
    at: 2026-11-20T19:36:14Z
  revisions:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T20:25:29Z
      mode: "update"
      note: "Use the Seihou-generated Nix development shell for client builds and tests."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T20:29:05Z
      mode: "implement"
      note: "Implement the client and verify plan acceptance against the locked toolchain."
---

# Send messages and count input tokens

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

A Haskell caller can send a conversation to Claude and estimate its input tokens using one configured client. A test caller exercises the public API against a local HTTP server, including an API failure.

## Progress

- [x] 2026-11-20. Seihou generated the locked flake. The shell reported GHC 9.12.4 and Cabal 3.16.1.0 in the working tree and from a detached clean checkout of the bootstrap commit.
- [x] 2026-11-20. The text roundtrip, Baikai-style session affinity and beta header capture, and HTTP failure fixtures passed.
- [x] 2026-11-20. The count route returned 17 input tokens and the captured history included text, base64 and URL image blocks without an output limit.

## Surprises & Discoveries

The generated formatter rewrote one Seihou-owned Nix file and the next generator preview reported a conflict. See [FRIC-1](../friction-log/1-the-generated-haskell-flake-conflicts-after-its-own-formatter-runs.md).



## Decision Log

2026-11-20 — Adopt the Seihou tooling bootstrap before creating the Cabal library, so the first package build uses the same locked shell as subsequent milestones.



## Outcomes & Retrospective

The locked shell built the library and example, then passed the loopback suite with the Anthropic key unset. The fixture observed one dispatch per operation, including a disconnected POST and redirect. FRIC-1 was accepted with a project-local formatter exclusion that preserves the template baseline. The [HTTP boundary ADR](../adr/0002-scope-credentials-and-response-lifetime-to-the-client.md) records ownership of credentials, the response and retries.



## Context and Orientation

The repository has an existing Seihou manifest for the planning skills and a Mori manifest. The client package and flake are still to be created. The direct consumer is `mori://shinzui/baikai/packages/baikai-claude`, which imports Mercury request types and has its own SSE transport and provider policy. `mori://shinzui/shikumi/packages/shikumi` uses that adapter. `mori://shinzui/shikigami/packages/shikigami-core` relies on governed provider attempts through its program runtime. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-11` requires structured failures for downstream retry decisions. `mori://shinzui/shikumi/okf/adrs/concepts/ADR-14` distinguishes schema enforcement from tool calling. The historical API surface is available at `mori://MercuryTechnologies/claude/packages/claude`. The old default header was 2023-06-01. This package targets the direct API version 2026-10-21. [Version migration guide](https://platform.claude.com/docs/en/api/migration-2026-10-21).

## Plan of Work

Apply the Seihou module from the repository root using the commands below. Track its generated files, including the exact lockfile, the patches to the existing .gitignore and the updated Seihou manifest and baselines. Keep optional project-specific Nix settings in `flake.module.nix`. [Template in Mori](mori://shinzui/seihou-modules/templates/nix-haskell-flake).

Next create `claude-hs.cabal`, `cabal.project`, public modules `src/Claude/Client.hs` and `src/Claude/Messages.hs`, and private `src/Claude/Internal/Http.hs`. Use one Cabal common stanza with GHC2024, DeriveAnyClass, DuplicateRecordFields, OverloadedLabels and OverloadedStrings for all components. Follow `mori://shinzui/haskell-jitsurei/docs/core-standards` and `mori://shinzui/haskell-jitsurei/docs/core-record-patterns`. Use strict record fields, explicit deriving strategies, postpositive qualified imports and generic-lens labels for access and updates. Use explicit wire keys wherever the protocol differs from Haskell naming. Look up each chosen package with Mori, read its source, then check Hackage and upstream tags before setting bounds. Use the same compiler in development and the project's automated build/test job.

Implement a reusable, opaque client with an explicit key, endpoint, timeout and reusable connection manager. Default to https://api.anthropic.com. Permit per-request beta and provider metadata headers so Baikai can pass session affinity. Define a collision policy for library-owned authentication, version and framing headers. Scope credentials to the configured origin. Redact secrets in rendered errors. Disable automatic retries of submitted requests including manager retries on reused connections. Preserve caller cancellation and callback exceptions. Put status checks, request IDs, parsing of the API error envelope, and scoped access to the response body in the internal HTTP module. A single local text roundtrip is the first proof.

Next model user/assistant history, optional system text, text and image input, message ID, ordered response blocks, stop reason and usage. Allow a new model ID as text and retain unknown tagged response blocks as JSON. Use required arguments or validated constructors for model, nonempty conversation and positive output limit. Build a separate count request from shared input fields and verify its endpoint-specific body. Add a small compilable usage example and transport setup instructions in README.md. [Create a Message](https://platform.claude.com/docs/en/api/messages/create) and [Count tokens](https://platform.claude.com/docs/en/api/messages/count_tokens).

## Concrete Steps

With Nix flakes and Seihou available, run this initial bootstrap from the repository root. If the module is missing, install it first with the following command.

```bash
seihou install https://github.com/shinzui/seihou-modules.git --module nix-haskell-flake
```

Preview and apply the same inputs. The preview should include flake.nix, flake.lock, nix/haskell.nix, treefmt, pre-commit, fourmolu.yaml and .envrc. Resolve any conflicts with existing project files before applying.

```bash
flake_args=(
  nix-haskell-flake
  --var project.name=claude-hs
  --var 'project.description=Haskell client for the Anthropic Claude Messages API'
  --var ghc.version=ghc9124
  --var nix.process-compose=false
  --var nix.postgresql=false
)
seihou run "${flake_args[@]}" --dry-run
seihou run "${flake_args[@]}"
```

Stage the generated flake inputs so Git-backed Nix can see them. Verify the locked shell reports GHC 9.12.4 and a Cabal version. Repeat these checks from a clean checkout of the bootstrap commit.

```bash
nix develop --no-write-lock-file -c ghc --numeric-version
nix develop --no-write-lock-file -c cabal --numeric-version
```

From the repository root, build and test each client milestone in the locked development shell provided by EP-1. See the [tooling ADR](../adr/0001-bootstrap-haskell-tooling-with-seihou.md). The library must build and the local test suite must report PASS with no Anthropic key in the environment.

```bash
nix develop --no-write-lock-file -c cabal build all
nix develop --no-write-lock-file -c cabal test all --test-show-details=direct
```

## Validation and Acceptance

Use a loopback server in `test/Support/Server.hs` and register `test/MessagesSpec.hs` from `test/Main.hs`. Assert method, path, API key sentinel, exact version and omitted optional fields. POST /v1/messages must return the fixture's text, model, stop reason and input/output counts. For POST /v1/messages/count_tokens return 17 input tokens, inspect the supplied history and assert the output limit is absent. Cover a non-JSON 502, a 429 with request ID and Retry-After, invalid JSON on HTTP 200, an unknown block and a disconnected POST. Observe one attempt, differentiated errors, and secret-free diagnostics. The complete request fixture omits temperature, top_p and top_k under the selected version. Compile a narrow Baikai-style request mapping with the public package, including provider session headers, before extending endpoint coverage. Check the captured request and header values.

## Idempotence and Recovery

Use ephemeral loopback ports and bracket server lifetime per test. A failed fixture run is safe to repeat. Leave retry timing and the decision to repeat a billable call to the downstream runtime.

## Interfaces and Dependencies

Expose createMessage and countTokens as Client plus typed request to IO (Either ClientError result). Keep successful response metadata available, including request ID. Distinguish transport, API status/envelope and protocol decode errors. Model a refusal stop separately from HTTP failure. The internal runner takes a method, endpoint path, request options/body and a scoped reader callback. Keep Aeson codecs shared between Messages, streaming and batches. No prerequisite child.
