// @license
// Copyright (c) 2019 - 2024 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gg_project_type_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  group('detectProjectType', () {
    test('returns dart for a pubspec.yaml without flutter key', () {
      File(
        '${tmp.path}/pubspec.yaml',
      ).writeAsStringSync('name: foo\nversion: 0.0.1\n');
      expect(detectProjectType(tmp), ProjectType.dart);
    });

    test('returns flutter for pubspec.yaml with top-level flutter key', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync(
        'name: foo\n'
        'version: 0.0.1\n'
        'flutter:\n'
        '  uses-material-design: true\n',
      );
      expect(detectProjectType(tmp), ProjectType.flutter);
    });

    test('ignores indented "flutter:" keys (not top-level)', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync(
        'name: foo\n'
        'dependencies:\n'
        '  flutter:\n'
        '    sdk: flutter\n',
      );
      // Indented `flutter:` under `dependencies:` is common in plain Dart
      // packages that talk to Flutter types but are not Flutter apps.
      expect(detectProjectType(tmp), ProjectType.dart);
    });

    test('ignores commented-out flutter keys', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync(
        'name: foo\n'
        '# flutter:\n'
        'version: 0.0.1\n',
      );
      expect(detectProjectType(tmp), ProjectType.dart);
    });

    test('tolerates blank and CRLF lines', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync(
        'name: foo\r\n\r\nflutter:\r\n  uses-material-design: true\r\n',
      );
      expect(detectProjectType(tmp), ProjectType.flutter);
    });

    test('returns typescript for package.json + tsconfig.json', () {
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(detectProjectType(tmp), ProjectType.typescript);
    });

    test(
      'throws when package.json is present but tsconfig.json is missing',
      () {
        File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
        expect(() => detectProjectType(tmp), throwsException);
      },
    );

    test('throws when directory is empty', () {
      expect(() => detectProjectType(tmp), throwsException);
    });

    test('pubspec.yaml takes precedence over package.json', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(detectProjectType(tmp), ProjectType.dart);
    });
  });
}
