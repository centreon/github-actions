# packaging

Actions shared by the packaging jobs.

| Action                    | Purpose                                                                 |
| ------------------------- | ----------------------------------------------------------------------- |
| `packaging/parse-distrib` | Give the package extension, the naming and the family of a distribution |

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
