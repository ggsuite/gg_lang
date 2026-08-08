// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/src/language_catalog.dart';
import 'package:gg_lang/src/manifest.dart';
import 'package:gg_lang/src/project_type.dart';
import 'package:pub_semver/pub_semver.dart';

// #############################################################################

/// A public package registry gg can upload to.
///
/// A single-language package has at most one. A *hybrid* — a directory carrying
/// both a `pubspec.yaml` and a `package.json`, see [isHybridProject] — can have
/// both, and each side decides for itself: `publish_to: none` takes the Dart
/// side out without touching the npm side, and `private: true` does the
/// reverse.
///
/// This enum exists because [checkProjectType] resolves a hybrid to a *single*
/// [ProjectType], which cannot express »pub.dev and npm«. Publishing decisions
/// therefore ask [publishTargetsOf] instead of the project type.
enum PublishTarget {
  /// The Dart registry, described by `pubspec.yaml`.
  pubDev('pub.dev'),

  /// The Node registry, described by `package.json`.
  npm('npm');

  const PublishTarget(this.id);

  /// The registry name used in messages and in `done_steps` markers.
  final String id;

  /// The [ProjectType] whose catalog entry describes this target in
  /// [directory].
  ///
  /// For [PublishTarget.pubDev] this is [detectProjectType], which gives
  /// `pubspec.yaml` precedence and therefore answers `dart` or `flutter` even
  /// for a hybrid. For [PublishTarget.npm] it is always
  /// [ProjectType.typescript] — the catalog keys the `package.json` manifest
  /// and the npm registry under that name regardless of whether the repo ships
  /// any TypeScript sources.
  ProjectType projectTypeIn(Directory directory) => switch (this) {
    PublishTarget.pubDev => detectProjectType(directory),
    PublishTarget.npm => ProjectType.typescript,
  };

  /// The catalog entry for this target in [directory] — registry url, status
  /// url and publish command.
  LanguageSpec specIn(Directory directory, LanguageCatalog catalog) =>
      catalog.spec(projectTypeIn(directory));

  /// The manifest this target publishes: `pubspec.yaml` for
  /// [PublishTarget.pubDev], `package.json` for [PublishTarget.npm].
  ///
  /// Deliberately not [Manifest.detect]: that resolves a hybrid to exactly one
  /// manifest, which is the assumption this enum exists to break.
  Manifest manifestIn(Directory directory, LanguageCatalog catalog) =>
      Manifest(directory: directory, spec: specIn(directory, catalog).manifest);
}

// #############################################################################

/// Convenience predicates on a set of [PublishTarget]s.
extension PublishTargetsX on Set<PublishTarget> {
  /// The targets in upload order: pub.dev first, npm second.
  ///
  /// pub.dev goes first because `dart pub publish --dry-run` is the only
  /// pre-upload validation gate in the publish flow — a package that fails it
  /// should fail before anything reached any registry.
  List<PublishTarget> get ordered => <PublishTarget>[
    for (final target in PublishTarget.values)
      if (contains(target)) target,
  ];

  /// Whether the package publishes to no registry at all. Such packages are
  /// released through git tags only.
  bool get isGitOnly => isEmpty;

  /// A human readable label for messages: `none`, `pub.dev`, `npm` or
  /// `pub.dev+npm`.
  String get label => isEmpty ? 'none' : ordered.map((t) => t.id).join('+');
}

// #############################################################################

/// The registries the package in [directory] publishes to.
///
/// Rules — each manifest decides for its own side, so neither can hide the
/// other:
/// - `pubspec.yaml` present and `publish_to` absent or not `none` → pub.dev
/// - `package.json` present and `private` not truthy → npm
/// - neither → an empty set, i.e. the package releases through git tags only
///
/// A manifest that cannot be read or parsed counts as *not* publishing: a
/// broken manifest must never cause an upload.
///
/// Note that a `publish_to:` naming a custom pub server is treated as pub.dev
/// here, while the version lookup still queries pub.dev itself — the registry
/// url comes from the language catalog, not from the manifest. No repository in
/// the suite uses a custom server; fixing that would mean making the registry
/// url manifest-driven.
Future<Set<PublishTarget>> publishTargetsOf(
  Directory directory, {
  LanguageCatalog? catalog,
}) async {
  final resolved = catalog ?? await LanguageCatalog.load();
  final targets = <PublishTarget>{};

  if (File('${directory.path}/pubspec.yaml').existsSync() &&
      !await _isPrivate(directory, resolved, PublishTarget.pubDev)) {
    targets.add(PublishTarget.pubDev);
  }

  if (File('${directory.path}/package.json').existsSync() &&
      !await _isPrivate(directory, resolved, PublishTarget.npm)) {
    targets.add(PublishTarget.npm);
  }

  return targets;
}

// #############################################################################

/// Whether [directory] is a hybrid whose two manifests carry different
/// versions.
///
/// Returns false for anything that is not a hybrid, and for a hybrid whose
/// versions cannot be parsed — callers use this to *relax* a check (skip pana,
/// reconcile the manifests), so an unreadable manifest must not trigger them.
Future<bool> hybridVersionsDiffer(
  Directory directory, {
  LanguageCatalog? catalog,
}) async {
  final versions = await hybridVersions(directory, catalog: catalog);
  if (versions == null) return false;
  return versions.pubspec != versions.packageJson;
}

/// The two manifest versions of the hybrid in [directory], or null when
/// [directory] is not a hybrid or either version cannot be parsed.
Future<({Version pubspec, Version packageJson})?> hybridVersions(
  Directory directory, {
  LanguageCatalog? catalog,
}) async {
  if (!isHybridProject(directory)) return null;

  final resolved = catalog ?? await LanguageCatalog.load();
  try {
    return (
      pubspec: await PublishTarget.pubDev
          .manifestIn(directory, resolved)
          .readVersion(),
      packageJson: await PublishTarget.npm
          .manifestIn(directory, resolved)
          .readVersion(),
    );
  } catch (_) {
    return null;
  }
}

// .............................................................................
/// Reads the publish marker of one side (`publish_to` / `private`). A manifest
/// that cannot be read or parsed counts as private.
///
/// The catch is deliberately broad: `loadYaml` and `jsonDecode` throw their own
/// exception types, and none of them may turn into an upload.
Future<bool> _isPrivate(
  Directory directory,
  LanguageCatalog catalog,
  PublishTarget target,
) async {
  try {
    return await target.manifestIn(directory, catalog).isPrivate();
  } catch (_) {
    return true;
  }
}
