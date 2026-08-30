# Testing

Cornerlight turns the product stories in [USER_STORIES.md](USER_STORIES.md) into Swift Testing contracts. The suite covers catalog enumeration, filtering, recents, pins, hiding, settings, Hot Corner state, native Spotlight adapters, transition serialization, and focus-lifecycle ownership.

## Run tests

```sh
swift test
./verify.sh
```

`Tools/test-build-workflow.sh` replaces external build tools with deterministic fakes and verifies stable signing selection, hardened distribution signing, staged promotion, live-target refusal, and opt-in launch behavior. `Tools/test-release-workflow.sh` exercises changelog failures, immutable tag metadata, release-note extraction, and the required signing/notarization/publication boundaries. `Tools/test-visual-tools.sh` verifies only the framebuffer comparison utility.

## Deliberate automation boundary

Tests may instantiate Spotlight's controller hierarchy offscreen, but they must not:

- order the real panel onscreen;
- activate Cornerlight;
- move or inspect the pointer for automation;
- synthesize keyboard or mouse input;
- change the user's Hot Corner or privacy settings.

Real WindowServer placement, animation, keyboard handoff, Input Monitoring persistence, and app execution are owner-acceptance checks in [TODO.md](TODO.md).

## Adding behavior

Add or amend the user story first, then add the smallest headless test that proves it. If a behavior belongs to Spotlight's native UI, test the adapter contract rather than creating a parallel UI implementation.
