# Changelog

## [Unreleased]

### Changed

- Support projects without manifest: ProjectType.none, checks skipped, version tracked as git tag only

## [0.2.7] - 2026-07-29

### Changed

- RegistryWaiter prints its wait and progress messages in dark gray, the status url in blue and the success message in green
- Print registry wait messages dark gray, status url blue, success green

## [0.2.6] - 2026-07-29

### Added

- RegistrySpec.statusUrl + statusUrlFor: human-facing status page url (pub.dev versions page, npmjs.com package page) resolved from the language catalog
- RegistryWaiter: optional log callback and statusUrl — announces the wait incl. the status page url, reports periodic progress and includes the url in the timeout error
- Add registry request timeouts, RegistryWaiter logging and status urls

### Fixed

- PubDevRegistry and NpmRegistry now bound every single lookup with a request timeout (RegistryException instead of hanging forever on a stalled HTTP connection or an npm process waiting for interactive input)
- NpmRegistry.latestVersion no longer reads the "latest" dist-tag. Private feeds (e.g. Azure Artifacts) can leave the tag pointing at an older release, which made an already published version look unpublished and rejected the correct next version. The published version list is now authoritative, preferring the highest stable release and falling back to prereleases only when nothing stable exists.

## [0.2.5] - 2026-07-28

### Changed

- Do not trust the npm latest dist-tag when reading the published version

## [0.2.4] - 2026-07-22

### Changed

- Run npm registry lookups in the package directory so the project-level .npmrc with private feeds is honored

### Fixed

- Fix .gitignore so .gg/.gg.json is trackable and expose allLockFileNames for lock-file classification

## [0.2.3] - 2026-07-20

### Added

- Add rc prerelease channel to gg do publish (channel field/flag, X.Y.Z-rc.N computation, npm --tag rc, single + multi repo)
- Address review: wrap registry version-parse errors as RegistryException, clarify spent-version rc message, lock cider rc changelog format

## [0.2.2] - 2026-07-15

### Changed

- Make LanguageCatalog.load AOT-safe: embed languages.json as Dart constant instead of Isolate.resolvePackageUri asset lookup
- Gg Multi: changed references to pub.dev

## [0.2.1] - 2026-06-26

### Changed

- Preserve dependency constraint operator (^^/\~/exact) through publish

## [0.2.0] - 2026-06-19

### Changed

- Treat dart-typescript bridge repos as TypeScript for can/do commit, running package.json scripts (test/lint/format:check)
- Treat dart-typescript bridge repos as TypeScript for can/do review (npm install, skip dart pub get); export isBridgeProject from gg\_one
- Introduce checkProjectType() as single source of truth for bridge->TypeScript check rule; add .example() real-instance factories & P:\programs\flutter/bin/internal/exit\_with\_errorlevel.bat
- Publish bridges as TypeScript: pnpm-aware publish, dual-manifest version bump, non-swallowed publish errors, idempotent resume, review skips merged repos, link: for local TS deps, package.json scripts check

## [0.1.0] - 2026-06-08

### Added

- `Manifest` — format-driven accessor that reads and writes package name,
version and publish-target marker for both `pubspec.yaml` (yaml, via
`yaml_edit` so formatting/comments survive) and `package.json` (json), driven
by `ManifestSpec`. Includes `isPrivate()` and a `Manifest.detect` factory.
- `Registry` abstraction with `PubDevRegistry` (pub.dev HTTP API) and
`NpmRegistry` (`npm view <name> version`), plus a `RegistryFactory` that picks
the implementation from the new `RegistrySpec` in the catalog.
- `RegistrySpec` and `LanguageSpec.registry`; `languages.json` now describes
the registry for dart/flutter (http) and typescript (cli).

### Changed

- chore: prepare gg\_lang 0.0.1 for publishing (remove publish\_to:none, changelog)
- feat(do add): auto-clone transitive deps into master before graph build & P:\programs\flutter/bin/internal/exit\_with\_errorlevel.bat
- feat(gg\_lang): add example/ for pana compliance

## [0.0.1] - 2026-06-01

### Added

- Initial release: `ProjectType` / `detectProjectType`,
`TypeScriptPackageManager`, and the `LanguageCatalog` with a bundled
`languages.json` asset — the shared catalog of language-specific commands
(install / analyze / format / test / publish / registryVersion) and package
metadata for Dart, Flutter and TypeScript. Extracted from `gg_one` so it can
be shared by `gg_one`, `gg_test` and `gg_publish` without circular
dependencies.

[Unreleased]: https://github.com/ggsuite/gg_lang/compare/0.2.7...HEAD
[0.2.7]: https://github.com/ggsuite/gg_lang/compare/0.2.6...0.2.7
[0.2.6]: https://github.com/ggsuite/gg_lang/compare/0.2.5...0.2.6
[0.2.5]: https://github.com/ggsuite/gg_lang/compare/0.2.4...0.2.5
[0.2.4]: https://github.com/ggsuite/gg_lang/compare/0.2.3...0.2.4
[0.2.3]: https://github.com/ggsuite/gg_lang/compare/0.2.2...0.2.3
[0.2.2]: https://github.com/ggsuite/gg_lang/compare/0.2.1...0.2.2
[0.2.1]: https://github.com/ggsuite/gg_lang/compare/0.2.0...0.2.1
[0.2.0]: https://github.com/ggsuite/gg_lang/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/ggsuite/gg_lang/compare/0.0.1...0.1.0
[0.0.1]: https://github.com/ggsuite/gg_lang/releases/tag/0.0.1
