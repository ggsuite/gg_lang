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
