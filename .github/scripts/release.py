#!/usr/bin/env python3
"""Per-action releases of this repository.

Each component of .github/release-components.json is an action released on
its own: immutable "<component>-vX.Y.Z" tags carry a GitHub release, and the
floating "<component>-vX" tag follows the latest X.y.z release. The bump comes
from the conventional commit titles touching the component's paths.

  validate                  check the component file against the actions
  plan --title T --base B   preview the releases a pull request would make
  release                   release what changed on HEAD (needs GH_TOKEN)
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

COMPONENTS_FILE = Path(".github/release-components.json")
INITIAL_VERSION = (1, 0, 0)
TITLE_RE = re.compile(
    r"^(?P<type>feat|fix|perf|refactor|revert|docs|ci|chore|test|build|style)"
    r"(?:\([a-z0-9._-]+\))?(?P<breaking>!)?: \S"
)
PATCH_TYPES = {"fix", "perf", "refactor", "revert"}
LEVELS = {None: 0, "patch": 1, "minor": 2, "major": 3}

Version = tuple[int, int, int]
Components = dict[str, list[str]]
Commit = tuple[str, str, str]


class CommandError(Exception):
    """A git or gh command failed; carries its stderr."""


def command(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise CommandError(f"{' '.join(args)}: {result.stderr.strip()}")
    return result


def git(*args: str) -> str:
    return command("git", *args).stdout


def gh(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    return command("gh", *args, check=check)


def action_dirs() -> list[str]:
    return sorted(
        str(p.parent)
        for p in Path(".").glob("**/action.yml")
        if not p.parts[0].startswith(".")
    )


def bump_level(title: str, body: str = "") -> str | None:
    """Release level of a commit; None for a non-conventional or non-releasing type."""
    match = TITLE_RE.match(title)
    if not match:
        return None
    if match["breaking"] or re.search(r"^BREAKING[ -]CHANGE: ", body, re.MULTILINE):
        return "major"
    if match["type"] == "feat":
        return "minor"
    if match["type"] in PATCH_TYPES:
        return "patch"
    return None


def released_versions(component: str) -> list[Version]:
    pattern = re.compile(rf"^{re.escape(component)}-v(\d+)\.(\d+)\.(\d+)$")
    tags = git("tag", "--list", f"{component}-v*").split()
    return [(int(m[1]), int(m[2]), int(m[3])) for m in map(pattern.match, tags) if m]


def next_version(current: Version | None, level: str) -> Version:
    if current is None:
        return INITIAL_VERSION
    major, minor, patch = current
    if level == "major":
        return (major + 1, 0, 0)
    if level == "minor":
        return (major, minor + 1, 0)
    return (major, minor, patch + 1)


def tag_name(component: str, version: Version) -> str:
    return f"{component}-v{'.'.join(map(str, version))}"


def commits_since(
    component: str, paths: list[str], current: Version | None
) -> list[Commit]:
    rev = "HEAD" if current is None else f"{tag_name(component, current)}..HEAD"
    out = git("log", "--format=%H%x1f%s%x1f%b%x1e", rev, "--", *paths)
    commits = []
    for record in filter(None, (r.strip("\n") for r in out.split("\x1e"))):
        sha, subject, body = record.split("\x1f")
        commits.append((sha, subject, body))
    return commits


def validate(components: Components) -> bool:
    """Every action is the first path of the component named after it, and every path exists."""
    errors = []
    dirs = action_dirs()
    for directory in dirs:
        name = directory.replace("/", "-")
        if components.get(name, [None])[0] != directory:
            errors.append(
                f"action {directory} needs a '{name}' component whose first path is {directory}"
            )
    for name, paths in components.items():
        errors += [
            f"component {name}: path {p} does not exist"
            for p in paths
            if not Path(p).is_dir()
        ]
        if not paths or paths[0] not in dirs:
            errors.append(
                f"component {name}: its first path must be an action directory"
            )
    for error in errors:
        print(f"::error file={COMPONENTS_FILE}::{error}")
    return not errors


def summary(lines: list[str]) -> None:
    text = "\n".join(lines) + "\n"
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(text)


def plan(components: Components, title: str, base: str) -> bool:
    """Show what merging a pull request with this title would release."""
    if not TITLE_RE.match(title):
        print(
            f"::error::'{title}' is not a conventional commit title: type(scope)!: description"
        )
        return False
    level = bump_level(title)
    changed = git("diff", "--name-only", f"{base}...HEAD").split()
    rows = []
    for name, paths in components.items():
        if not any(f.startswith(p + "/") for f in changed for p in paths):
            continue
        current = max(released_versions(name), default=None)
        before = f"`{tag_name(name, current)}`" if current else "-"
        if level is None:
            rows.append(f"| `{name}` | {before} | no release | |")
        else:
            new = next_version(current, level)
            rows.append(
                f"| `{name}` | {before} | `{tag_name(name, new)}` | `{name}-v{new[0]}` |"
            )
    if not rows:
        summary(["No action is changed by this pull request: no release."])
    else:
        header = [
            "| Action | Current | After merge | Floating tag |",
            "| --- | --- | --- | --- |",
        ]
        summary([f"Releases on merge of `{title}`:", "", *header, *rows])
    return True


def move_tag(repo: str, tag: str, sha: str) -> None:
    ref = f"repos/{repo}/git/refs/tags/{tag}"
    if gh("api", ref, check=False).returncode == 0:
        gh("api", "-X", "PATCH", ref, "-f", f"sha={sha}", "-F", "force=true")
    else:
        gh(
            "api",
            "-X",
            "POST",
            f"repos/{repo}/git/refs",
            "-f",
            f"ref=refs/tags/{tag}",
            "-f",
            f"sha={sha}",
        )


def sync_floating_tags(components: Components, repo: str) -> None:
    """Point every <component>-vX at the latest X.y.z release; idempotent, so a rerun repairs a failed move."""
    for name in components:
        versions = released_versions(name)
        for major in sorted({v[0] for v in versions}):
            target = tag_name(name, max(v for v in versions if v[0] == major))
            sha = git("rev-list", "-n", "1", target).strip()
            floating = f"{name}-v{major}"
            current = subprocess.run(
                ["git", "rev-list", "-n", "1", floating],
                check=False,
                capture_output=True,
                text=True,
            ).stdout.strip()
            if current != sha:
                move_tag(repo, floating, sha)
                print(f"{floating} -> {target} ({sha[:12]})")


def release(components: Components, repo: str) -> None:
    """Release every component with releasing commits since its last tag."""
    head = git("rev-parse", "HEAD").strip()
    released = []
    for name, paths in components.items():
        current = max(released_versions(name), default=None)
        commits = [
            c for c in commits_since(name, paths, current) if bump_level(c[1], c[2])
        ]
        if not commits:
            continue
        level = max(
            (bump_level(subject, body) or "patch" for _, subject, body in commits),
            key=lambda lv: LEVELS[lv],
        )
        version = next_version(current, level)
        tag = tag_name(name, version)
        major = version[0]
        notes = [f"- {subject} ({sha[:12]})" for sha, subject, _ in commits]
        notes += [
            "",
            "```yaml",
            f"uses: centreon/github-actions/{paths[0]}@{name}-v{major}",
            "```",
        ]
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
            f.write("\n".join(notes) + "\n")
        gh(
            "release",
            "create",
            tag,
            "--repo",
            repo,
            "--target",
            head,
            "--title",
            tag,
            "--notes-file",
            f.name,
            "--latest=false",
        )
        git("fetch", "--quiet", "origin", f"refs/tags/{tag}:refs/tags/{tag}")
        released.append(f"- `{tag}` ({level})")
    sync_floating_tags(components, repo)
    summary(["Released:", "", *released] if released else ["Nothing to release."])


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate")
    plan_parser = sub.add_parser("plan")
    plan_parser.add_argument("--title", required=True)
    plan_parser.add_argument("--base", required=True)
    sub.add_parser("release")
    args = parser.parse_args()

    components: Components = json.loads(COMPONENTS_FILE.read_text())
    if not validate(components):
        return 1
    if args.command == "plan":
        return 0 if plan(components, args.title, args.base) else 1
    if args.command == "release":
        release(components, os.environ["GITHUB_REPOSITORY"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
