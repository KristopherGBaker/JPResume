# Contributing

## Requirements

- macOS 15+
- Swift 6.2 (Xcode or Swift toolchain)
- [Mint](https://github.com/yonaskolb/Mint) — manages SwiftLint and XcodeGen

Install tools:

```bash
make bootstrap   # mint bootstrap
```

## Build & test

```bash
make build       # swift build
make test        # swift test
make lint        # swiftlint lint
make fix         # swiftlint lint --fix
make project     # xcodegen generate (regenerate JPResume.xcodeproj)
make install     # release build → /usr/local/bin/jpresume
```

Or directly:

```bash
swift build
swift run jpresume convert examples/resume.md --provider claude-cli --format both
swift run jpresume convert examples/resume.md --dry-run
```

## Tooling

- **SwiftLint** — configured in `.swiftlint.yml`. Must pass with 0 violations before committing.
- **XcodeGen** — `project.yml` generates the Xcode project. Run `make project` after adding new source files.
- **Mint** — `Mintfile` pins tool versions. Run `make bootstrap` after cloning.

## Releases

Releases are tagged `v*` and published to [GitHub Releases](https://github.com/KristopherGBaker/JPResume/releases) as a universal macOS binary (arm64 + x86_64). The Homebrew tap at [KristopherGBaker/homebrew-tap](https://github.com/KristopherGBaker/homebrew-tap) is updated automatically on each release via GitHub Actions.

To cut a release:

1. Bump the version string in `Sources/JPResume/JPResume.swift` and `Sources/JPResume/Pipeline/Artifact.swift`
2. Commit and tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
