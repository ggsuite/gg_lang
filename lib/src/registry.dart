// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:gg_lang/src/language_catalog.dart';
import 'package:gg_lang/src/project_type.dart';
import 'package:gg_process/gg_process.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart' as mocktail;
import 'package:pub_semver/pub_semver.dart';

// #############################################################################

/// Thrown on unexpected registry errors (non-404 HTTP status, npm non-zero
/// exit that is not a "not found").
class RegistryException implements Exception {
  /// Constructor.
  RegistryException(this.message);

  /// A human readable description of what went wrong.
  final String message;

  @override
  String toString() => 'RegistryException: $message';
}

// #############################################################################

/// Looks up the latest version a package has published to its registry.
abstract class Registry {
  /// Constructor.
  const Registry();

  /// Returns the latest published [Version], or null when the package has
  /// never been published (404 / not found).
  Future<Version?> latestVersion({required String packageName});

  /// Returns all published [Version]s including prereleases, or an empty
  /// list when the package has never been published (404 / not found).
  Future<List<Version>> allVersions({required String packageName});
}

// #############################################################################

/// pub.dev implementation (Dart/Flutter) using the HTTP JSON API.
class PubDevRegistry extends Registry {
  /// Constructor.
  PubDevRegistry({required RegistrySpec spec, http.Client? httpClient})
    : _spec = spec,
      _httpClient = httpClient;

  final RegistrySpec _spec;
  final http.Client? _httpClient;

  @override
  Future<Version?> latestVersion({required String packageName}) async {
    final url = _url(packageName);
    final body = await _getBody(url);
    if (body == null) return null;

    final raw = _resolvePath(body, _spec.latestPath ?? 'latest.version');
    if (raw == null) {
      throw RegistryException(
        'No "${_spec.latestPath}" in response from $url.',
      );
    }
    return Version.parse(raw.toString());
  }

  @override
  Future<List<Version>> allVersions({required String packageName}) async {
    final url = _url(packageName);
    final body = await _getBody(url);
    if (body == null) return [];

    final path = _spec.versionsPath ?? 'versions';
    final raw = _resolvePath(body, path);
    if (raw is! List) {
      throw RegistryException('No "$path" list in response from $url.');
    }

    // pub.dev lists versions as objects carrying a `version` field; plain
    // string entries are supported for simpler registries. A malformed entry
    // is surfaced as a RegistryException (like every other registry error),
    // so callers that only catch RegistryException are not crashed by a raw
    // FormatException.
    return raw.map((entry) {
      final value = entry is Map ? entry['version'] : entry;
      try {
        return Version.parse(value.toString());
      } on FormatException catch (e) {
        throw RegistryException('Invalid version "$value" from $url: $e');
      }
    }).toList();
  }

  // ...........................................................................
  String _url(String packageName) =>
      (_spec.url ?? '').replaceAll('{name}', packageName);

  // ...........................................................................
  /// Fetches and decodes the JSON body behind [url]. Returns null on 404.
  Future<Map<String, dynamic>?> _getBody(String url) async {
    final client = _httpClient ?? http.Client();

    late http.Response response;
    try {
      response = await client.get(Uri.parse(url));
    } catch (e) {
      throw RegistryException('Error querying $url: $e');
    } finally {
      if (_httpClient == null) client.close();
    }

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw RegistryException('Error ${response.statusCode} querying $url.');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ...........................................................................
  /// Navigates a dotted [path] (e.g. `latest.version`) into a decoded JSON map.
  static Object? _resolvePath(Map<String, dynamic> root, String path) {
    Object? current = root;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}

// #############################################################################

/// npm implementation (TypeScript) shelling out via the catalog command
/// (`npm view <name> version`).
class NpmRegistry extends Registry {
  /// Constructor. [workingDirectory] should be the package directory: npm
  /// resolves the project-level `.npmrc` from its working directory, so
  /// without it scoped registries (e.g. a private Azure Artifacts feed) are
  /// missed and their packages look unpublished.
  NpmRegistry({
    required LanguageSpec spec,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
    String? workingDirectory,
  }) : _spec = spec,
       _processWrapper = processWrapper,
       _workingDirectory = workingDirectory;

  final LanguageSpec _spec;
  final GgProcessWrapper _processWrapper;
  final String? _workingDirectory;

  @override
  Future<Version?> latestVersion({required String packageName}) async {
    final commandKey = _spec.registry?.command ?? 'registryVersion';
    final stdout = await _runViewCommand(commandKey, packageName);

    if (stdout == null || stdout.isEmpty) return null;
    return Version.parse(stdout);
  }

  @override
  Future<List<Version>> allVersions({required String packageName}) async {
    final commandKey = _spec.registry?.versionsCommand ?? 'registryVersions';
    final stdout = await _runViewCommand(commandKey, packageName);

    if (stdout == null || stdout.isEmpty) return [];

    // `npm view <name> versions --json` prints a JSON list, or a single
    // JSON string when only one version has ever been published. Malformed
    // JSON or an unparseable version is surfaced as a RegistryException so
    // callers that only catch RegistryException are not crashed by a raw
    // FormatException.
    try {
      final decoded = jsonDecode(stdout);
      final list = decoded is List ? decoded : [decoded];
      return list.map((entry) => Version.parse(entry.toString())).toList();
    } on FormatException catch (e) {
      throw RegistryException('Invalid versions output for $packageName: $e');
    }
  }

  // ...........................................................................
  /// Runs the catalog command behind [commandKey] and returns its trimmed
  /// stdout. Returns null when the package is not found (404).
  Future<String?> _runViewCommand(String commandKey, String packageName) async {
    final command = _spec.command(commandKey).withValues({'name': packageName});

    final executable = command.exec ?? command.tool!;
    final result = await _processWrapper.run(
      executable,
      command.args,
      runInShell: command.runInShell,
      workingDirectory: _workingDirectory,
    );

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String);

    if (result.exitCode != 0) {
      if (stderr.contains('404') || stderr.contains('E404')) return null;
      throw RegistryException(
        'Error running "$executable ${command.args.join(' ')}": $stderr',
      );
    }

    return stdout;
  }
}

// #############################################################################

/// Builds the right [Registry] for a [ProjectType] / [LanguageSpec], based on
/// the language's [RegistrySpec.kind].
class RegistryFactory {
  /// Constructor.
  const RegistryFactory({
    http.Client? httpClient,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _httpClient = httpClient,
       _processWrapper = processWrapper;

  final http.Client? _httpClient;
  final GgProcessWrapper _processWrapper;

  /// Returns a [Registry] for [type] using [spec]. Throws when the language
  /// has no registry configured or an unknown kind. [workingDirectory] is the
  /// package directory; CLI registries run their lookups there so npm picks
  /// up the project-level `.npmrc` (scoped/private registries).
  Registry forProjectType(
    ProjectType type, {
    required LanguageSpec spec,
    String? workingDirectory,
  }) {
    final registry = spec.registry;
    if (registry == null) {
      throw RegistryException(
        'No registry configured for ${spec.displayName}.',
      );
    }

    switch (registry.kind) {
      case 'http':
        return PubDevRegistry(spec: registry, httpClient: _httpClient);
      case 'cli':
        return NpmRegistry(
          spec: spec,
          processWrapper: _processWrapper,
          workingDirectory: workingDirectory,
        );
      default:
        throw RegistryException('Unknown registry kind "${registry.kind}".');
    }
  }
}

// #############################################################################
/// A mocktail mock.
class MockRegistry extends mocktail.Mock implements Registry {}
