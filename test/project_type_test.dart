// @license
// Copyright (c) ggsuite
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
      File('${tmp.path}/pubspec.yaml')
          .writeAsStringSync('name: foo\nversion: 0.0.1\n');
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
      'returns none when package.json is present but tsconfig.json is missing',
      () {
        File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
        expect(detectProjectType(tmp), ProjectType.none);
      },
    );

    test('returns none when directory is empty', () {
      expect(detectProjectType(tmp), ProjectType.none);
    });

    test('returns none when only tsconfig.json is present', () {
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(detectProjectType(tmp), ProjectType.none);
    });

    test('pubspec.yaml takes precedence over package.json', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(detectProjectType(tmp), ProjectType.dart);
    });
  });

  group('isHybridProject', () {
    test('is true when pubspec.yaml and package.json coexist', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      expect(isHybridProject(tmp), isTrue);
      // detectProjectType still reports dart (pubspec precedence).
      expect(detectProjectType(tmp), ProjectType.dart);
    });

    test('a tsconfig.json is not required', () {
      // A Dart package that additionally publishes its payload as an npm
      // tarball carries no TypeScript sources — but it still has two
      // manifests, two registries and two versions to keep in lock-step.
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      expect(File('${tmp.path}/tsconfig.json').existsSync(), isFalse);
      expect(isHybridProject(tmp), isTrue);
    });

    test('a tsconfig.json does not hurt either', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(isHybridProject(tmp), isTrue);
    });

    test('is false for a pure Dart package', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      expect(isHybridProject(tmp), isFalse);
    });

    test('is false for a pure TypeScript project', () {
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(isHybridProject(tmp), isFalse);
    });

    test('is false for an empty directory', () {
      expect(isHybridProject(tmp), isFalse);
    });
  });

  group('isBridgeProject', () {
    test('is the former name of isHybridProject, with the widened rule', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      // No tsconfig.json — which the old rule required.
      expect(isBridgeProject(tmp), isHybridProject(tmp));
      expect(isBridgeProject(tmp), isTrue);
    });
  });

  group('checkProjectType', () {
    test('resolves a hybrid repo to typescript (not dart)', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      // detectProjectType would say dart (pubspec precedence); the check
      // pipeline treats hybrids as typescript.
      expect(detectProjectType(tmp), ProjectType.dart);
      expect(checkProjectType(tmp), ProjectType.typescript);
    });

    test('resolves a hybrid without tsconfig.json to typescript too', () {
      // This is the case that used to fall through to dart, so the npm side
      // of such a repo was never checked, versioned or published by gg.
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      expect(detectProjectType(tmp), ProjectType.dart);
      expect(checkProjectType(tmp), ProjectType.typescript);
    });

    test('a Flutter hybrid is checked as typescript as well', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync(
        'name: foo\nflutter:\n  uses-material-design: true\n',
      );
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      expect(detectProjectType(tmp), ProjectType.flutter);
      expect(checkProjectType(tmp), ProjectType.typescript);
    });

    test('delegates to detectProjectType for a pure Dart package', () {
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: foo\n');
      expect(checkProjectType(tmp), ProjectType.dart);
    });

    test('delegates to detectProjectType for a pure TypeScript project', () {
      File('${tmp.path}/package.json').writeAsStringSync('{"name":"foo"}');
      File('${tmp.path}/tsconfig.json').writeAsStringSync('{}');
      expect(checkProjectType(tmp), ProjectType.typescript);
    });

    test('returns none when no project type can be detected', () {
      expect(checkProjectType(tmp), ProjectType.none);
    });
  });

  group('ProjectType.isDartFamily', () {
    test('is true for Dart and Flutter, false for TypeScript and none', () {
      expect(ProjectType.dart.isDartFamily, isTrue);
      expect(ProjectType.flutter.isDartFamily, isTrue);
      expect(ProjectType.typescript.isDartFamily, isFalse);
      expect(ProjectType.none.isDartFamily, isFalse);
    });
  });

  group('ProjectType.hasManifest', () {
    test('is true for all types except none', () {
      expect(ProjectType.dart.hasManifest, isTrue);
      expect(ProjectType.flutter.hasManifest, isTrue);
      expect(ProjectType.typescript.hasManifest, isTrue);
      expect(ProjectType.none.hasManifest, isFalse);
    });
  });
}
