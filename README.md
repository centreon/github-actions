# github-actions

Shared GitHub Actions used by Centreon CI workflows.

The repository is a set of **packages**: a package is a top-level directory, versioned
and released on its own, that holds one action or several actions built on the same
code. Each package documents its actions in its own `README.md`.

| Package                  | Actions                                                             |
| ------------------------ | ------------------------------------------------------------------- |
| [`pulp`](pulp/README.md) | `pulp/package-delivery`, `pulp/promote-to-stable`, `pulp/setup-cli` |

## Usage

Reference an action by its path and the major tag of its package:

```yaml
- uses: centreon/github-actions/pulp/package-delivery@pulp/v1
```

- `<package>/v1` always points at the latest `1.y.z` release of the package: fixes and
  new optional features reach every branch of every repository without any change
  there.
- A new major (`<package>/v2`) is opt-in: change the tag, branch by branch, after
  reading its release notes. The previous major stays where it was and gets no
  further release.
- To freeze a branch, reference an exact release: `@pulp/v1.4.2` (never moved) or its
  commit SHA.

The tag carries the package name because a ref applies to the whole repository: a
plain `@v1` would give every action the same version, and a breaking change in one
package would force all the others to a new major.

In the calling repository:

- allow `centreon/github-actions` in the SHA pinning check, as for
  `centreon/security-tools`;
- make Dependabot ignore it, the major tag already brings the updates:

  ```yaml
  # .github/dependabot.yml
  - package-ecosystem: github-actions
    directory: "/"
    ignore:
      - dependency-name: "centreon/github-actions*"
  ```

## Versioning and releases

Each package follows [Semantic Versioning](https://semver.org/). Releases are made by
[release-please](https://github.com/googleapis/release-please) from the titles of the
pull requests merged on `main` (squash merge, so the title is the commit):

| Change to a package                                                                            | Pull request title                  | Release |
| ---------------------------------------------------------------------------------------------- | ----------------------------------- | ------- |
| Removed or renamed input/output, new required input, changed default or behavior a caller sees | `feat(pulp)!: …` (or `fix!`)        | major   |
| New action, new optional input or output                                                       | `feat(pulp): …`                     | minor   |
| Bug fix, pinned dependency bump, performance, refactoring, revert                              | `fix`, `perf`, `refactor`, `revert` | patch   |
| Documentation, tests, CI, chores                                                               | `docs`, `test`, `ci`, `chore`       | none    |

Anything that changes what an action runs needs a releasing type, or callers never get
it: `docs`, `test`, `ci` and `chore` changes to a package only ship with its next
release.

A commit counts for the packages whose directory it changes.

1. A pull request with a releasing title is merged on `main`.
2. release-please opens, or updates, the release pull request of each changed package
   (`chore(main): release pulp 1.2.0`): version bump and `<package>/CHANGELOG.md`.
   Several changes can accumulate in it.
3. Merging the release pull request creates the `<package>/v1.2.0` tag and its GitHub
   release, then moves the floating `<package>/v1` tag to it: callers get the release
   on their next run.

Nothing reaches the callers before step 3: the release pull request is the moment to
decide that `main` is good to ship.

### Testing a change before its release

Reference the commit of the pull request from a branch of a calling repository, and
run the workflow there:

```yaml
- uses: centreon/github-actions/pulp/package-delivery@<commit-sha>
```

### Rolling back a release

A release reaches every caller at once. If it breaks them, run the `move-major-tag`
workflow with the previous release (for example `pulp/v1.4.1`): the major tag points
back at it within seconds. Then fix or revert on `main`; the next release moves the
tag forward again.

The same workflow repairs a release whose tag was created but whose major tag was not
moved (a failed `release` run): give it the new release.

## Adding or changing an action

- Put a new action in an existing package when it shares code with it, otherwise create
  a package: a top-level directory with a `README.md`, declared in
  `release-please-config.json` with its directory name as `component`, and listed in
  the table above.
- An action is self-contained in its package: no `uses: ./...` (that path resolves in
  the caller's workspace) and nothing referenced outside the package. It calls another
  action of its package with `uses: $/<package>/<action>` and shared scripts through
  `${{ github.action_path }}`: both resolve to the commit of the release in use.
  `$/` needs a runner 2.336.0 or newer.
- Remote actions are pinned to a full commit SHA with a `# vX.Y.Z` comment.
- Shell scripts follow shellcheck; test them with
  [bats](https://github.com/bats-core/bats-core) in `<package>/tests/`.

The `lint` workflow enforces all of this on every pull request, with the title format,
a run of `pulp/package-delivery` up to the repository layout, and two linters of the
workflows and actions: [jactionlint](https://jactionlint.jdx.dev) (validity) and
[zizmor](https://docs.zizmor.sh/) (security). Run the checks locally with:

```shell
.github/scripts/check-actions.sh
shellcheck -x -P SCRIPTDIR -S warning $(git ls-files '*.sh')
npx bats $(git ls-files '*.bats' | xargs -n 1 dirname | sort -u)
uvx jactionlint
uvx zizmor --offline .
```

## Repository settings

The settings of this repository are code too, in
[centreon/Github](https://github.com/centreon/Github) (`repos/centreon/github_actions.tf`);
change them there, not in the GitHub interface.

- **Release token**: the token of the `technique-ci` account, which opens the release
  pull requests and pushes the tags, is the `CENTREON_TECHNIQUE_PAT` secret of the
  `release` environment. Only `main` may use that environment, so the workflow of another
  branch never receives the token. Its value is set by hand on the environment, and the
  organization secret of the same name must not be shared with this repository. The
  `release` workflow does nothing without it.
- **`Release tags` ruleset**: only `technique-ci` and the organization admins may create,
  move or delete a tag.
- **Squash merge commit title**: the pull request title, so the title checked by `lint`
  is the commit release-please reads.
- **Required status check**: `lint` on `main`.
- **Immutable releases** (set by hand, not managed as code): a published
  `<package>/vX.Y.Z` release and its tag cannot change; the floating tags carry no
  release and stay movable.
