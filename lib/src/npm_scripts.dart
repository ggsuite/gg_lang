// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

// #############################################################################

/// Reads the `scripts` section of the `package.json` in [directory].
///
/// Returns a map of script name to command line. Returns an empty map when
/// there is no `package.json`, it cannot be parsed, it is not a JSON object,
/// or it declares no `scripts`.
Map<String, String> readNpmScripts(Directory directory) {
  final file = File('${directory.path}/package.json');
  if (!file.existsSync()) {
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return const {};
    }
    final scripts = decoded['scripts'];
    if (scripts is! Map) {
      return const {};
    }
    final result = <String, String>{};
    scripts.forEach((key, value) {
      result[key.toString()] = value.toString();
    });
    return result;
  } catch (_) {
    return const {};
  }
}

// .............................................................................
/// Whether the `package.json` in [directory] declares an npm script named
/// [name].
bool hasNpmScript(Directory directory, String name) =>
    readNpmScripts(directory).containsKey(name);

// .............................................................................
/// The names of every dependency the `package.json` in [directory] declares —
/// `dependencies`, `devDependencies`, `peerDependencies` and
/// `optionalDependencies`.
///
/// Returns an empty set when there is no `package.json`, it cannot be parsed,
/// or it is not a JSON object. Callers use this to act only on packages a
/// repository really has: installing one it never declared would add it.
Set<String> readNpmDependencyNames(Directory directory) {
  final file = File('${directory.path}/package.json');
  if (!file.existsSync()) {
    return const {};
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return const {};
    }
    final result = <String>{};
    for (final section in const <String>[
      'dependencies',
      'devDependencies',
      'peerDependencies',
      'optionalDependencies',
    ]) {
      final entries = decoded[section];
      if (entries is Map) {
        result.addAll(entries.keys.map((key) => key.toString()));
      }
    }
    return result;
  } catch (_) {
    return const {};
  }
}

// .............................................................................
/// Whether the `package.json` in [directory] sets `"private": true`.
///
/// npm and pnpm refuse to publish a package marked private, so gg's
/// publish-related checks treat such a package as exempt from the
/// `prepublishOnly` requirement.
///
/// Returns `false` when there is no `package.json`, it cannot be parsed, it is
/// not a JSON object, or `private` is absent or anything other than the JSON
/// boolean `true`.
bool isPrivateNpmPackage(Directory directory) {
  final file = File('${directory.path}/package.json');
  if (!file.existsSync()) {
    return false;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      return false;
    }
    return decoded['private'] == true;
  } catch (_) {
    return false;
  }
}
