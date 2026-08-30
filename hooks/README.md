# Git hooks

`pre-commit` runs the quick verifier. `pre-push` runs the complete verifier. Install both by setting this repository's tracked hook path:

```sh
./scripts/install-hooks.sh
```

The hooks never launch Cornerlight or take focus.
