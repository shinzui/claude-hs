---
type: Friction Entry
title: "Baikai's Hackage dependency source cannot resolve claude-hs"
description: "Hackage has no claude-hs release and Cabal rejects uploads without a package license."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T22:48:49Z"
frictionId: FRIC-3
status: logged
impact: blocked
kind: environment
origin: "mori://shinzui/claude-hs"
affects: "https://hackage.haskell.org/"
affectedVersion: "unreleased"
plan: "docs/plans/8-remove-the-mercury-claude-dependency-from-baikai.md"
workaround: "Run the pinned provider and cohort trials with an explicit local source while awaiting the release decision."
---
# Baikai's Hackage dependency source cannot resolve claude-hs

## Attempted

Check the normal package source and first-release eligibility using the Hackage package JSON endpoint and cabal check.

## Encountered

The claude-hs package endpoint returned HTTP 404. Cabal reported license-none and that Hackage would reject the package.

## Workaround

Run the pinned provider and cohort trials with an explicit local source while awaiting the release decision.
