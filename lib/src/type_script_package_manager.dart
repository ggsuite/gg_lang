// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/src/project_type.dart';

// #############################################################################

/// The JavaScript/TypeScript package manager in use by a project.
enum TypeScriptPackageManager {
  /// pnpm — detected by `pnpm-lock.yaml`.
  pnpm('pnpm'),

  /// yarn — detected by `yarn.lock`.
  yarn('yarn'),

  /// npm — the default when no lockfile matches.
  npm('npm');

  const TypeScriptPackageManager(this.executable);

  /// The command-line executable that drives this package manager.
  final String executable;

  /// The lock file this package manager writes.
  ///
  /// - pnpm → `pnpm-lock.yaml`
  /// - yarn → `yarn.lock`
  /// - npm  → `package-lock.json`
  String get lockFile => switch (this) {
    TypeScriptPackageManager.pnpm => 'pnpm-lock.yaml',
    TypeScriptPackageManager.yarn => 'yarn.lock',
    TypeScriptPackageManager.npm => 'package-lock.json',
  };

  /// Builds the argv to invoke a locally-installed tool (e.g. `eslint`,
  /// `tsc`) with the given [args].
  ///
  /// - pnpm → `pnpm exec <tool> <args>`
  /// - yarn → `yarn <tool> <args>`   (yarn 1.x runs binaries directly)
  /// - npm  → `npx <tool> <args>`
  ({String executable, List<String> args}) execCommand(
    String tool,
    List<String> args,
  ) {
    return switch (this) {
      TypeScriptPackageManager.pnpm => (
        executable: 'pnpm',
        args: ['exec', tool, ...args],
      ),
      TypeScriptPackageManager.yarn => (
        executable: 'yarn',
        args: [tool, ...args],
      ),
      TypeScriptPackageManager.npm => (
        executable: 'npx',
        args: [tool, ...args],
      ),
    };
  }

  /// Builds the argv to run a `package.json` script (e.g. `test`, `lint`,
  /// `format:check`) named [script].
  ///
  /// All package managers share the `<pm> run <script>` form:
  /// - pnpm → `pnpm run <script>`
  /// - yarn → `yarn run <script>`
  /// - npm  → `npm run <script>`
  ({String executable, List<String> args}) runCommand(String script) {
    return (executable: executable, args: ['run', script]);
  }

  /// Builds the argv to upgrade the project's dependencies.
  ///
  /// - pnpm → `pnpm update [--latest]`
  /// - yarn → `yarn upgrade [--latest]`
  /// - npm  → `npm update` — npm has no cross-major update, so [latest] makes
  ///   no difference there
  ///
  /// [latest] crosses major versions, mirroring `dart pub upgrade
  /// --major-versions`.
  ///
  /// `--no-save` is deliberately *not* passed. It would keep `package.json`
  /// untouched, but a `--latest` that cannot widen the declared range leaves
  /// the lock file resolving outside it, and the next
  /// `pnpm install --frozen-lockfile` in CI fails with
  /// `ERR_PNPM_OUTDATED_LOCKFILE`.
  ({String executable, List<String> args}) updateCommand({
    required bool latest,
  }) => switch (this) {
    TypeScriptPackageManager.pnpm => (
      executable: 'pnpm',
      args: <String>['update', if (latest) '--latest'],
    ),
    TypeScriptPackageManager.yarn => (
      executable: 'yarn',
      args: <String>['upgrade', if (latest) '--latest'],
    ),
    TypeScriptPackageManager.npm => (
      executable: 'npm',
      args: const <String>['update'],
    ),
  };

