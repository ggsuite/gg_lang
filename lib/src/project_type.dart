// @license
// Copyright (c) ggsuite
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

  /// A TypeScript project (package.json + tsconfig.json), and the type gg's
  /// check pipeline uses for a hybrid — see [checkProjectType].
  typescript,

  /// A directory without a recognizable language manifest — no pubspec.yaml
  /// and no package.json + tsconfig.json pair.
  ///
  /// gg runs its plain git workflow on such projects: language checks
  /// (analyze / format / build / tests) are skipped and the version lives
  /// exclusively in git tags. Note that a `package.json` without a
  /// `tsconfig.json` also resolves to this type — unless a `pubspec.yaml`
  /// sits next to it, which makes the directory a hybrid.
  none,
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

  /// Whether this project type carries a language manifest
  /// (pubspec.yaml or package.json).
  ///
  /// Only [ProjectType.none] has no manifest — such projects have no
  /// registry, no lock file and no manifest based version.
  bool get hasManifest => this != ProjectType.none;
}

// #############################################################################

/// Detects the [ProjectType] of [directory] — which manifest the directory
/// carries, not which pipeline gg should run on it. For the latter, use
/// [checkProjectType].
///
/// Detection rules, in order:
/// 1. `pubspec.yaml` with a top-level `flutter:` key, or one depending on the
///    Flutter SDK → [ProjectType.flutter]
/// 2. `pubspec.yaml` → [ProjectType.dart]
/// 3. `package.json` + `tsconfig.json` → [ProjectType.typescript]
/// 4. otherwise → [ProjectType.none]
///
/// Note that rule 2 also catches hybrids: a repo with both manifests reports
/// its Dart side here, which is exactly what callers keeping the two sides in
/// lock-step need (version files, manifest bumps).
ProjectType detectProjectType(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  if (pubspec.existsSync()) {
    final content = pubspec.readAsStringSync();
    if (_hasTopLevelFlutterKey(content) || _dependsOnFlutterSdk(content)) {
      return ProjectType.flutter;
    }
    return ProjectType.dart;
  }

  final packageJson = File('${directory.path}/package.json');
  final tsconfig = File('${directory.path}/tsconfig.json');
  if (packageJson.existsSync() && tsconfig.existsSync()) {
    return ProjectType.typescript;
  }

  return ProjectType.none;
}

// #############################################################################

/// Whether [directory] is a *hybrid* project — a repo that ships a Dart
/// manifest (`pubspec.yaml`) and a TypeScript manifest (`package.json`)
/// side by side.
///
/// A `tsconfig.json` is deliberately not required. Plenty of hybrids carry
/// no TypeScript sources at all: a Dart package that additionally publishes
/// its payload as an npm tarball is one manifest short of a compiler
/// config, yet it still has two manifests, two registries and two versions
/// to keep in lock-step — which is what every caller of this predicate
/// actually cares about.
///
/// [detectProjectType] resolves such a directory to [ProjectType.dart],
/// because pubspec.yaml takes precedence. The gg check pipeline
/// (analyze/format/tests) treats hybrids as TypeScript instead, so it needs
/// to recognize them explicitly — see [checkProjectType].
bool isHybridProject(Directory directory) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  final packageJson = File('${directory.path}/package.json');
  return pubspec.existsSync() && packageJson.existsSync();
}

/// Former name of [isHybridProject], kept so callers keep compiling.
///
/// Mind the widened meaning: this used to require a `tsconfig.json` as well,
/// and now does not. Prefer [isHybridProject] in new code — "bridge" suggested
/// a repo bridging two *languages*, while the predicate is really about a repo
/// carrying two *manifests*.
bool isBridgeProject(Directory directory) => isHybridProject(directory);

// #############################################################################

/// The [ProjectType] that gg's check pipeline (analyze / format / tests)
/// should use for [directory].
///
/// This is the single source of truth for the rule "hybrid repos are checked
/// as TypeScript": a hybrid (see [isHybridProject]) resolves to
/// [ProjectType.typescript], everything else is delegated to
/// [detectProjectType]. Prefer this over hand-writing
/// `isHybridProject(d) ? ProjectType.typescript : detectProjectType(d)` so the
/// rule lives in one place.
///
/// TypeScript wins because the npm scripts are the outer shell of a hybrid:
/// `pnpm test` chains the Dart tests, `pnpm build` produces both artifacts.
/// Running the Dart pipeline separately would duplicate that work.
ProjectType checkProjectType(Directory directory) => isHybridProject(directory)
    ? ProjectType.typescript
    : detectProjectType(directory);

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

// .............................................................................
/// Whether [pubspecContent] declares a dependency on the Flutter SDK, i.e.
/// carries a `flutter:` entry followed by `sdk: flutter`.
///
/// A top-level `flutter:` section is not enough to recognize a Flutter
/// package: it holds assets, fonts and `uses-material-design`, none of which
/// a plain widget library needs. Such a package — `supply_chain_flutter` is
/// one — has `flutter:` only under `environment:` and `dependencies:`, and was
/// therefore classified as plain Dart. The SDK dependency is what actually
/// makes a package Flutter, and it is the signal `gg_is_flutter` reads too.
bool _dependsOnFlutterSdk(String pubspecContent) {
  var sawFlutterKey = false;

  for (final rawLine in pubspecContent.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    if (line.trim().startsWith('#')) continue;

    // »  flutter:« — the dependency entry, indented under dependencies: or
    // dev_dependencies:. The top-level form is handled by the caller.
    if (line.startsWith(' ') && line.trim() == 'flutter:') {
      sawFlutterKey = true;
      continue;
    }

    if (sawFlutterKey) {
      if (line.trim() == 'sdk: flutter') {
        return true;
      }
      // Only the line directly below the key describes it; »environment:«
      // uses »flutter: ">=3.47.0"«, which never reaches this branch because
      // it does not match the bare-key test above.
      if (line.trim().isNotEmpty) {
        sawFlutterKey = false;
      }
    }
  }

  return false;
}
