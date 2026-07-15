# gg_lang

Shared language definitions for the gg toolchain.

`gg_lang` provides:

- `ProjectType` and `detectProjectType` — detect whether a directory holds a
  Dart, Flutter or TypeScript project.
- `LanguageCatalog` — the catalog of all language-specific commands
  (install, analyze, format, test, publish, ...) and package metadata. The
  catalog is embedded as a Dart constant, so `LanguageCatalog.load` also
  works in AOT-compiled executables (no runtime asset lookup via
  `Isolate.resolvePackageUri`).

It lives in its own package so that `gg_one`, `gg_test` and `gg_publish` can all
share the same catalog without creating circular dependencies.

## Extending to a new language

Add an entry to `lib/src/assets/languages.json` describing the language's
commands and manifest, copy the JSON content into the constant in
`lib/src/assets/languages_json.dart` (a test enforces that both stay in
sync), then add the matching `ProjectType` value.
