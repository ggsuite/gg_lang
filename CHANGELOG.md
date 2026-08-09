# Changelog

## 0.5.0 - 2026-08-09

### Added

- `PublishTarget`, `publishTargetsOf` and the `PublishTargetsX` extension — a
package can now have a *set* of registries instead of one. Both manifests of a
hybrid are read independently, so `publish_to: none` takes the Dart side out
without touching the npm side and `private: true` does the reverse. This is
what lets a hybrid publish to pub.dev **and** npm; `checkProjectType`, which
resolves a hybrid to a single `ProjectType`, cannot express that.
- `hybridVersions` / `hybridVersionsDiffer` — read both manifest versions of a
hybrid, for reconciling them and for deciding whether pana can run.
- `NpmRegistryResolver` and the pure `npmStatusUrlTemplate` — resolve the
registry a package actually publishes to from the merged `.npmrc`
(`publishConfig.registry` → `@scope:registry` → `registry`) and derive the
human-facing status page from it. The npm registry and Azure Artifacts (cloud,
organization-scoped, legacy `*.pkgs.visualstudio.com` and self-hosted) are
mapped to their web pages; anything else falls back to the packument url.
Before, the publish flow always printed an `npmjs.com` link, which is wrong for
every scoped package on a private feed. Only the `registry` keys are ever read
— never the `_authToken`/`_auth` credentials next to them.
- `TypeScriptPackageManager.updateCommand({required bool latest})` — the argv to
upgrade dependencies, so `gg do upgrade deps` can reach the node side.

### Changed

- Allow to publish hybrid packages

## 0.4.1 - 2026-08-08

### Added

- `isHybridProject` — the predicate under its new name. `isBridgeProject`
keeps working as an alias but now carries the widened meaning; "bridge"
suggested a repo bridging two languages, while the rule is really about a
repo carrying two manifests.

### Changed

- A hybrid repository — one carrying both a `pubspec.yaml` and a
`package.json` — is recognized as such without a `tsconfig.json`, and
`checkProjectType` resolves it to `ProjectType.typescript`. Before, the
detection additionally required a `tsconfig.json`, so a Dart package that
publishes its payload as an npm tarball fell through to
`ProjectType.dart`: gg ran only the Dart pipeline on it, never the npm
scripts, never wrote its `package.json` version, and never published it to
npm.
- Allow to publish pnpm packages without typescript.

## 0.4.0 - 2026-08-04

### Changed

- Rename .master to .ocean with automatic migration at next start

## 0.3.3 - 2026-08-04

### Changed

- Finetune command line output

## 0.3.2 - 2026-07-31

### Changed

- Print »waiting until ... appears on pub.dev only one time
- Merge main

## 0.3.1 - 2026-07-30

### Added

- RegistryWaiter.resetAnnouncements: clears the process-wide announcement
state so tests can assert the start message per test

### Changed

- Waiting until appears multiple times

### Fixed

- RegistryWaiter.waitUntilVersionAvailable announces a wait at most once per
version and process. The publish flow waits for the same version from more
than one place — the repo publishing it, then later repos depending on it —
and each place builds its own waiter, so the »Waiting until … appears on
pub.dev« message was printed more than once.
- A version that is already visible returns without logging anything: there
is no wait to report.
- A repeated wait no longer repeats the announcement — a stale registry
response or a transient lookup error can make a published version look
unpublished again. Progress, success and timeout messages are unaffected.

## 0.3.0 - 2026-07-29

### Changed

- Support projects without manifest: ProjectType.none, checks skipped,
version tracked as git tag only

## 0.2.7 - 2026-07-29

### Changed

- RegistryWaiter prints its wait and progress messages in dark gray, the
status url in blue and the success message in green
- Print registry wait messages dark gray, status url blue, success green

## 0.2.6 - 2026-07-29

### Added

- RegistrySpec.statusUrl + statusUrlFor: human-facing status page url
(pub.dev versions page, npmjs.com package page) resolved from the language
catalog
- RegistryWaiter: optional log callback and statusUrl — announces the wait
incl. the status page url, reports periodic progress and includes the url in
the timeout error
- Add registry request timeouts, RegistryWaiter logging and status urls

### Fixed

- PubDevRegistry and NpmRegistry now bound every single lookup with a
request timeout (RegistryException instead of hanging forever on a stalled
HTTP connection or an npm process waiting for interactive input)
- NpmRegistry.latestVersion no longer reads the "latest" dist-tag. Private
feeds (e.g. Azure Artifacts) can leave the tag pointing at an older release,
which made an already published version look unpublished and rejected the
correct next version. The published version list is now authoritative,
preferring the highest stable release and falling back to prereleases only
when nothing stable exists.

## 0.2.5 - 2026-07-28

### Changed

- Do not trust the npm latest dist-tag when reading the published version

## 0.2.4 - 2026-07-22

### Changed

- Run npm registry lookups in the package directory so the project-level
.npmrc with private feeds is honored

### Fixed

- Fix .gitignore so .gg/.gg.json is trackable and expose allLockFileNames
for lock-file classification

## 0.2.3 - 2026-07-20

### Added

- Add rc prerelease channel to gg do publish (channel field/flag,
X.Y.Z-rc.N computation, npm --tag rc, single + multi repo)
- Address review: wrap registry version-parse errors as RegistryException,
clarify spent-version rc message, lock cider rc changelog format

## 0.2.2 - 2026-07-15

### Changed

- Make LanguageCatalog.load AOT-safe: embed languages.json as Dart constant
instead of Isolate.resolvePackageUri asset lookup
- Gg Multi: changed references to pub.dev

## 0.2.1 - 2026-06-26

### Changed

- Preserve dependency constraint operator (^^/~/exact) through publish

## 0.2.0 - 2026-06-19

### Changed

- Treat dart-typescript bridge repos as TypeScript for can/do commit,
running package.json scripts (test/lint/format:check)
- Treat dart-typescript bridge repos as TypeScript for can/do review (npm
install, skip dart pub get); export isBridgeProject from gg_one
- Introduce checkProjectType() as single source of truth for
bridge->TypeScript check rule; add .example() real-instance factories &
P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- Publish bridges as TypeScript: pnpm-aware publish, dual-manifest version
bump, non-swallowed publish errors, idempotent resume, review skips merged
repos, link: for local TS deps, package.json scripts check

## 0.1.0 - 2026-06-08

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

- chore: prepare gg_lang 0.0.1 for publishing (remove publish_to:none,
changelog)
- feat(do add): auto-clone transitive deps into master before graph build &
P:\programs\flutter/bin/internal/exit_with_errorlevel.bat
- feat(gg_lang): add example/ for pana compliance

## 0.0.1 - 2026-06-01

### Added

- Initial release: `ProjectType` / `detectProjectType`,
`TypeScriptPackageManager`, and the `LanguageCatalog` with a bundled
`languages.json` asset — the shared catalog of language-specific commands
(install / analyze / format / test / publish / registryVersion) and package
metadata for Dart, Flutter and TypeScript. Extracted from `gg_one` so it can
be shared by `gg_one`, `gg_test` and `gg_publish` without circular
dependencies.
