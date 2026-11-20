# CLAUDE.md

Guidance for Claude Code and other coding agents working in this repository. Read
[README.md](README.md) first: it describes the packages, the versioning and the release
flow. This file only adds what an agent gets wrong without being told.

## What is at stake

Every Centreon repository calls these actions through a floating major tag
(`@pulp/v1`). A release reaches every branch of every repository on its next run, with
no review on their side. Treat every change to a package as a production change:

- keep it backward compatible, or make it a major version on purpose;
- cover it with a test before changing it;
- never weaken a check to make a pipeline pass.

The repository is public: nothing confidential in the code, the tests, the commit
messages or the pull request text.

## Layout

- `<package>/`: a top-level directory, versioned and released on its own. It holds one
  or several actions (`action.yml`), their scripts, a `README.md` and `tests/`.
- `.github/scripts/`: the repository's own tooling, with its bats tests.
- `.github/workflows/`: `lint` (every pull request), `release` and `move-major-tag`.

## Checks to run before committing

```shell
.github/scripts/check-actions.sh
shellcheck -x -P SCRIPTDIR -S warning $(git ls-files '*.sh')
npx bats $(git ls-files '*.bats' | xargs -n 1 dirname | sort -u)
uvx jactionlint
uvx zizmor --offline .
prettier --check .
bash .githooks/pre-commit.d/01_gitleaks.sh
```

The last line matters: `.githooks/pre-commit` is not executable in this repository, so
git silently skips the secret scan.

## Rules the lint enforces

- An action never references anything outside its package: no `uses: ./...` (it
  resolves in the caller's workspace), no path climbing out of the package.
- An action calls another action of its package with `uses: $/<package>/<action>`, and
  scripts through `${{ github.action_path }}`.
- Remote actions are pinned to a full commit SHA followed by a `# vX.Y.Z` comment.
- Every script an action runs exists and is executable (`chmod +x`, then commit the
  mode).
- Every package is declared in `release-please-config.json` with its directory name as
  `component`, and has a `README.md`.

## Pull requests and releases

- The pull request title becomes the squash commit and decides the release:
  `fix`, `perf`, `refactor` and `revert` release a patch, `feat` a minor, a `!` a major;
  `docs`, `test`, `ci` and `chore` release nothing. A change to what an action runs
  must carry a releasing type, or callers never receive it.
- A removed or renamed input or output, a new required input, a changed default or a
  behavior a caller can see is a breaking change: it needs the `!`.
- Never create, move or delete a tag, and never edit a `CHANGELOG.md` or
  `.release-please-manifest.json`: release-please owns them.
- Never push to `main`. Work on a branch named after the Jira ticket and open a pull
  request.

## Bash

- `#!/usr/bin/env bash` and `set -euo pipefail` in every executable script; a sourced
  file sets neither. The verification scripts leave `-e` out on purpose: they check
  every package before failing.
- Give every optional environment variable a default (`VAR="${VAR:-}"`): under
  `set -u`, a variable the caller did not pass aborts the script.
- A regex match overwrites `BASH_REMATCH`: read the captures right after the match.
- `grep` returns 1 when nothing matches, which aborts under `pipefail`; use `|| true`
  or a parameter expansion where an empty result is valid.
- Scripts imported from a product repository keep their style: do not reformat them,
  so they stay comparable with their origin.

## Tests

- bats tests live in `<package>/tests/` and replace `curl`, `pulp` or `gh` with a
  stand-in script put first on the `PATH`. See `pulp/tests/check-deb.bats` for the
  pattern.
- Run a script with exactly the environment its `action.yml` step passes
  (`env -i PATH="$PATH" ...`): a variable set by habit in a test hides a missing
  default.
- A stand-in must not answer two endpoints with one pattern: a task href named after
  another endpoint matched the wrong case and made a test loop forever.
- Check that a new test fails without the change it covers.
- Use placeholders, never a real token, credential or customer data.

## Migrating an action from a product repository

1. Compare every copy before choosing one: the same action often exists in several
   repositories, and the copies diverged in both directions.
2. Compare the maintained branches too (`dev-24.10.x`, `dev-25.10.x`, ...), not only
   `develop`: they carry fixes `develop` does not have, and they will call the shared
   action as well.
3. Replace every `./.github/...` path, which would resolve in the caller's repository.
4. An action nested with `uses:` that becomes a script loses the defaults of its
   inputs: give them back to the script.
5. Migrate the local actions a reusable workflow calls before the workflow itself.
6. Prove equivalence: same outputs as the original on a wide set of inputs, then a real
   run from a branch of a calling repository pinned to the commit under review.

## What is not managed here

- `.githooks/`, `.github/CODEOWNERS` and `.github/workflows/secu-*.yml` are pushed by
  the [centreon/Github](https://github.com/centreon/Github) infrastructure code: change
  them there.
- The repository settings (rulesets, roles, shared secrets, merge options) are in the
  same place, in `repos/centreon/github_actions.tf`.
