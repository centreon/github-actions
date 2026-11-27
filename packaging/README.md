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
or several patterns) into the working directory, saves the packages in the cache under
`cache_key` and, with `upload_artifacts: "true"`, uploads them as an artifact kept one
day. `nfpm` must be installed: the packaging images provide it.

This repository is public and holds no key: the signing key is an input, read from the
secrets of the calling repository. It is written outside the workspace and removed when
the step ends. Without `rpm_gpg_key` the packages are built unsigned.

### What a configuration can read

nfpm replaces `${NAME}` by the variable `NAME` in most fields of a configuration
(`version`, `release`, `description`, `depends`, the signature...), and in the `src` and
`dst` of a `contents` entry that sets `expand: true`. The action gives it:

| Variable                                           | Value                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------- |
| `${VERSION}`                                       | `version`, or `major_version.minor_version`                               |
| `${RELEASE}`                                       | `release`; for a deb, followed by the distribution (`7+deb12u1`)          |
| `${DIST}`                                          | For an rpm, the distribution (`.el9`); empty for a deb                    |
| `${ARCH}`                                          | `arch`                                                                    |
| `${COMMIT_HASH}`                                   | `commit_hash`                                                             |
| `${MAJOR_VERSION}`, `${NEXT_MAJOR_VERSION}`        | `major_version` and the one after it; only when `major_version` is given  |
| `${RPM_SIGNING_KEY_FILE}`, `${RPM_SIGNING_KEY_ID}` | The signing key; empty without one, which is how nfpm skips the signature |
| The variables of the job                           | As they are: set them with `env:` on the job, or through `$GITHUB_ENV`    |

`NEXT_MAJOR_VERSION` follows the versions of Centreon: six months later before 26.10
(`24.04` then `24.10`), the next month since (`26.10` then `26.11`).

```yaml
description: |
  Centreon broker.
  Commit: ${COMMIT_HASH}
contents:
  - src: "./module.so"
    dst: "/usr/lib64/lua/${LUA_VERSION}/module.so"
    expand: true
    file_info:
      owner: "@APACHE_USER@"
```

nfpm does not read the owner of a file from the environment. That is the one thing the
action writes in a configuration: `@APACHE_USER@` and `@APACHE_GROUP@` become `apache`
for an rpm and `www-data` for a deb. Any other `@UPPERCASE@` placeholder fails the step,
and nothing is replaced inside the packaged files: a workflow that needs a value in an
installation script writes it there before calling the action.

### Options

| Input           | Default              | Effect                                                                                              |
| --------------- | -------------------- | --------------------------------------------------------------------------------------------------- |
| `deb_release`   | `release`            | Release number of a deb, when it is not the one of an rpm                                           |
| `deb_copyright` | `false`              | Adds `copyright.<license>`, or the `LICENSE.md` of the repository, to a deb as its `copyright` file |
| `artifact_name` | `packages-<distrib>` | Name of the uploaded artifact; the default ends with `-<arch>` when `arch` is given                 |

### Switching from a local copy

The local `package-nfpm` and `package` actions replaced `@NAME@` placeholders with sed
and differ between repositories. Every repository changes `@COMMIT_HASH@` to
`${COMMIT_HASH}` in its configurations and stops passing `package_extension` and
`stability`. Then:

| Local copy                        | Inputs                                                                       | In the repository                                                                                                                                                                                                                                              |
| --------------------------------- | ---------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| centreon                          | `deb_copyright: "true"`                                                      | A step removes the development files, sets `PHP_MIN_VERSION` and `PHP_MAX_VERSION`, and writes the PHP version in the two installation scripts of centreon-web                                                                                                 |
| centreon-modules                  | `deb_copyright: "true"`                                                      | Same step, with the four `PHP_*` variables; sourceguardian-loader reads `${PHP_MIN_VERSION}` and `${PHP_MODULE_API}` with `expand: true`                                                                                                                       |
| centreon-collect                  | `deb_copyright: "true"`                                                      | The Lua version of the `env/.env.<distrib>` files moves to the configuration that reads it                                                                                                                                                                     |
| centreon-plugins                  | `version`; `deb_release`: `release` on unstable and canary, `1` otherwise    | Nothing else                                                                                                                                                                                                                                                   |
| centreon-stream-connector-scripts | `version`; `deb_release` like centreon-plugins where the release is not kept | A step sets `LUA_VERSION`; the configurations read `${LUA_VERSION}` and `${VERSION}` instead of `@luaver@` and `@VERSION@`, with `expand: true` on the entries using them. Its debs take the suffix of the other projects: `1+deb12u1` instead of `1~bookworm` |
| centreon-agent                    | `version`                                                                    | Nothing else                                                                                                                                                                                                                                                   |

The packaging of centreon-plugin-packs builds one package per pack from a template and
keeps its own action.
