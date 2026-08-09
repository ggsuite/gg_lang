// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_lang/src/type_script_package_manager.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart' as mocktail;
import 'package:path/path.dart' as p;

// #############################################################################

/// The hosts serving the public npm registry.
const Set<String> _npmjsHosts = <String>{
  'registry.npmjs.org',
  'registry.npmjs.com',
  'registry.yarnpkg.com',
};

/// The status page of the public npm registry, with a `{name}` placeholder.
const String npmjsStatusUrl =
    'https://www.npmjs.com/package/{name}?activeTab=versions';

// #############################################################################

/// Returns the human-facing page where the published versions of a package on
/// [registryUrl] can be checked, as a template with a `{name}` placeholder.
///
/// Recognized registries:
/// - the public npm registry → the npmjs.com versions tab
/// - Azure Artifacts → the feed page (`…/_artifacts/feed/<feed>`), covering the
///   project-scoped, organization-scoped, legacy `*.pkgs.visualstudio.com` and
///   self-hosted Azure DevOps Server shapes
/// - anything else → the packument url `<registry>/<name>`, which is not a web
///   page but is always correct
///
/// The Azure result carries **no** `{name}` placeholder: Microsoft documents
/// the feed page but publishes no url contract for the per-package route, and a
/// link that 404s is worse than one extra click.
///
/// Never throws. A status url exists to help a human; it must not be able to
/// abort a publish.
String npmStatusUrlTemplate(String registryUrl) {
  final Uri uri;
  try {
    uri = Uri.parse(registryUrl.trim());
  } on FormatException {
    return _packumentTemplate(registryUrl);
  }

  if (!uri.hasAuthority || uri.host.isEmpty) {
    return _packumentTemplate(registryUrl);
  }

  if (_npmjsHosts.contains(uri.host.toLowerCase())) {
    return npmjsStatusUrl;
  }

  return _azureFeedUrl(uri) ?? _packumentTemplate(registryUrl);
}

// .............................................................................
/// The packument url — `<registry>/<name>` with exactly one separating slash.
String _packumentTemplate(String registryUrl) {
  final trimmed = registryUrl.trim();
  final withoutTrailingSlashes = trimmed.replaceAll(RegExp(r'/+$'), '');
  return '$withoutTrailingSlashes/{name}';
}

// .............................................................................
/// Maps an Azure Artifacts npm registry url to its feed page, or null when
/// [uri] is not an Azure Artifacts registry.
///
/// One rule covers every shape: everything before the `_packaging` segment is
/// the organization/project prefix, and the segment after it names the feed.
///
/// | registry | feed page |
/// |---|---|
/// | `pkgs.dev.azure.com/{org}/{project}/_packaging/{feed}/npm/registry/` | `dev.azure.com/{org}/{project}/_artifacts/feed/{feed}` |
/// | `pkgs.dev.azure.com/{org}/_packaging/{feed}/npm/registry/` | `dev.azure.com/{org}/_artifacts/feed/{feed}` |
/// | `{org}.pkgs.visualstudio.com/{project}/_packaging/{feed}/npm/registry/` | `dev.azure.com/{org}/{project}/_artifacts/feed/{feed}` |
/// | a self-hosted `{host}/{collection}/{project}/_packaging/…` | `{host}/{collection}/{project}/_artifacts/feed/{feed}` |
String? _azureFeedUrl(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final index = segments.indexOf('_packaging');
  if (index == -1 || index + 1 >= segments.length) {
    return null;
  }

  // A feed may be addressed through one of its views (»ds-cdm@local«,
  // »@release«). The view is not part of the feed page url.
  final feed = segments[index + 1].split('@').first;
  if (feed.isEmpty) {
    return null;
  }

  final prefix = segments.sublist(0, index);
  final host = uri.host.toLowerCase();

  if (host == 'pkgs.dev.azure.com') {
    return _joinUrl('https://dev.azure.com', prefix, feed);
  }

  // Legacy »{org}.pkgs.visualstudio.com«: the organization lives in the host
  // and has to move into the path.
  if (host.endsWith('.pkgs.visualstudio.com')) {
    final org = host.substring(
      0,
      host.length - '.pkgs.visualstudio.com'.length,
    );
    if (org.isEmpty) return null;
    return _joinUrl('https://dev.azure.com', <String>[org, ...prefix], feed);
  }

  // Azure DevOps Server (self-hosted): the web ui lives on the same host.
  final authority = uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
  return _joinUrl(authority, prefix, feed);
}

// .............................................................................
String _joinUrl(String origin, List<String> prefix, String feed) {
  final path = <String>[...prefix, '_artifacts', 'feed', feed].join('/');
  return '$origin/$path';
}

// #############################################################################

