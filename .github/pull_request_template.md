## Why

<!-- The problem this solves, in the user's words. Link the issue. -->

Fixes #

## What changed

<!-- The effect, briefly. The diff shows the how. -->

## How it was verified

<!-- Tests that pin the behaviour (Swift Testing, state-based). For serve UI changes: before/after screenshots.
     Private-API paths that only a booted simulator can exercise: what you ran by hand. -->

## Checklist

- [ ] A failing `@Test` came first; `swift test` passes
- [ ] `./Injected/build.sh` was run if anything under `Injected/` changed
- [ ] User-visible change: one line under `## [Unreleased]` in `CHANGELOG.md`
- [ ] `make docs && make check-docs` passes
