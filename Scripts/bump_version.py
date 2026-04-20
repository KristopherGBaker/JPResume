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


def main() -> int:
    parser = argparse.ArgumentParser(description="Bump the JPResume release version across source and docs.")
    parser.add_argument("version", help="New semantic version, for example 0.4.2")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate that all managed version references already match the provided version.",
    )
    args = parser.parse_args()

    if not SEMVER_RE.fullmatch(args.version):
        raise SystemExit(f"Version must be semantic versioning like 0.4.2, got: {args.version}")

    repo_root = Path(__file__).resolve().parent.parent
    managed_files = [
        repo_root / "Sources/JPResume/JPResume.swift",
        repo_root / "Sources/JPResume/Pipeline/Artifact.swift",
        repo_root / "docs/cli.md",
        repo_root / "CLAUDE.md",
        repo_root / "docs/contributing.md",
    ]

    if args.check:
        mismatches: list[str] = []

        jpresume = (repo_root / "Sources/JPResume/JPResume.swift").read_text()
        if f'version: "{args.version}"' not in jpresume:
            mismatches.append("Sources/JPResume/JPResume.swift")

        artifact = (repo_root / "Sources/JPResume/Pipeline/Artifact.swift").read_text()
        if f'static let version = "{args.version}"' not in artifact:
            mismatches.append("Sources/JPResume/Pipeline/Artifact.swift")

        cli_doc = (repo_root / "docs/cli.md").read_text()
        if f"jpresume/{args.version}" not in cli_doc:
            mismatches.append("docs/cli.md")

        claude = (repo_root / "CLAUDE.md").read_text()
        if f"jpresume/{args.version}" not in claude:
            mismatches.append("CLAUDE.md")

        verify_contributing_doc(repo_root / "docs/contributing.md")

        if mismatches:
            raise SystemExit("Version mismatch in: " + ", ".join(mismatches))

        print(f"All managed version references already match {args.version}")
        return 0

    changed_files: list[Path] = []
    for path in managed_files:
        if update_file(path, args.version):
            changed_files.append(path)

    verify_contributing_doc(repo_root / "docs/contributing.md")

    if changed_files:
        print(f"Bumped version to {args.version} in:")
        for path in changed_files:
            print(f"- {path.relative_to(repo_root)}")
    else:
        print(f"No changes needed; managed version references already match {args.version}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