  /// Builds the argv to hold [package] at [version].
  ///
  /// - pnpm → `pnpm update --save-exact <package>@<version>`
  /// - yarn → `yarn upgrade --exact <package>@<version>`
  /// - npm  → `npm install --save-exact <package>@<version>`
  ///
  /// pnpm gets **no** `--latest`: combined with an explicit spec it refuses
  /// with `ERR_PNPM_LATEST_WITH_SPEC`. Without it, `pnpm update <pkg>@<spec>`
  /// moves the package into the named line in either direction — verified
  /// taking a declared `~7.0.2` down to `6.0.3`.
  ///
  /// `--save-exact` only decides how the *manifest* is rewritten when the
  /// declared spec carries no range operator; pnpm keeps an existing `^`/`~`
  /// and just retargets it (`^7.0.2` → `^6.0.3`). Either way the package stays
  /// inside the pinned major, and the pin re-runs on every upgrade.
  ({String executable, List<String> args}) pinCommand({
    required String package,
    required String version,
  }) => switch (this) {
    TypeScriptPackageManager.pnpm => (
      executable: 'pnpm',
      args: <String>['update', '--save-exact', '$package@$version'],
    ),
    TypeScriptPackageManager.yarn => (
      executable: 'yarn',
      args: <String>['upgrade', '--exact', '$package@$version'],
    ),
    TypeScriptPackageManager.npm => (
      executable: 'npm',
      args: <String>['install', '--save-exact', '$package@$version'],
    ),
  };

  /// Builds the argv to publish the package with this package manager.
  ///
  /// - pnpm → `pnpm publish --no-git-checks` — gg manages git itself and
  ///   publishes from a feature branch, so pnpm's default branch/clean-tree
  ///   checks (which would abort the publish) must be disabled.
  /// - yarn → `yarn publish`
  /// - npm  → `npm publish`
  ({String executable, List<String> args}) get publishCommand => switch (this) {
    TypeScriptPackageManager.pnpm => (
      executable: 'pnpm',
      args: ['publish', '--no-git-checks'],
    ),
    TypeScriptPackageManager.yarn => (executable: 'yarn', args: ['publish']),
    TypeScriptPackageManager.npm => (executable: 'npm', args: ['publish']),
  };
}

// #############################################################################

/// npm packages gg holds at a fixed version instead of letting an upgrade
/// carry them along.
///
/// `pnpm update --latest` crosses every major boundary. TypeScript 7 is a
/// breaking rewrite the toolchain around it is not ready for, so the node
/// upgrade runs the generic update first and then pins these packages — which
/// also brings a repository that already drifted past the pin back down.
///
/// Only packages a repository actually **declares** are pinned. Installing one
/// it never declared would add it as a new dependency.
const Map<String, String> pinnedNpmVersions = <String, String>{
  'typescript': '6',
};

// #############################################################################

/// Detects the [TypeScriptPackageManager] of [directory] by looking at the
/// lockfiles present. Falls back to [TypeScriptPackageManager.npm].
TypeScriptPackageManager detectTypeScriptPackageManager(Directory directory) {
  if (File('${directory.path}/pnpm-lock.yaml').existsSync()) {
    return TypeScriptPackageManager.pnpm;
  }
  if (File('${directory.path}/yarn.lock').existsSync()) {
    return TypeScriptPackageManager.yarn;
  }
  return TypeScriptPackageManager.npm;
}

// #############################################################################

/// Returns the dependency lock file name for the project in [directory].
///
/// `pubspec.lock` for Dart/Flutter, and the package-manager-specific lock
/// file for TypeScript (`package-lock.json` for npm, `yarn.lock` for yarn,
/// `pnpm-lock.yaml` for pnpm — detected from the lock files present).
///
/// Throws an [ArgumentError] for [ProjectType.none] — a project without a
/// manifest has no lock file.
String lockFileFor(Directory directory) {
  final type = detectProjectType(directory);
  if (type == ProjectType.none) {
    throw ArgumentError(
      'No lock file exists for "${directory.path}" — '
      'a project without a manifest has no lock file.',
    );
  }
  return type.isDartFamily
      ? 'pubspec.lock'
      : detectTypeScriptPackageManager(directory).lockFile;
}

// #############################################################################

/// All lock file names any supported language or package manager writes.
///
/// Unlike [lockFileFor] this is not tied to one project type: bridge repos
/// (pubspec.yaml + package.json) can carry lock files of both ecosystems, so
/// callers that classify lock-file changes (e.g. as regenerable drift) need
/// the full set.
final Set<String> allLockFileNames = {
  'pubspec.lock',
  for (final manager in TypeScriptPackageManager.values) manager.lockFile,
};
