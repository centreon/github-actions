# sources

Delivery of the source tarballs published on the download site.

| Action             | Purpose                                                               |
| ------------------ | --------------------------------------------------------------------- |
| `sources/delivery` | Build the source tarball of a module and upload it to the site bucket |

## Delivery

```yaml
deliver-sources:
  runs-on: centreon-ubuntu-26.04-slim
  permissions:
    contents: read
  steps:
    - uses: actions/checkout@<sha> # vX.Y.Z
      with:
        persist-credentials: false

    - uses: centreon/github-actions/sources/delivery@sources/v1
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
