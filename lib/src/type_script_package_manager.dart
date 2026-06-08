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
}

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
String lockFileFor(Directory directory) {
  final type = detectProjectType(directory);
  return type.isDartFamily
      ? 'pubspec.lock'
      : detectTypeScriptPackageManager(directory).lockFile;
}
