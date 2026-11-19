# github-actions

Shared GitHub Actions used by Centreon CI workflows.

The repository is a set of **packages**: a package is a top-level directory, versioned
and released on its own, that holds one action or several actions built on the same
code.

| Package         | Actions                                                             |
| --------------- | ------------------------------------------------------------------- |
| [`pulp`](#pulp) | `pulp/package-delivery`, `pulp/promote-to-stable`, `pulp/setup-cli` |

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

| Change to a package                                                                            | Pull request title           | Release |
| ---------------------------------------------------------------------------------------------- | ---------------------------- | ------- |
| Removed or renamed input/output, new required input, changed default or behavior a caller sees | `feat(pulp)!: …` (or `fix!`) | major   |
| New action, new optional input or output                                                       | `feat(pulp): …`              | minor   |
| Bug fix, pinned dependency bump, performance                                                   | `fix(pulp): …`, `perf: …`    | patch   |
| Refactoring, documentation, tests, CI                                                          | `refactor:`, `docs:`, `ci:`… | none    |

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

## Adding or changing an action

- Put a new action in an existing package when it shares code with it, otherwise create
  a package: a top-level directory, declared in `release-please-config.json` with its
  directory name as `component`.
- An action is self-contained in its package: no `uses: ./...` (that path resolves in
  the caller's workspace) and no path leaving the package. Shared logic lives in
  scripts called through `${{ github.action_path }}`, so all files come from the same
  release, on any runner version.
- Remote actions are pinned to a full commit SHA with a `# vX.Y.Z` comment.
- Shell scripts follow shellcheck; test them with
  [bats](https://github.com/bats-core/bats-core) in `<package>/tests/`.

The `lint` workflow enforces all of this on every pull request, with the title format,
a run of `pulp/package-delivery` up to the repository layout, and two linters of the
workflows and actions: [jactionlint](https://jactionlint.jdx.dev) (validity) and
[zizmor](https://docs.zizmor.sh/) (security). Run the checks locally with:

```shell
.github/scripts/check-actions.sh
shellcheck -x -P SCRIPTDIR $(git ls-files '*.sh')
npx bats pulp/tests .github/scripts/tests
uvx jactionlint
uvx zizmor --offline .
```

## pulp

Delivery of rpm/deb packages to the Pulp repositories.

| Action                   | Purpose                                                                                       |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| `pulp/package-delivery`  | Deliver rpm/deb packages from the actions cache to an unstable, testing or feature repository |
| `pulp/promote-to-stable` | Promote testing packages to the stable repository                                             |
| `pulp/setup-cli`         | Install pulp-cli and authenticate with a GitHub OIDC token                                    |

`pulp/lib` holds their shared scripts (repository layout, REST api, manifest,
post-delivery checks); it is not an action.

Requirements of the calling job:

- `permissions: id-token: write` (OIDC authentication to Pulp).
- An internal runner: the Pulp api is not reachable from GitHub-hosted runners.
- An OIDC rule for the calling repository in the Pulp configuration.
- Inputs `pulp_url`, `pulp_content_url` and `audience` wired from the `PULP_API_URL`,
  `PULP_CONTENT_URL` and `PULP_OIDC_AUDIENCE` organization variables.

`repository_name` selects the repository family: `standard`, `standard-internal`,
`business`, `business-internal`, `plugins` or `connectors`.

```yaml
deliver-pulp:
  runs-on: centreon-ubuntu-26.04-small
  permissions:
    contents: read
    id-token: write
  steps:
    - uses: centreon/github-actions/pulp/package-delivery@pulp/v1
      with:
        module_name: centreon-web
        distrib: el9
        version: "26.10"
        cache_key: ${{ github.sha }}-${{ github.run_id }}-rpm-el9
        stability: testing
        release_type: release
        is_cloud: "false"
        pulp_url: ${{ vars.PULP_API_URL }}
        pulp_content_url: ${{ vars.PULP_CONTENT_URL }}
        audience: ${{ vars.PULP_OIDC_AUDIENCE }}
```

## Repository settings

Kept outside the code, set by a repository admin:

- **Release app**: a GitHub App installed on this repository only, with `contents`,
  `pull-requests` and `issues` write access; its client id in the
  `RELEASE_APP_CLIENT_ID` variable and its private key in the `RELEASE_APP_PRIVATE_KEY`
  secret of the `release` environment.
- **`release` environment**: deployment branches limited to `main`.
- **`Release tags` ruleset**: the release app is the only bypass actor, so no one else
  can create, move or delete a tag.
- **Immutable releases**: enabled, so a published `<package>/vX.Y.Z` release and its tag
  cannot change (floating tags carry no release and stay movable by the app).
- **Squash merge commit title**: "Pull request title", so the title checked by `lint`
  is the commit release-please reads.
- **Required status check**: `lint` on `main`.
