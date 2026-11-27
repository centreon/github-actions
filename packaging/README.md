# packaging

Actions shared by the packaging jobs.

| Action                    | Purpose                                                                 |
| ------------------------- | ----------------------------------------------------------------------- |
| `packaging/parse-distrib` | Give the package extension, the naming and the family of a distribution |
| `packaging/nfpm`          | Build rpm or deb packages with nfpm, cache them and upload them         |

## Parse distrib

```yaml
- name: Parse distrib name
  id: parse-distrib
  uses: centreon/github-actions/packaging/parse-distrib@packaging/v1
  with:
    distrib: ${{ matrix.distrib }}

- run: ls ./*."$PACKAGE_EXTENSION"
  shell: bash
  env:
    PACKAGE_EXTENSION: ${{ steps.parse-distrib.outputs.package_extension }}
```

`distrib` is the name the workflows give a distribution. The el ones are accepted under
both of their names (`el9` or `alma9`); an unknown name fails the step.

| `distrib`        | `package_extension` | `package_distrib_name` | `distrib_family` | `distrib_family_major` | `distrib_name` | `repo_distrib_name` |
| ---------------- | ------------------- | ---------------------- | ---------------- | ---------------------- | -------------- | ------------------- |
| `el7`, `centos7` | `rpm`               | `el7`                  | `el`             | `el7`                  | `centos7`      | `el7`               |
| `el8`, `alma8`   | `rpm`               | `el8`                  | `el`             | `el8`                  | `alma8`        | `el8`               |
| `el9`, `alma9`   | `rpm`               | `el9`                  | `el`             | `el9`                  | `alma9`        | `el9`               |
| `el10`, `alma10` | `rpm`               | `el10`                 | `el`             | `el10`                 | `alma10`       | `el10`              |
| `bullseye`       | `deb`               | `deb11u1`              | `debian`         | `debian`               | `bullseye`     | `bullseye`          |
| `bookworm`       | `deb`               | `deb12u1`              | `debian`         | `debian`               | `bookworm`     | `bookworm`          |
| `trixie`         | `deb`               | `deb13u1`              | `debian`         | `debian`               | `trixie`       | `trixie`            |
| `jammy`          | `deb`               | `0ubuntu.22.04`        | `ubuntu`         | `ubuntu`               | `jammy`        | `jammy`             |
| `noble`          | `deb`               | `0ubuntu.24.04`        | `ubuntu`         | `ubuntu`               | `noble`        | `noble`             |

Three more outputs:

- `package_version_separator`: between a package name and its version, `-` for rpm and
  `_` for deb.
- `package_distrib_separator`: between a package version and `package_distrib_name`,
  `.` for el, `+` for debian and `-` for ubuntu.
- `package_distrib`: same value as `repo_distrib_name`, under its older name.

### Switching from a local copy

Every output of the local `parse-distrib` actions exists here with the same value, with
one exception: in centreon-collect and centreon-modules, `distrib_family` held the major
version for el (`el9`). Here `distrib_family` is always `el`, `debian` or `ubuntu`; a
caller that needs the former value reads `distrib_family_major`.

### Adding a distribution

Add its line to `parse-distrib.sh`, to this table and to the tests, and to the table of
the `pulp` package (`pulp/lib/parse-distrib.sh`), which keeps its own copy: a test fails
when the two disagree.

## Package with nfpm

```yaml
- name: Package
  uses: centreon/github-actions/packaging/nfpm@packaging/v1
  with:
    nfpm_file_pattern: "packaging/*.yaml"
    distrib: ${{ matrix.distrib }}
    major_version: ${{ needs.get-environment.outputs.major_version }}
    minor_version: ${{ needs.get-environment.outputs.minor_version }}
    release: ${{ needs.get-environment.outputs.release }}
    arch: all
    commit_hash: ${{ github.sha }}
    cache_key: ${{ github.run_id }}-${{ github.sha }}-${{ matrix.distrib }}
    rpm_gpg_key: ${{ secrets.RPM_GPG_SIGNING_KEY }}
    rpm_gpg_signing_key_id: ${{ secrets.RPM_GPG_SIGNING_KEY_ID }}
    rpm_gpg_signing_passphrase: ${{ secrets.RPM_GPG_SIGNING_PASSPHRASE }}
```

