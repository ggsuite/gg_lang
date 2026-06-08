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
    final url = (_spec.url ?? '').replaceAll('{name}', packageName);
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

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = _resolvePath(body, _spec.latestPath ?? 'latest.version');
    if (raw == null) {
      throw RegistryException(
        'No "${_spec.latestPath}" in response from $url.',
      );
    }
    return Version.parse(raw.toString());
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
  /// Constructor.
  NpmRegistry({
    required LanguageSpec spec,
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _spec = spec,
       _processWrapper = processWrapper;

  final LanguageSpec _spec;
  final GgProcessWrapper _processWrapper;

  @override
  Future<Version?> latestVersion({required String packageName}) async {
    final commandKey = _spec.registry?.command ?? 'registryVersion';
    final command = _spec.command(commandKey).withValues({'name': packageName});

    final executable = command.exec ?? command.tool!;
    final result = await _processWrapper.run(
      executable,
      command.args,
      runInShell: command.runInShell,
    );

    final stdout = (result.stdout as String).trim();
    final stderr = (result.stderr as String);

    if (result.exitCode != 0) {
      if (stderr.contains('404') || stderr.contains('E404')) return null;
      throw RegistryException(
        'Error running "$executable ${command.args.join(' ')}": $stderr',
      );
    }

    if (stdout.isEmpty) return null;
    return Version.parse(stdout);
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
  /// has no registry configured or an unknown kind.
  Registry forProjectType(ProjectType type, {required LanguageSpec spec}) {
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
        return NpmRegistry(spec: spec, processWrapper: _processWrapper);
      default:
        throw RegistryException('Unknown registry kind "${registry.kind}".');
    }
  }
}

// #############################################################################
/// A mocktail mock.
class MockRegistry extends mocktail.Mock implements Registry {}
