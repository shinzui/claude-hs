---
type: Friction Entry
title: "Concurrent Shikigami fixture deadlines expire during the consumer trial"
description: "The comprehensive runtime suite hit local HTTP fixture deadlines under concurrent execution, despite passing when Tasty scheduled one test at a time."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T20:59:36Z"
frictionId: FRIC-2
status: "accepted"
impact: detour
kind: environment
origin: "mori://shinzui/claude-hs"
affects: "mori://shinzui/shikigami/packages/shikigami-core"
affectedVersion: "0.1.0.0"
plan: "docs/plans/5-verify-the-client-through-baikai-shikumi-and-shikigami.md"
workaround: "Run the full suite with Tasty --num-threads=1 and keep RTS -N4. All 820 tests passed."
resolution: "Use one Tasty worker for the full trial suites while retaining four RTS capabilities."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-20T21:01:35Z"
    change: "The complete Shikigami suite passes with serial fixture scheduling."
---
# Concurrent Shikigami fixture deadlines expire during the consumer trial

## Attempted

Run the pinned Shikigami core suite from the candidate Cabal project with the default Tasty worker count and RTS -N4.

## Encountered

Twenty-five of 820 tests failed, mostly reporting decision provider attempt timed out. The three new governed Claude cases passed.

## Workaround

Run the full suite with Tasty --num-threads=1 and keep RTS -N4. All 820 tests passed.
