"""Tests of the per-action release logic, against a throwaway git repository."""

import json
import subprocess
from pathlib import Path

import pytest

import release


def run(*args: str) -> None:
    subprocess.run(args, check=True, capture_output=True)


@pytest.fixture
def repo(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    monkeypatch.chdir(tmp_path)
    run("git", "init", "-q", "-b", "main")
    run("git", "config", "user.email", "ci@example.com")
    run("git", "config", "user.name", "ci")
    run("git", "config", "commit.gpgsign", "false")
    run("git", "config", "tag.gpgsign", "false")
    for path in ("act/one", "act/two", "act/lib"):
        Path(path).mkdir(parents=True)
    Path("act/one/action.yml").write_text("name: one\n")
    Path("act/two/action.yml").write_text("name: two\n")
    Path(".github").mkdir()
    Path(".github/release-components.json").write_text(
        json.dumps({"act-one": ["act/one", "act/lib"], "act-two": ["act/two"]})
    )
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", "chore: init")
    return tmp_path


def commit(path: str, title: str, body: str = "") -> None:
    with open(path, "a") as f:
        f.write(title + "\n")
    run("git", "add", "-A")
    run("git", "commit", "-q", "-m", title, *(["-m", body] if body else []))


@pytest.mark.parametrize(
    ("title", "body", "level"),
    [
        ("feat(pulp): add an input", "", "minor"),
        ("fix(pulp): handle 503", "", "patch"),
        ("fix(deps): bump actions/cache", "", "patch"),
        ("perf: batch uploads", "", "patch"),
        ("feat(pulp)!: rename an input", "", "major"),
        ("fix: drop input", "BREAKING CHANGE: input x is removed", "major"),
        ("docs: readme", "", None),
        ("ci: lint", "", None),
        ("Update action.yml", "", None),
    ],
)
def test_bump_level(title: str, body: str, level: str) -> None:
    assert release.bump_level(title, body) == level


def test_next_version() -> None:
    assert release.next_version(None, "patch") == (1, 0, 0)
    assert release.next_version((1, 2, 3), "patch") == (1, 2, 4)
    assert release.next_version((1, 2, 3), "minor") == (1, 3, 0)
    assert release.next_version((1, 2, 3), "major") == (2, 0, 0)


def test_validate(repo: Path) -> None:
    components = json.loads(Path(".github/release-components.json").read_text())
    assert release.validate(components)
    Path("act/three").mkdir()
    Path("act/three/action.yml").write_text("name: three\n")
    assert not release.validate(components)


def test_versions_and_commits_follow_component_paths(repo: Path) -> None:
    commit("act/one/action.yml", "feat: one")
    run("git", "tag", "act-one-v1.0.0")
    run("git", "tag", "act-one-v1")
    commit("act/lib/x.sh", "fix: shared helper")
    commit("act/two/action.yml", "feat: two")
    commit("act/one/action.yml", "docs: one")

    assert release.released_versions("act-one") == [(1, 0, 0)]
    titles = [
        c[1]
        for c in release.commits_since("act-one", ["act/one", "act/lib"], (1, 0, 0))
    ]
    assert titles == ["docs: one", "fix: shared helper"]
    assert [c[1] for c in release.commits_since("act-two", ["act/two"], None)] == [
        "feat: two",
        "chore: init",
    ]


def test_plan(repo: Path, capsys: pytest.CaptureFixture) -> None:
    commit("act/one/action.yml", "feat: one")
    run("git", "tag", "act-one-v1.4.2")
    run("git", "checkout", "-q", "-b", "pr")
    commit("act/lib/x.sh", "wip")
    components = json.loads(Path(".github/release-components.json").read_text())

    assert release.plan(components, "fix(lib): retry", "main")
    out = capsys.readouterr().out
    assert "`act-one-v1.4.3`" in out and "act-two" not in out

    assert release.plan(components, "feat(lib)!: new layout", "main")
    assert "`act-one-v2.0.0` | `act-one-v2`" in capsys.readouterr().out

    assert not release.plan(components, "Update x.sh", "main")


FAKE_GH = """#!/usr/bin/env bash
# Stand-in for gh: releases and refs are written to the "origin" remote.
set -euo pipefail
remote=$(git remote get-url origin)
if [[ "$1" == release && "$2" == create ]]; then
  tag=$3
  shift 3
  while (($# > 0)); do
    [[ "$1" == --target ]] && target=$2
    shift
  done
  git -c tag.gpgSign=false -c tag.forceSignAnnotated=false --git-dir "$remote" tag "$tag" "$target"
  exit 0
fi
args=("$@")
last=${args[-1]}
case "${args[*]}" in
  "api -X PATCH "*) tag=${args[3]##*/tags/}; git -c tag.gpgSign=false -c tag.forceSignAnnotated=false --git-dir "$remote" tag -f "$tag" "${args[5]#sha=}" ;;
  "api -X POST "*) tag=${args[5]#ref=refs/tags/}; git -c tag.gpgSign=false -c tag.forceSignAnnotated=false --git-dir "$remote" tag "$tag" "${last#sha=}" ;;
  "api "*) git --git-dir "$remote" rev-parse -q --verify "refs/tags/${args[1]##*/tags/}" > /dev/null ;;
esac
"""


def remote_tags(remote: Path) -> dict[str, str]:
    out = subprocess.run(
        [
            "git",
            "--git-dir",
            str(remote),
            "tag",
            "--format=%(refname:short) %(objectname:short=7)",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return dict(line.split() for line in out.splitlines())


def short_head() -> str:
    return subprocess.run(
        ["git", "rev-parse", "--short=7", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def test_release_end_to_end(
    repo: Path,
    tmp_path_factory: pytest.TempPathFactory,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    remote = tmp_path_factory.mktemp("remote") / "origin.git"
    run("git", "init", "-q", "--bare", str(remote))
    run("git", "remote", "add", "origin", str(remote))
    bin_dir = tmp_path_factory.mktemp("bin")
    (bin_dir / "gh").write_text(FAKE_GH)
    (bin_dir / "gh").chmod(0o755)
    monkeypatch.setenv("PATH", f"{bin_dir}:{Path('/usr/bin')}:{Path('/bin')}")
    components = json.loads(Path(".github/release-components.json").read_text())

    def publish() -> dict[str, str]:
        run("git", "push", "-q", "origin", "main")
        release.release(components, "centreon/github-actions")
        run("git", "fetch", "-q", "--force", "origin", "+refs/tags/*:refs/tags/*")
        return remote_tags(remote)

    commit("act/one/action.yml", "feat(one): add")
    commit("act/two/action.yml", "feat(two): add")
    first = short_head()
    tags = publish()
    assert tags == {
        k: first
        for k in ("act-one-v1.0.0", "act-one-v1", "act-two-v1.0.0", "act-two-v1")
    }

    commit("act/lib/x.sh", "fix(lib): retry")
    fix = short_head()
    tags = publish()
    assert tags["act-one-v1.0.1"] == fix and tags["act-one-v1"] == fix
    assert tags["act-two-v1"] == first and "act-two-v1.0.1" not in tags

    commit("act/two/action.yml", "feat(two)!: rename input")
    major = short_head()
    tags = publish()
    assert tags["act-two-v2.0.0"] == major and tags["act-two-v2"] == major
    assert tags["act-two-v1"] == first

    commit("act/one/action.yml", "docs(one): typo")
    assert publish() == tags
