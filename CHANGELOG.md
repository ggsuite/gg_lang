# Changelog

## [Unreleased]

### Changed

- chore: prepare gg\_lang 0.0.1 for publishing (remove publish\_to:none, changelog)

## [0.0.1] - 2026-06-01

### Added

- Initial release: `ProjectType` / `detectProjectType`,
`TypeScriptPackageManager`, and the `LanguageCatalog` with a bundled
`languages.json` asset — the shared catalog of language-specific commands
(install / analyze / format / test / publish / registryVersion) and package
metadata for Dart, Flutter and TypeScript. Extracted from `gg_one` so it can
be shared by `gg_one`, `gg_test` and `gg_publish` without circular
dependencies.

[Unreleased]: https://github.com/ggsuite/gg_lang/compare/0.0.1...HEAD
[0.0.1]: https://github.com/ggsuite/gg_lang/releases/tag/0.0.1
