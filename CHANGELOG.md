# Changelog

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

[0.2.0]: https://github.com/ggsuite/gg_lang/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/ggsuite/gg_lang/compare/0.0.1...0.1.0
[0.0.1]: https://github.com/ggsuite/gg_lang/releases/tag/0.0.1
