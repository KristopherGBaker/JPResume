#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")


def replace_one(text: str, pattern: str, replacement: str, path: Path) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"Expected to update exactly one match in {path}, got {count}")
    return updated


def update_file(path: Path, version: str) -> bool:
    original = path.read_text()
    updated = original

    if path.name == "JPResume.swift":
        updated = replace_one(
            updated,
            r'version:\s*"\d+\.\d+\.\d+"',
            f'version: "{version}"',
            path,
        )
    elif path.name == "Artifact.swift":
        updated = replace_one(
            updated,
            r'static let version = "\d+\.\d+\.\d+"',
            f'static let version = "{version}"',
            path,
        )
    elif path.name == "cli.md":
        updated, count = re.subn(r"jpresume/\d+\.\d+\.\d+", f"jpresume/{version}", updated)
        if count < 1:
            raise SystemExit(f"Expected at least one doc version example in {path}")
    elif path.name == "CLAUDE.md":
        updated, count = re.subn(r"jpresume/\d+\.\d+\.\d+", f"jpresume/{version}", updated)
        if count < 1:
            raise SystemExit(f"Expected at least one produced_by version example in {path}")
    elif path.name == "contributing.md":
        if "1. Run `python3 Scripts/bump_version.py X.Y.Z`" not in updated:
            updated = replace_one(
                updated,
                r"1\. Bump the version string in `Sources/JPResume/JPResume\.swift` and `Sources/JPResume/Pipeline/Artifact\.swift`",
                "1. Run `python3 Scripts/bump_version.py X.Y.Z`",
                path,
            )
        if "2. Review the diff, commit it, then tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`" not in updated:
            updated = replace_one(
                updated,
                r"2\. Commit and tag: `git tag vX\.Y\.Z && git push origin vX\.Y\.Z`",
                "2. Review the diff, commit it, then tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`",
                path,
            )
    else:
        raise SystemExit(f"No update rule for {path}")

    if updated != original:
        path.write_text(updated)
        return True
    return False


def verify_contributing_doc(path: Path) -> None:
    text = path.read_text()
    if "python3 Scripts/bump_version.py X.Y.Z" not in text:
        raise SystemExit(f"Expected release instructions to mention bump_version.py in {path}")


def parse_version(version: str) -> tuple[int, int, int]:
    if not SEMVER_RE.fullmatch(version):
        raise SystemExit(f"Version must be semantic versioning like 0.4.2, got: {version}")
    major, minor, patch = version.split(".")
    return int(major), int(minor), int(patch)


def format_version(parts: tuple[int, int, int]) -> str:
    major, minor, patch = parts
    return f"{major}.{minor}.{patch}"


def read_current_version(repo_root: Path) -> str:
    jpresume = (repo_root / "Sources/JPResume/JPResume.swift").read_text()
    match = re.search(r'version:\s*"(\d+\.\d+\.\d+)"', jpresume)
    if not match:
        raise SystemExit("Could not find current version in Sources/JPResume/JPResume.swift")
    return match.group(1)


def increment_version(current_version: str, part: str) -> str:
    major, minor, patch = parse_version(current_version)
    if part == "major":
        return format_version((major + 1, 0, 0))
    if part == "minor":
        return format_version((major, minor + 1, 0))
    if part == "patch":
        return format_version((major, minor, patch + 1))
    raise SystemExit(f"Unsupported increment part: {part}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bump the JPResume release version across source and docs.")
    parser.add_argument("version", nargs="?", help="New semantic version, for example 0.4.2")
    parser.add_argument(
        "--part",
        choices=["major", "minor", "patch"],
        help="Increment the current version by one semantic version part.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate that all managed version references already match the provided version.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    managed_files = [
        repo_root / "Sources/JPResume/JPResume.swift",
        repo_root / "Sources/JPResume/Pipeline/Artifact.swift",
        repo_root / "docs/cli.md",
        repo_root / "CLAUDE.md",
        repo_root / "docs/contributing.md",
    ]

    if args.version and args.part:
        raise SystemExit("Specify either an explicit version or --part, not both")
    if not args.version and not args.part:
        raise SystemExit("Provide either an explicit version or --part {major,minor,patch}")

    current_version = read_current_version(repo_root)
    target_version = args.version if args.version else increment_version(current_version, args.part)
    parse_version(target_version)

    if args.check:
        mismatches: list[str] = []

        jpresume = (repo_root / "Sources/JPResume/JPResume.swift").read_text()
        if f'version: "{target_version}"' not in jpresume:
            mismatches.append("Sources/JPResume/JPResume.swift")

        artifact = (repo_root / "Sources/JPResume/Pipeline/Artifact.swift").read_text()
        if f'static let version = "{target_version}"' not in artifact:
            mismatches.append("Sources/JPResume/Pipeline/Artifact.swift")

        cli_doc = (repo_root / "docs/cli.md").read_text()
        if f"jpresume/{target_version}" not in cli_doc:
            mismatches.append("docs/cli.md")

        claude = (repo_root / "CLAUDE.md").read_text()
        if f"jpresume/{target_version}" not in claude:
            mismatches.append("CLAUDE.md")

        verify_contributing_doc(repo_root / "docs/contributing.md")

        if mismatches:
            raise SystemExit("Version mismatch in: " + ", ".join(mismatches))

        print(f"All managed version references already match {target_version}")
        return 0

    changed_files: list[Path] = []
    for path in managed_files:
        if update_file(path, target_version):
            changed_files.append(path)

    verify_contributing_doc(repo_root / "docs/contributing.md")

    if changed_files:
        print(f"Bumped version from {current_version} to {target_version} in:")
        for path in changed_files:
            print(f"- {path.relative_to(repo_root)}")
    else:
        print(f"No changes needed; managed version references already match {target_version}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
