# Changelog

## 1.0.0 (2026-11-20)


### Features

* **pulp:** add shared Pulp delivery actions ([43cbc73](https://github.com/centreon/github-actions/commit/43cbc73108908a074f32746ce49245500f7bcfa2))


### Bug Fixes

* **pulp:** cover the code specific to the maintained branches ([c43ec26](https://github.com/centreon/github-actions/commit/c43ec2632cac0a1f1a8a80efe7aba446c83004be))
* **pulp:** promote families whose testing and stable suites share their name ([f61a070](https://github.com/centreon/github-actions/commit/f61a070932b8f2260f8ef237ec847228d496e4a2))
* **pulp:** recover an interrupted deb promotion on rerun ([ded1b15](https://github.com/centreon/github-actions/commit/ded1b1544645970f5b5275f724cb6b4bba12d9e3))
* **pulp:** wait for queued tasks with separate queue and run budgets ([02d3ab3](https://github.com/centreon/github-actions/commit/02d3ab3556992f8ed963c18da0df113476f0265e))


### Performance Improvements

* **pulp:** check the presence of delivered deb packages in one listing ([7d4419e](https://github.com/centreon/github-actions/commit/7d4419e07fdd80a8edc9b0c6c280798a9f0f07de))
* **pulp:** run the delivery verification requests in parallel ([7eb237c](https://github.com/centreon/github-actions/commit/7eb237c294f19bd80c39f563a0b9f308a75b9d20))


### Code Refactoring

* **pulp:** call setup-cli through the self-repository syntax ([f586e53](https://github.com/centreon/github-actions/commit/f586e53cbe9cbc9fd879d332fad254b9cef1f540))
