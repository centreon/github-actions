# github-actions

Shared GitHub Actions used by Centreon CI workflows.

## Usage

Reference an action by its path and the floating major tag of that action:

```yaml
- uses: centreon/github-actions/pulp/package-delivery@pulp-package-delivery-v1
```

- `<action>-v1` always points at the latest `1.y.z` release of that action: fixes and
  new optional features reach every branch of every product repository without any
  change there, including maintained branches.
- A new major version (`<action>-v2`) is opt-in: move to it by changing the tag, once
  per branch, after reading its release notes.
- Pin an exact release only when a branch must not move:
  `@pulp-package-delivery-v1.4.2` (immutable) or the SHA of that tag.

Keep Dependabot away from these references in the product repositories, their
updates come from the floating tag:

```yaml
# .github/dependabot.yml of the product repository
- package-ecosystem: github-actions
  directory: "/"
  ignore:
    - dependency-name: "centreon/github-actions*"
```

## Versioning

Every action has its own [Semantic Versioning](https://semver.org/) version, declared
in `.github/release-components.json` with the paths it is built from: an action that
uses `pulp/lib` is released again when `pulp/lib` changes, the others are not.

| Change to an action                                                                            | Pull request title           | Release |
| ---------------------------------------------------------------------------------------------- | ---------------------------- | ------- |
| Removed or renamed input/output, new required input, changed default or behavior a caller sees | `feat(pulp)!: …` (or `fix!`) | major   |
| New optional input or output                                                                   | `feat(pulp): …`              | minor   |
| Bug fix, pinned dependency bump, internal refactoring                                          | `fix(pulp): …`               | patch   |
| Documentation, CI of this repository                                                           | `docs: …`, `ci: …`           | none    |

Pull requests are squash-merged with their title as commit title, so the title decides
the release; the `lint` check rejects a non-conventional title and its summary shows
the versions the merge will release.

Every merge on `main` runs the `release` workflow, which for each action changed since
its last release:

1. creates the immutable `<action>-vX.Y.Z` tag and its GitHub release (commit list and
   usage line);
2. moves the floating `<action>-vX` tag to it.

A breaking change starts `<action>-v(X+1)` and leaves `<action>-vX` on its last
release: older majors receive no further fixes.

## Writing an action

Each action is self-contained: it never calls a sibling action through `uses: ./...`
(that path resolves in the caller's workspace). Shared logic lives in scripts called
through `${{ github.action_path }}`, so every file comes from the pinned commit. Remote
actions are pinned to a full SHA with a `# vX.Y.Z` comment. The `lint` workflow checks
both rules, plus shellcheck and actionlint.

A new action gets a component named after its path (`pulp/setup-cli` ->
`pulp-setup-cli`) in `.github/release-components.json`, listing its own directory first
and then every directory it uses through `github.action_path`; the `lint` check fails
otherwise.

## Pulp delivery

| Action                       | Purpose                                                                                       |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| `pulp/package-delivery`      | Deliver rpm/deb packages from the actions cache to an unstable, testing or feature repository |
| `pulp/promote-to-stable`     | Promote testing packages to the stable repository                                             |
| `pulp/repository-properties` | Compute repository names, base paths, suites and domains of a delivery                        |
| `pulp/setup-cli`             | Install pulp-cli and authenticate with a GitHub OIDC token                                    |
| `pulp/lib`                   | Shell helpers (REST api, manifest, post-delivery checks), not an action                       |

Requirements of the calling job:

- `permissions: id-token: write` (OIDC authentication to Pulp).
- An internal runner: the Pulp api is not reachable from GitHub-hosted runners.
- An OIDC rule for the calling repository in the Pulp configuration.
- Inputs `pulp_url`, `pulp_content_url` and `audience` wired from the `PULP_API_URL`,
  `PULP_CONTENT_URL` and `PULP_OIDC_AUDIENCE` organization variables.

`repository_name` selects the repository family: `standard`, `standard-internal`,
`business`, `business-internal`, `plugins` or `connectors`.

Example:

```yaml
deliver-pulp:
  runs-on: centreon-ubuntu-26.04-small
  permissions:
    contents: read
    id-token: write
  steps:
    - uses: centreon/github-actions/pulp/package-delivery@pulp-package-delivery-v1
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

- **Release app**: a GitHub App with `contents: write` on this repository only; its
  client id in the `RELEASE_APP_CLIENT_ID` variable and its private key in the
  `RELEASE_APP_PRIVATE_KEY` secret of the `release` environment.
- **`release` environment**: deployment branches limited to `main`.
- **`Release tags` ruleset**: the release app is the only bypass actor, so no one else
  can create, move or delete a tag.
- **Immutable releases**: enabled, so a published `<action>-vX.Y.Z` release and its tag
  cannot change (floating tags carry no release and stay movable by the app).
- **Squash merge commit title**: "Pull request title", so the PR title checked by `lint`
  is the commit the release reads.
- **Required status check**: `lint` on `main`.
