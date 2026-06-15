// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gg_npm_scripts_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('readNpmScripts', () {
    test('returns the scripts map declared in package.json', () {
      File('${tmp.path}/package.json').writeAsStringSync(
        '{"name":"foo","scripts":{"test":"vitest run","lint":"eslint"}}',
      );
      final scripts = readNpmScripts(tmp);
      expect(scripts, {'test': 'vitest run', 'lint': 'eslint'});
    });

    test('returns an empty map when package.json is missing', () {
      expect(readNpmScripts(tmp), isEmpty);
    });

    test('returns an empty map when package.json has no scripts', () {
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      expect(readNpmScripts(tmp), isEmpty);
    });

    test('returns an empty map when scripts is not an object', () {
      File('${tmp.path}/package.json').writeAsStringSync('{"scripts":"oops"}');
      expect(readNpmScripts(tmp), isEmpty);
    });

    test('returns an empty map when package.json is not a JSON object', () {
      File('${tmp.path}/package.json').writeAsStringSync('[1,2,3]');
      expect(readNpmScripts(tmp), isEmpty);
    });

    test('returns an empty map when package.json is malformed', () {
      File('${tmp.path}/package.json').writeAsStringSync('{ not json');
      expect(readNpmScripts(tmp), isEmpty);
    });
  });

  group('hasNpmScript', () {
    test('is true when the script exists', () {
      File(
        '${tmp.path}/package.json',
      ).writeAsStringSync('{"scripts":{"test":"vitest run"}}');
      expect(hasNpmScript(tmp, 'test'), isTrue);
    });

    test('is false when the script is absent', () {
      File(
        '${tmp.path}/package.json',
      ).writeAsStringSync('{"scripts":{"lint":"eslint"}}');
      expect(hasNpmScript(tmp, 'test'), isFalse);
    });
  });
}
