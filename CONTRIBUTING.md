# Contributing

Cornerlight is a single-owner macOS utility. Issues are disabled, and pull requests are accepted only from collaborators explicitly added to the repository. Everyone else should fork the GPL-3.0 project and use different branding for modified distributions.

Collaborator changes should preserve its KISS boundary: Cornerlight owns app inventory and personal preferences; Spotlight owns the visible launcher.

Before committing:

```sh
./scripts/install-hooks.sh
./verify.sh
```

Requirements:

- derive behavior from [USER_STORIES.md](USER_STORIES.md);
- keep tests headless and non-disruptive;
- add no polling, telemetry, network dependency, persistent app index, or replacement launcher UI;
- treat every private macOS selector as version-pinned to macOS 26.6;
- update `CHANGELOG.md` for every product or release-workflow change.

The tracked pre-commit hook rejects staged product changes without a staged changelog. The pre-push hook runs the full verification suite and validates immutable release metadata for every `vX.Y.Z` tag. CI applies the same changelog rule to the complete pushed or proposed range, so bypassing a local hook does not bypass the repository gate.

After any macOS update, rerun the native contract suite before installing a new build.
