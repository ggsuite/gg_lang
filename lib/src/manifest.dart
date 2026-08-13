// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_lang/src/language_catalog.dart';
import 'package:gg_lang/src/project_type.dart';
import 'package:mocktail/mocktail.dart' as mocktail;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

// #############################################################################

/// Thrown when a manifest field is missing or the manifest cannot be parsed.
class ManifestException implements Exception {
  /// Constructor.
  ManifestException(this.message);

  /// A human readable description of what went wrong.
  final String message;

  @override
  String toString() => 'ManifestException: $message';
}

// #############################################################################

/// Reads and writes package metadata (name, version, publish marker) from a
/// language manifest (`pubspec.yaml` / `package.json`), driven by a
/// [ManifestSpec] so the field names and format never need to be hardcoded.
class Manifest {
  /// Creates a manifest accessor for [directory] using [spec].
  Manifest({required this.directory, required this.spec});

  /// Builds a [Manifest] by auto-detecting the project type in [directory].
  ///
  /// When [treatBridgeAsTypeScript] is `true`, a cross-language bridge repo
  /// (pubspec.yaml + package.json + tsconfig.json) resolves to its
  /// `package.json` manifest via [checkProjectType]. This is what the publish
  /// and versioning flow wants, where a bridge is published as a TypeScript
  /// package. The default ([detectProjectType]) keeps the raw precedence where
  /// a bridge resolves to its `pubspec.yaml`.
  ///
  /// Throws a [ManifestException] when [directory] contains no manifest at
  /// all ([ProjectType.none]).
  factory Manifest.detect(
    Directory directory,
    LanguageCatalog catalog, {
    bool treatBridgeAsTypeScript = false,
  }) {
    final type = treatBridgeAsTypeScript
        ? checkProjectType(directory)
        : detectProjectType(directory);
    if (type == ProjectType.none) {
      throw ManifestException(
        'No manifest (pubspec.yaml / package.json) found in '
        '"${directory.path}".',
      );
    }
    return Manifest(directory: directory, spec: catalog.spec(type).manifest);
  }

  /// The directory containing the manifest file.
  final Directory directory;

  /// The manifest description from the language catalog.
  final ManifestSpec spec;

  /// The manifest [File] (`<directory>/<spec.file>`).
  File get file => File('${directory.path}/${spec.file}');

  // ...........................................................................
  /// Reads the package version. Throws [ManifestException] when it is absent
  /// or cannot be parsed as a semantic version.
  Future<Version> readVersion() async {
    final raw = await readVersionString();
    if (raw == null) {
      throw ManifestException('No "${spec.versionPath}" in ${spec.file}.');
    }
    try {
      return Version.parse(raw);
    } on FormatException catch (e) {
      throw ManifestException('Invalid version "$raw" in ${spec.file}: $e');
    }
  }

  // ...........................................................................
  /// Reads the raw version string (no semver parsing). Null when absent.
  Future<String?> readVersionString() async {
    final value = (await _read())[spec.versionPath];
    return value?.toString();
  }

  // ...........................................................................
  /// Reads the package name. Throws [ManifestException] when it is absent.
  Future<String> readName() async {
    final value = (await _read())[spec.namePath];
    if (value == null) {
      throw ManifestException('No "${spec.namePath}" in ${spec.file}.');
    }
    return value.toString();
  }

  // ...........................................................................
  /// Reads the publish-target marker (Dart: `publish_to`, npm: `private`) as a
  /// raw string. Returns null when the marker is not present.
  Future<String?> readPublishTargetMarker() async {
    final value = (await _read())[spec.publishTargetMarker];
    return value?.toString();
  }

  // ...........................................................................
  /// Whether the package is excluded from the public registry
  /// (Dart `publish_to: none`, npm `private: true`).
  Future<bool> isPrivate() async {
    final value = (await _read())[spec.publishTargetMarker];
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString() == 'none' || value.toString() == 'true';
  }

  // ...........................................................................
  /// Writes [version] back to the manifest, preserving the surrounding
  /// formatting and comments.
  Future<void> writeVersion(Version version) async {
    final f = file;
    if (!f.existsSync()) {
      throw ManifestException('${spec.file} not found in ${directory.path}.');
    }
    final content = await f.readAsString();

    switch (spec.format) {
      case 'yaml':
        final editor = YamlEditor(content);
        editor.update([spec.versionPath], version.toString());
        await f.writeAsString(editor.toString());
      case 'json':
        final map = jsonDecode(content) as Map<String, dynamic>;
        map[spec.versionPath] = version.toString();
        const encoder = JsonEncoder.withIndent('  ');
        await f.writeAsString('${encoder.convert(map)}\n');
      default:
        throw ManifestException('Unknown manifest format "${spec.format}".');
    }
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  /// Reads and decodes the manifest into a map keyed by top-level field.
  Future<Map<String, dynamic>> _read() async {
    final f = file;
    if (!f.existsSync()) {
      throw ManifestException('${spec.file} not found in ${directory.path}.');
    }
    final content = await f.readAsString();

    switch (spec.format) {
      case 'yaml':
        final decoded = loadYaml(content);
        if (decoded is! Map) {
          throw ManifestException('${spec.file} is not a YAML map.');
        }
        return Map<String, dynamic>.from(decoded);
      case 'json':
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) {
          throw ManifestException('${spec.file} is not a JSON object.');
        }
        return decoded;
      default:
        throw ManifestException('Unknown manifest format "${spec.format}".');
    }
  }
}

// #############################################################################
/// A mocktail mock.
class MockManifest extends mocktail.Mock implements Manifest {}
