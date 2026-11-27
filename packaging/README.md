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

| Variable                                           | Value                                                                    |
| -------------------------------------------------- | ------------------------------------------------------------------------ |
| `${VERSION}`                                       | `version`, or `major_version.minor_version`                              |
| `${RELEASE}`                                       | `release`; for a deb, followed by the distribution (`7+deb12u1`)         |
| `${DIST}`                                          | For an rpm, the distribution (`.el9`); empty for a deb                   |
| `${ARCH}`                                          | `arch`                                                                   |
| `${MAJOR_VERSION}`, `${NEXT_MAJOR_VERSION}`        | `major_version` and the one after it; only when `major_version` is given |
| `${APACHE_USER}`, `${APACHE_GROUP}`                | `apache` for an rpm, `www-data` for a deb                                |
| `${RPM_SIGNING_KEY_FILE}`, `${RPM_SIGNING_KEY_ID}` | The signing key                                                          |
| The variables of the job                           | As they are: set them with `env:` on the job, or through `$GITHUB_ENV`   |

`NEXT_MAJOR_VERSION` follows the versions of Centreon: six months later before 26.10
(`24.04` then `24.10`), the next month since (`26.10` then `26.11`).

Placeholders are replaced in the configuration before nfpm runs:

- `@COMMIT_HASH@`, `@APACHE_USER@` and `@APACHE_GROUP@`.
- The ones of `placeholders`: one `NAME=value` per line replaces `@NAME@`.
- An `@UPPERCASE@` placeholder left in a configuration fails the step.

Only the configurations are edited. A workflow that needs a value in another file (an
installation script, a template) writes it there before calling the action.

### Options

| Input                | Default              | Effect                                                                                              |
| -------------------- | -------------------- | --------------------------------------------------------------------------------------------------- |
| `deb_release`        | `release`            | Release number of a deb, when it is not the one of an rpm                                           |
| `deb_release_suffix` | From `parse-distrib` | Distribution suffix of the release of a deb, for example `~bookworm`                                |
| `deb_copyright`      | `false`              | Adds `copyright.<license>`, or the `LICENSE.md` of the repository, to a deb as its `copyright` file |
| `artifact_name`      | `packages-<distrib>` | Name of the uploaded artifact; the default ends with `-<arch>` when `arch` is given                 |

### Switching from a local copy

The local `package-nfpm` and `package` actions differ between repositories. What gives
the same packages with this one:

| Local copy                        | Inputs                                                                                                                                                      | Before the action, in the workflow                                                                                                               |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| centreon                          | `deb_copyright: "true"`                                                                                                                                     | Remove the development files; set `PHP_MIN_VERSION` and `PHP_MAX_VERSION`; write the PHP version in the two installation scripts of centreon-web |
| centreon-modules                  | `deb_copyright: "true"`; for sourceguardian-loader, `placeholders` for `PHP_MIN_VERSION` and `PHP_MODULE_API`                                               | Remove the development files; set the four `PHP_*` variables; write the PHP version in the installation script of sourceguardian-loader          |
| centreon-collect                  | `deb_copyright: "true"`                                                                                                                                     | Nothing; the Lua version of the `env/.env.<distrib>` files moves to the configuration that reads it                                              |
| centreon-plugins                  | `version`; `deb_release`: `release` on unstable and canary, `1` otherwise                                                                                   | Nothing                                                                                                                                          |
| centreon-stream-connector-scripts | `version`, `deb_release_suffix: "~<distrib>"`, `placeholders` for `luaver` and `VERSION`; `deb_release` like centreon-plugins where the release is not kept | Read the Lua version                                                                                                                             |
| centreon-agent                    | `version`                                                                                                                                                   | Nothing                                                                                                                                          |

No caller passes `package_extension` or `stability` any more. The packaging of
centreon-plugin-packs builds one package per pack from a template and keeps its own
action.
