// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

// #############################################################################

/// The kind of project gg is operating on.
enum ProjectType {
  /// A pure Dart package (pubspec.yaml without a `flutter:` section).
  dart,

  /// A Flutter package (pubspec.yaml with a `flutter:` section).
  flutter,

  /// A TypeScript project (package.json + tsconfig.json).
  typescript,
}

/// Convenience predicates on [ProjectType].
extension ProjectTypeX on ProjectType {
  /// Whether this is a Dart-family project (Dart or Flutter).
  ///
  /// These project types share the pubspec.yaml manifest, the pub.dev
  /// registry and the CHANGELOG.md/cider based versioning flow — many gg
  /// commands branch on exactly this distinction.
  bool get isDartFamily =>
      this == ProjectType.dart || this == ProjectType.flutter;
}

// #############################################################################

/// Detects the [ProjectType] of [directory].
///
/// Detection rules, in order:
/// 1. `pubspec.yaml` with a top-level `flutter:` key → [ProjectType.flutter]
/// 2. `pubspec.yaml` → [ProjectType.dart]
/// 3. `package.json` + `tsconfig.json` → [ProjectType.typescript]
///
/// Throws an [Exception] if the directory matches none of the above.
ProjectType detectProjectType(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (pubspec.existsSync()) {
    final content = pubspec.readAsStringSync();
    if (_hasTopLevelFlutterKey(content)) {
      return ProjectType.flutter;
    }
    return ProjectType.dart;
  }

  final packageJson = File('${directory.path}/package.json');
  final tsconfig = File('${directory.path}/tsconfig.json');
  if (packageJson.existsSync() && tsconfig.existsSync()) {
    return ProjectType.typescript;
  }

  throw Exception(
    'Could not detect project type in "${directory.path}". '
    'Expected pubspec.yaml (Dart/Flutter) or '
    'package.json + tsconfig.json (TypeScript).',
  );
}

// #############################################################################

/// Whether [directory] is a cross-language *bridge* project — a repo that
/// ships both a Dart manifest (`pubspec.yaml`) and a TypeScript manifest
/// (`package.json` + `tsconfig.json`) side by side.
///
/// [detectProjectType] resolves such a directory to [ProjectType.dart],
/// because pubspec.yaml takes precedence. The gg check pipeline
/// (analyze/format/tests) treats bridges as TypeScript instead, so it needs
/// to recognize them explicitly.
bool isBridgeProject(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  final packageJson = File('${directory.path}/package.json');
  final tsconfig = File('${directory.path}/tsconfig.json');
  return pubspec.existsSync() &&
      packageJson.existsSync() &&
      tsconfig.existsSync();
}

// .............................................................................
bool _hasTopLevelFlutterKey(String pubspecContent) {
  for (final rawLine in pubspecContent.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;
    // A top-level key starts at column zero; nested keys are indented.
    if (line.startsWith('flutter:')) {
      return true;
    }
  }
  return false;
}
