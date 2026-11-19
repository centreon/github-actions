# github-actions

Shared GitHub Actions used by Centreon CI workflows.

## Usage

Reference an action by its path in this repository, pinned to a full commit SHA:

```yaml
- uses: centreon/github-actions/pulp/package-delivery@<commit-sha> # <branch or tag>
```

Each action is self-contained: it never calls a sibling action through `uses: ./...`
(that path would resolve in the caller's workspace). Shared logic lives in scripts
called through `${{ github.action_path }}`, so every file comes from the same commit.

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
    - uses: centreon/github-actions/pulp/package-delivery@<commit-sha> # main
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