/// Resolves the npm registry a package actually publishes to, by asking the
/// package manager for its merged `.npmrc` configuration.
///
/// Resolution order, mirroring how npm and pnpm pick the registry:
/// 1. `publishConfig.registry` in `package.json`
/// 2. the package scope's `@<scope>:registry`
/// 3. the default `registry`
///
/// The lookup runs `<pm> config get <key>` **in the package directory**, so the
/// project-level `.npmrc` is merged with the user and global ones exactly as a
/// real publish would see it.
///
/// Only the keys `registry` and `@<scope>:registry` are ever read. Credentials
/// live under separate `//<host>/:_authToken` and `_auth` keys and this class
/// must never touch them.
class NpmRegistryResolver {
  /// Constructor.
  NpmRegistryResolver({
    GgProcessWrapper processWrapper = const GgProcessWrapper(),
  }) : _processWrapper = processWrapper;

  /// Example instance for tests.
  factory NpmRegistryResolver.example() => NpmRegistryResolver();

  final GgProcessWrapper _processWrapper;

  /// The resolved registry per absolute directory path.
  ///
  /// Caching the [Future] rather than the value also collapses concurrent
  /// lookups of the same directory into one subprocess. Instance level, not
  /// static: a global cache would have to be reset in every test's `setUp`.
  final Map<String, Future<String?>> _cache = <String, Future<String?>>{};

  /// Forgets all cached lookups.
  void clearCache() => _cache.clear();

  // ...........................................................................
  /// The registry the package in [directory] publishes to, or null when none
  /// is configured — the package manager then uses its own default.
  Future<String?> registryOf({
    required Directory directory,
    TypeScriptPackageManager? packageManager,
  }) {
    final key = directory.absolute.path;
    return _cache[key] ??= _resolve(
      directory: directory,
      packageManager:
          packageManager ?? detectTypeScriptPackageManager(directory),
    );
  }

  // ...........................................................................
  /// The status page template (with a `{name}` placeholder) for the package in
  /// [directory].
  ///
  /// Falls back to [fallback] when no registry is configured — npm's own
  /// default *is* the public registry, so the caller's catalog template is the
  /// right guess there.
  Future<String?> statusUrlTemplateOf({
    required Directory directory,
    String? fallback,
    TypeScriptPackageManager? packageManager,
  }) async {
    final registry = await registryOf(
      directory: directory,
      packageManager: packageManager,
    );
    if (registry == null) return fallback;
    return npmStatusUrlTemplate(registry);
  }

  // ######################
  // Private
  // ######################

  // ...........................................................................
  Future<String?> _resolve({
    required Directory directory,
    required TypeScriptPackageManager packageManager,
  }) async {
    final pkg = _readPackageJson(directory);

    final publishConfig = pkg?['publishConfig'];
    if (publishConfig is Map) {
      final registry = publishConfig['registry'];
      if (registry is String && registry.isNotEmpty) {
        return registry;
      }
    }

    final name = pkg?['name'];
    if (name is String && name.startsWith('@') && name.contains('/')) {
      final scope = name.substring(0, name.indexOf('/'));
      final scoped = await _config(
        directory: directory,
        packageManager: packageManager,
        key: '$scope:registry',
      );
      if (scoped != null) {
        return scoped;
      }
    }

    return _config(
      directory: directory,
      packageManager: packageManager,
      key: 'registry',
    );
  }

  // ...........................................................................
  /// Reads and parses `package.json`, or null when absent/unparseable.
  Map<String, dynamic>? _readPackageJson(Directory directory) {
    final file = File(p.join(directory.path, 'package.json'));
    if (!file.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ...........................................................................
  /// Reads a config value from the merged `.npmrc` via `<pm> config get <key>`.
  /// Returns null when unset.
  Future<String?> _config({
    required Directory directory,
    required TypeScriptPackageManager packageManager,
    required String key,
  }) async {
    // npm/pnpm/yarn are shell shims (pnpm.cmd on Windows, a PATH script
    // elsewhere), so run through a shell — otherwise Windows cannot find the
    // executable and Process.run throws »cannot find the file«.
    final result = await _processWrapper.run(
      packageManager.executable,
      <String>['config', 'get', key],
      workingDirectory: directory.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      return null;
    }
    return _cleanConfigValue(result.stdout.toString());
  }

  // ...........................................................................
  /// Extracts the value from a `config get` output.
  ///
  /// pnpm 11 prints raw strings for string values but JSON for everything else,
  /// and yarn classic wraps the value in a banner plus a »Done in …« footer. So
  /// prefer the first url-shaped line and strip surrounding quotes rather than
  /// trusting the whole output; fall back to the first meaningful line, which
  /// is what a single-line `npm config get` produces. Yarn's scoped lookups
  /// stay unreliable — gg's TypeScript repositories use pnpm in practice.
  static String? _cleanConfigValue(String stdout) {
    final candidates = <String>[];
    for (final rawLine in stdout.split('\n')) {
      final line = _unquote(rawLine.trim());
      if (line.isEmpty || line == 'undefined' || line == 'null') {
        continue;
      }
      if (line.contains('://')) {
        return line;
      }
      candidates.add(line);
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  // ...........................................................................
  static String _unquote(String value) {
    if (value.length < 2) return value;
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}

// #############################################################################
/// A mocktail mock.
class MockNpmRegistryResolver extends mocktail.Mock
    implements NpmRegistryResolver {}
