# pulp

Delivery of rpm and deb packages to the Pulp repositories.

| Action                   | Purpose                                                                                       |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| `pulp/package-delivery`  | Deliver rpm/deb packages from the actions cache to an unstable, testing or feature repository |
| `pulp/promote-to-stable` | Promote the testing packages of a module to the stable repository                             |
| `pulp/setup-cli`         | Install pulp-cli and authenticate with a GitHub OIDC token                                    |

`lib/` holds their shared scripts (repository layout, REST api, manifest, post-delivery
checks) and `tests/` their bats tests; neither is an action. The inputs and outputs of
an action are documented in its `action.yml`.

## Requirements of the calling job

- `permissions: id-token: write`: the actions authenticate to Pulp with a GitHub OIDC
  token, never with a stored credential.
- An internal runner: the Pulp api is not reachable from GitHub-hosted runners.
- An OIDC rule for the calling repository in the Pulp configuration (delivery-tooling).
  Deliveries are allowed from any ref; stable promotions only from `develop`, the
  maintenance and release branches, and tags.
- Repositories that already exist: the actions never create them, except the rpm
  feature repositories (see below).
- Inputs `pulp_url`, `pulp_content_url` and `audience` wired from the `PULP_API_URL`,
  `PULP_CONTENT_URL` and `PULP_OIDC_AUDIENCE` organization variables.

## Delivery

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

- The packages come from the actions cache entry `cache_key`, saved by the packaging
  job as `./*.rpm` or `./*.deb`.
- `repository_name` selects the repository family: `standard` (default),
  `standard-internal`, `business`, `business-internal`, `plugins` or `connectors`.
  `plugins` and `connectors` are not versioned: leave `version` empty.
- `stability` is `unstable` or `testing`; `release_type` (`release` or `hotfix`) selects
  the testing repository.
- A testing delivery of a package version already published in stable is refused: bump
  the version.
- `delivery_type: feature` delivers rpm packages to the repositories of the ticket
  found in the branch name (`MON-12345-...`). When they do not exist yet,
  `centreon_technique_pat` is needed to request their creation. deb feature deliveries
  are skipped.
- Every delivery is verified afterwards (presence in the repository, published
  metadata, download); `verify: "false"` skips it.

## Promotion

```yaml
- uses: centreon/github-actions/pulp/promote-to-stable@pulp/v1
  with:
    module_name: centreon-web
    distrib: el9
    major_version: "26.10"
    stability: stable
    release_type: release
    is_cloud: "false"
    pulp_url: ${{ vars.PULP_API_URL }}
    pulp_content_url: ${{ vars.PULP_CONTENT_URL }}
    audience: ${{ vars.PULP_OIDC_AUDIENCE }}
```

- Promotes every package of `module_name` found in the testing repository of
  `release_type`. Any `stability` other than `stable` is a dry run.
- 24.04 and 24.10 deb packages are also mirrored into their dedicated legacy stable
  repository, whose suite is the plain distribution codename.
- A promotion interrupted after the repository update can be run again.