The action builds one package per nfpm configuration matching `nfpm_file_pattern` (one
or several patterns), moves the packages to the working directory, saves them in the
cache under `cache_key` and, with `upload_artifacts: "true"`, uploads them as an
artifact kept one day. `nfpm` must be installed: the packaging images provide it.

This repository is public and holds no key: the signing key is an input, read from the
secrets of the calling repository. It is written outside the workspace and removed when
the step ends. Without `rpm_gpg_signing_key_id` the packages are built unsigned.

### What a configuration can read

| Variable                                                       | Value                                                                    |
| -------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `${VERSION}`                                                   | `version`, or `major_version.minor_version`                              |
| `${RELEASE}`                                                   | `release`; for a deb, followed by the distribution (`7+deb12u1`)         |
| `${DIST}`                                                      | For an rpm, the distribution (`.el9`); empty for a deb                   |
| `${ARCH}`                                                      | `arch`                                                                   |
| `${MAJOR_VERSION}`, `${NEXT_MAJOR_VERSION}`                    | `major_version` and the one after it; only when `major_version` is given |
| `${APACHE_USER}`, `${APACHE_GROUP}`                            | `apache` for an rpm, `www-data` for a deb                                |
| `${RPM_SIGNING_KEY_FILE}`, `${RPM_SIGNING_KEY_ID}`             | The signing key                                                          |
| The variables of `environment`                                 | One `NAME=value` per line                                                |
| The variables of `env/.env.<distrib>`, next to a configuration | Loaded when the file exists                                              |
| The variables of the job                                       | As they are                                                              |

Placeholders are replaced before nfpm runs:

- `@COMMIT_HASH@`, `@APACHE_USER@` and `@APACHE_GROUP@`, in the configuration.
- The ones of `placeholders`, in the configuration: one `NAME=value` per line replaces
  `@NAME@`. A line holding only `NAME` takes the value of the variable `NAME`.
- The ones of `tree_placeholders`, written the same way, in every file of the
  directory of the configuration (scripts, templates).
- An `@UPPERCASE@` placeholder left in a configuration fails the step.

### Options

| Input                | Default                | Effect                                                                                              |
| -------------------- | ---------------------- | --------------------------------------------------------------------------------------------------- |
| `version_cadence`    | `monthly`              | `NEXT_MAJOR_VERSION` after `26.10` is `26.11`; with `biannual`, after `24.04` it is `24.10`         |
| `deb_release_suffix` | From `parse-distrib`   | Distribution suffix of the release of a deb, for example `~bookworm`                                |
| `deb_stable_release` | empty: release is kept | Release number forced on a deb when `stability` is neither `unstable` nor `canary`                  |
| `deb_copyright`      | `false`                | Adds `copyright.<license>`, or the `LICENSE.md` of the repository, to a deb as its `copyright` file |
| `package_extension`  | From `distrib`         | Not needed; when given, the step fails if it is not the extension of `distrib`                      |
| `artifact_name`      | `packages-<distrib>`   | Name of the uploaded artifact; the default ends with `-<arch>` when `arch` is given                 |

### Switching from a local copy

The local `package-nfpm` and `package` actions differ between repositories. What each
one did on its own is an input here:

| Local copy                        | Inputs giving the same packages                                                                                                  |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| centreon                          | `deb_copyright: "true"`; the PHP versions as `environment` and `tree_placeholders`; `version_cadence: biannual` up to 25.10      |
| centreon-collect                  | `deb_copyright: "true"`; `version_cadence: biannual` up to 25.10                                                                 |
| centreon-modules                  | Same as centreon, plus `placeholders: CENTREON_VERSION=<version>`                                                                |
| centreon-plugins                  | `version`, `stability` and `deb_stable_release: "1"`                                                                             |
| centreon-stream-connector-scripts | `version`, `deb_release_suffix: "~<distrib>"`, `placeholders` for `luaver` and `VERSION`, `deb_stable_release: "1"` where needed |
| centreon-agent                    | `version`                                                                                                                        |

Three things stay in the calling repository, before this action: removing the
development files of a module, choosing the PHP versions, and reading the Lua version.
The packaging of centreon-plugin-packs builds one package per pack from a template and
keeps its own action.
