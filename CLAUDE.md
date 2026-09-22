## Hybrid packages

A *hybrid* carries both a `pubspec.yaml` and a `package.json` and publishes the
same payload to pub.dev **and** npm. `checkProjectType` resolves such a
directory to a single `ProjectType.typescript`, which cannot express two
registries — that mapping stays, because the check pipeline (analyze / format /
tests) really does run through the npm scripts.

Publishing decisions therefore do **not** ask for the project type. They ask
`publishTargetsOf(dir)` (`lib/src/publish_targets.dart`), which reads both
manifests independently: `publish_to: none` takes the Dart side out without
touching the npm side, and `private: true` does the reverse. `PublishTarget`
carries the per-registry manifest/spec lookups (`manifestIn`, `specIn`,
`projectTypeIn`) so a caller never has to branch on the language itself, and
`hybridVersions` / `hybridVersionsDiffer` expose the two version numbers that
have to be kept in lock-step.

`NpmRegistryResolver` (`lib/src/npm_registry_resolver.dart`) answers "which npm
registry does this package actually publish to" from the merged `.npmrc`
(`publishConfig.registry` → `@scope:registry` → `registry`, via
`<pm> config get`), and the pure `npmStatusUrlTemplate` derives the human-facing
status page from it — npmjs.com, an Azure Artifacts feed page, or the packument
url as a last resort. It reads only the `registry` keys, never the credentials
next to them. `NpmLoggedIn`, `WaitUntilPublished` and `NpmRegistryChecker` all
share it.

<!-- helix:claude_md:start -->

# gg workflow

This repo is developed ticket by ticket with the `gg` CLI. Follow the
development guide, it tells you when to ask the user and which command
comes next:

@doc/guides/for-ai/ai-dev-guide.md

The steps are also available as skills: `/gg-ticket`, `/gg-commit`,
`/gg-push`, `/gg-publish`, `/gg-cleanup`. `/gg` lists them and says which
one comes next.

<!-- helix:claude_md:end -->
