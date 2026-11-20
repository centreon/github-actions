# CLAUDE.md — pulp package

Read [README.md](README.md) and the root [CLAUDE.md](../CLAUDE.md) first.

## What the scripts must keep doing

- **Fail closed.** A delivery or a promotion never creates a repository or a
  distribution (the rpm feature repositories are the only exception): a missing one is
  an error naming it. An api that cannot be read is an error, never "absent".
- **Protect stable.** A testing delivery refuses a version already published in stable,
  and a promotion only adds to the stable repositories.
- **Authenticate with the OIDC token only.** It expires after about 5 minutes: call
  `refresh_pulp_token` in the parent shell before a long loop, a refresh in a subshell
  is lost. Never print the token.
- **Verify what was delivered.** `lib/check-*.sh` reads the manifest written by the
  delivery or the promotion; keep it in sync with what is uploaded.

## Pulp facts that shape the code

- Listing `content/deb/release_components/` is refused (403) to the CI identity. Deduce
  a release component from the associations of a package, as `promote-deb.sh` does.
- A deb package is unique on its name, version and architecture in a repository,
  across suites: delivering the same version with other bytes evicts the other build.
- Creating content is one task per package, and tasks queue behind each other on a
  repository. Batch what can be batched (`modify` with a list), and wait with
  `wait_task_race`, which tells a queued task from a failing one.
- One request per package does not scale: a full plugins delivery is about 690 packages
  per distribution. Prefer one filtered listing (`pulp_label_select`, `fields=`), and
  run the remaining per-package requests through `wait_for_slot`.
- Repository names and suites differ by family and version; `lib/repository-properties.sh`
  is the only place that computes them. 24.04 and 24.10 also have a dedicated legacy
  stable repository; `plugins` and `connectors` are not versioned and name their
  testing and stable suites alike.

## Testing a change for real

bats tests cover the scripts against stand-ins; a change to a delivery or promotion
path also needs a real run before it is released.

- Use the **dev** stack, never production: api `https://pulp-api-dev.int.centreon.com`,
  content `https://packages-dev.centreon.com`, audience `https://pulp.dev.centreon.io`.
  A token minted for that audience is refused by production.
- Call the action from a throwaway branch of the repository that owns the family
  (`centreon` for standard, `centreon-modules` for business, `centreon-plugins` for
  plugins, `centreon-plugin-packs` for connectors), pinned to the commit under review.
- A delivery runs from any branch. A stable promotion is only accepted from a tag or a
  release branch: trigger the test workflow on a temporary tag.
- Throwaway packages built in the workflow are enough: the scripts only read the
  package name, version and architecture.
- Never pass `centreon_technique_pat` in a test against the dev stack: it requests the
  creation of the feature repositories on production.
- Ask before pushing a branch, a tag or a workflow to another repository, and delete
  them once the run is read.
