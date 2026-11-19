# github-actions

Shared GitHub Actions used by Centreon CI workflows.

## Usage

Reference an action by its path in this repository, pinned to the full commit SHA of a
release, with the release tag as a comment:

```yaml
- uses: centreon/github-actions/pulp/package-delivery@<commit-sha> # v1.2.0
```

- Always pin a SHA, never a tag or a branch: a SHA cannot be moved, and Dependabot
  reads the `# vX.Y.Z` comment to propose the next release.
- Use the same release for every action of this repository in a workflow.
- Each maintained branch of a product repository keeps its own pin: an older branch
  stays on the release it was validated with until it is bumped on purpose.

Let Dependabot bump the pins in one pull request per product repository:

```yaml
# .github/dependabot.yml of the product repository
- package-ecosystem: github-actions
  directory: "/"
  schedule:
    interval: monthly
  groups:
    centreon-github-actions:
      patterns:
        - "centreon/github-actions*"
```

An urgent fix does not wait for Dependabot: bump the SHA and the comment by hand.

## Versioning

The repository is released as a whole with [Semantic Versioning](https://semver.org/)
tags `vX.Y.Z`, each with an immutable GitHub release and an entry in `CHANGELOG.md`.

| Change to any action                                                                           | Pull request title           | Release |
| ---------------------------------------------------------------------------------------------- | ---------------------------- | ------- |
| Removed or renamed input/output, new required input, changed default or behavior a caller sees | `feat(pulp)!: …` (or `fix!`) | major   |
| New action, new optional input or output                                                       | `feat(pulp): …`              | minor   |
| Bug fix, pinned dependency bump, internal refactoring                                          | `fix(pulp): …`               | patch   |
| Documentation, CI of this repository                                                           | `docs: …`, `ci: …`           | none    |

Pull requests are squash-merged, so their title is the commit that decides the release.

How a release happens:

1. Every merge on `main` updates the release pull request (`chore: release X.Y.Z`),
   which carries the version bump and the `CHANGELOG.md` entry.
2. Merging the release pull request creates the `vX.Y.Z` tag and its GitHub release.
3. The release summary gives the SHA to pin.

Tags are never moved or deleted, and there is no floating major tag (`v1`): callers pin
SHAs, so a moving tag would bring nothing but risk.

## Writing an action

Each action is self-contained: it never calls a sibling action through `uses: ./...`
(that path resolves in the caller's workspace). Shared logic lives in scripts called
through `${{ github.action_path }}`, so every file comes from the pinned commit. Remote
actions are pinned to a full SHA with a `# vX.Y.Z` comment. The `lint` workflow checks
both rules, plus shellcheck and actionlint.

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
    - uses: centreon/github-actions/pulp/package-delivery@<commit-sha> # v1.0.0
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

- **Release app**: a GitHub App with `contents`, `pull-requests` and `issues` write
  access to this repository only; its client id in the `RELEASE_APP_CLIENT_ID` variable
  and its private key in the `RELEASE_APP_PRIVATE_KEY` secret of the `release`
  environment.
- **`release` environment**: deployment branches limited to `main`.
- **`Release tags` ruleset**: the release app is the only bypass actor, so no one else
  can create, move or delete a tag.
- **Immutable releases**: enabled, so a published release and its tag cannot change.
- **Required status check**: `lint` on `main`.
