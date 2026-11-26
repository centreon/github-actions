# download-site

Actions that feed the download site: the upload of the source tarballs, and the
publication of release entries in the site repository.

| Action                           | Purpose                                                               |
| -------------------------------- | --------------------------------------------------------------------- |
| `download-site/sources-delivery` | Build the source tarball of a module and upload it to the site bucket |
| `download-site/publication`      | Commit release entries to the site repository and open a pull request |

A release shows on the site once its entries are merged in the site repository: the
upload alone publishes nothing.

## Sources delivery

```yaml
deliver-sources:
  runs-on: centreon-ubuntu-26.04-slim
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@<sha> # vX.Y.Z
      with:
        persist-credentials: false

    - uses: centreon/github-actions/download-site/sources-delivery@download-site/v1
      with:
        bucket_directory: centreon-gorgone
        module_directory: gorgone
        module_name: centreon-gorgone
        major_version: "26.10"
        minor_version: "3"
```

- Archives `module_directory` as `<module_name>-<major_version>.<minor_version>.tar.gz`,
  whose single top-level directory carries the same name, and uploads it to
  `public/<bucket_directory>/` in the bucket, readable by anyone.
- The `.git` directory of an archived checkout is left out of the tarball.
- The directory is renamed in the workspace: run the action last in its job, or on a
  checkout nothing else needs.
- The job needs the aws cli credentials that may write to the bucket; they come from
  the runner, the action takes no secret. The aws cli is installed when it is missing.
- A tarball of the same name is replaced: deliver a version once.

### Files built by another job

A module whose tarball must hold built files (frontend, dependencies, translations)
passes the cache keys of the job that built them. Each pair is optional and restored
before archiving; a missing cache fails the delivery.

| Path input                  | Cache key input             |
| --------------------------- | --------------------------- |
| `frontend_index_file`       | `frontend_index_cache_key`  |
| `frontend_static_directory` | `frontend_static_cache_key` |
| `backend_vendor_directory`  | `backend_vendor_cache_key`  |
| `translation_directory`     | `translation_cache_key`     |

Anything else can be restored by the calling job before the action: it archives the
directory as it finds it.

### Trying a delivery

- `dry_run: "true"` builds the tarball and prints its destination without uploading.
  The outputs `source_file` and `destination` are set either way.
- `bucket` targets another bucket than the download site one.

## Publication

```yaml
publish:
  runs-on: ubuntu-26.04
  permissions:
    contents: read
  steps:
    # ... build entries.tsv ...
    - uses: centreon/github-actions/download-site/publication@download-site/v1
      with:
        entries_file: entries.tsv
        branch: release/sources-26.10-20261100
        commit_message: "release: onprem 26.10 build 20261100"
        pr_title: "release: onprem 26.10 build 20261100"
        github_token: ${{ secrets.SITE_TOKEN }}
        webapp_repo: ${{ secrets.SITE_REPOSITORY }}
```

- Clones the site repository, writes the entries in its release files, runs the site's
  own validator, pushes the branch and opens the pull request. A human reviews and
  merges it.
- Running it again is safe: an existing branch and pull request are completed, an
  entry of the same product, os and version is replaced, and nothing is committed when
  nothing changed.
- The token needs contents and pull-requests write access on the site repository, and
  nothing else. `webapp_repo` has no default: pass it from a secret or a variable of
  the calling repository.
- The site's own code (its validator) runs on a copy of the clone, without the token.
  What is pushed is checked against what was validated: only the files this run wrote,
  with the content it validated, to the repository it cloned.

### Entries

`entries_file` holds one release entry per line, tab-separated, without a header:

| Column     | Content                                                               |
| ---------- | --------------------------------------------------------------------- |
| `product`  | Product key, declared in the site catalog                             |
| `train`    | Version train, declared in the site catalog; one train per run        |
| `state`    | `stable`, `rc` or `beta`; empty means `stable`                        |
| `os`       | Operating system, may be empty                                        |
| `version`  | Version of the artifact                                               |
| `file`     | File name or url of the artifact                                      |
| `date`     | `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SSZ`                                |
| `md5`      | md5 of the artifact, 32 lowercase hexadecimal characters              |
| `size`     | Size in bytes, greater than 0                                         |
| `s3_uri`   | Optional. Location of the artifact, only read with `sidecar: "true"`  |
| `out_name` | Optional. Release file of this entry, instead of the `out_name` input |

- The release file of an entry is `out_name` in the directory of its product group and
  train. Pass the `out_name` input when every entry goes to one file, or the column
  when a release spans several, as components versioned on their own do.
- A train or a product the catalog does not declare is refused: adding one is a
  decision to take in the site repository first.

### Monitoring agent

The Agent tab of the site only renders a block of the catalog. The four `agent_*`
inputs feature a windows installer there, in the same commit as the release entries:

```yaml
agent_version: "26.10.2"
agent_file_url: https://example.invalid/centreon-monitoring-agent-26.10.2.exe
agent_md5: 0123456789abcdef0123456789abcdef
agent_size: "12345678"
```

- The build replaces the featured entry of its train and joins the list of all
  versions; the rest of the catalog is left byte for byte.
- A build of a train that is not featured yet is added, and the pull request says so:
  which trains are featured is for its reviewer to decide.

### Appliances sidecar

`sidecar: "true"` also uploads a YAML description next to each artifact that has an
`s3_uri`, with the aws cli and the credentials of the runner. It is off by default.

### Trying a publication

`dry_run: "true"` does everything up to the validation, prints the files it would
commit and pushes nothing: no branch, no pull request, no sidecar.
