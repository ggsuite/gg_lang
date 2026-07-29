// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

const _dartSpec = ManifestSpec(
  file: 'pubspec.yaml',
  format: 'yaml',
  versionPath: 'version',
  namePath: 'name',
  publishTargetMarker: 'publish_to',
  lockFile: 'pubspec.lock',
);

const _tsSpec = ManifestSpec(
  file: 'package.json',
  format: 'json',
  versionPath: 'version',
  namePath: 'name',
  publishTargetMarker: 'private',
  lockFile: 'package-lock.json',
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('gg_lang_manifest_test');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void writePubspec(String content) {
    File('${dir.path}/pubspec.yaml').writeAsStringSync(content);
  }

  void writePackageJson(String content) {
    File('${dir.path}/package.json').writeAsStringSync(content);
  }

  group('Manifest (yaml / pubspec.yaml)', () {
    test('reads version, name and marker', () async {
      writePubspec('''
name: my_pkg
version: 1.2.3
publish_to: none
''');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect((await manifest.readVersion()).toString(), '1.2.3');
      expect(await manifest.readVersionString(), '1.2.3');
      expect(await manifest.readName(), 'my_pkg');
      expect(await manifest.readPublishTargetMarker(), 'none');
      expect(await manifest.isPrivate(), isTrue);
    });

    test('isPrivate is false when publish_to is absent', () async {
      writePubspec('name: my_pkg\nversion: 1.0.0\n');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(await manifest.isPrivate(), isFalse);
    });

    test(
      'writeVersion replaces only the version line, keeping comments',
      () async {
        writePubspec('''
name: my_pkg # the package
version: 1.2.3
# a trailing comment
environment:
  sdk: ">=3.8.0 <4.0.0"
''');
        final manifest = Manifest(directory: dir, spec: _dartSpec);
        await manifest.writeVersion(Version.parse('2.0.0'));

        final result = File('${dir.path}/pubspec.yaml').readAsStringSync();
        expect(result, contains('version: 2.0.0'));
        expect(result, contains('name: my_pkg # the package'));
        expect(result, contains('# a trailing comment'));
        expect(result, contains('sdk: ">=3.8.0 <4.0.0"'));
      },
    );

    test('readVersion throws when version is missing', () async {
      writePubspec('name: my_pkg\n');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(manifest.readVersion(), throwsA(isA<ManifestException>()));
    });

    test('readVersion throws on an invalid version', () async {
      writePubspec('name: my_pkg\nversion: not-a-version\n');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(manifest.readVersion(), throwsA(isA<ManifestException>()));
    });

    test('readName throws when name is missing', () async {
      writePubspec('version: 1.0.0\n');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(manifest.readName(), throwsA(isA<ManifestException>()));
    });

    test('throws when the manifest does not exist', () async {
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(manifest.readVersion(), throwsA(isA<ManifestException>()));
      expect(
        manifest.writeVersion(Version.parse('1.0.0')),
        throwsA(isA<ManifestException>()),
      );
    });

    test('throws when the manifest is not a yaml map', () async {
      writePubspec('- just\n- a\n- list\n');
      final manifest = Manifest(directory: dir, spec: _dartSpec);
      expect(manifest.readVersion(), throwsA(isA<ManifestException>()));
    });
  });

  group('Manifest (json / package.json)', () {
    test('reads version, name and private marker', () async {
      writePackageJson(
        '{\n  "name": "ts_pkg",\n  "version": "0.4.0",'
        '\n  "private": true\n}\n',
      );
      final manifest = Manifest(directory: dir, spec: _tsSpec);
      expect((await manifest.readVersion()).toString(), '0.4.0');
      expect(await manifest.readName(), 'ts_pkg');
      expect(await manifest.isPrivate(), isTrue);
    });

    test('isPrivate is false for a public package', () async {
      writePackageJson('{"name":"ts_pkg","version":"0.4.0","private":false}');
      final manifest = Manifest(directory: dir, spec: _tsSpec);
      expect(await manifest.isPrivate(), isFalse);
    });

    test('writeVersion rewrites package.json with 2-space indent', () async {
      writePackageJson('{"name":"ts_pkg","version":"0.4.0"}');
      final manifest = Manifest(directory: dir, spec: _tsSpec);
      await manifest.writeVersion(Version.parse('0.5.0'));

      final result = File('${dir.path}/package.json').readAsStringSync();
      expect(result, contains('"version": "0.5.0"'));
      expect(result, endsWith('\n'));
    });

    test('throws when package.json is not an object', () async {
      writePackageJson('[1, 2, 3]');
      final manifest = Manifest(directory: dir, spec: _tsSpec);
      expect(manifest.readName(), throwsA(isA<ManifestException>()));
    });
  });

  group('Manifest.detect', () {
    test('builds a manifest from the detected project type', () async {
      writePubspec('name: my_pkg\nversion: 3.1.4\n');
      final catalog = LanguageCatalog.fromString(_catalogJson);
      final manifest = Manifest.detect(dir, catalog);
      expect(manifest.spec.file, 'pubspec.yaml');
      expect((await manifest.readVersion()).toString(), '3.1.4');
    });

    group('for a bridge (pubspec.yaml + package.json + tsconfig.json)', () {
      setUp(() {
        writePubspec('name: bridge\nversion: 3.1.4\n');
        writePackageJson('{"name":"@org/bridge","version":"0.4.0"}');
        File('${dir.path}/tsconfig.json').writeAsStringSync('{}');
      });

      test('resolves to pubspec.yaml by default', () async {
        final catalog = LanguageCatalog.fromString(_catalogJson);
        final manifest = Manifest.detect(dir, catalog);
        expect(manifest.spec.file, 'pubspec.yaml');
        expect((await manifest.readVersion()).toString(), '3.1.4');
      });

      test('resolves to package.json when treatBridgeAsTypeScript', () async {
        final catalog = LanguageCatalog.fromString(_catalogJson);
        final manifest = Manifest.detect(
          dir,
          catalog,
          treatBridgeAsTypeScript: true,
        );
        expect(manifest.spec.file, 'package.json');
        expect((await manifest.readVersion()).toString(), '0.4.0');
      });
    });

    test('throws a ManifestException when the directory has no manifest', () {
      final catalog = LanguageCatalog.fromString(_catalogJson);
      expect(
        () => Manifest.detect(dir, catalog),
        throwsA(
          isA<ManifestException>().having(
            (e) => e.message,
            'message',
            contains('No manifest'),
          ),
        ),
      );
    });
  });

  group('Manifest (unknown format)', () {
    const weirdSpec = ManifestSpec(
      file: 'pubspec.yaml',
      format: 'toml',
      versionPath: 'version',
      namePath: 'name',
      publishTargetMarker: 'publish_to',
      lockFile: 'pubspec.lock',
    );

    test('throws on read', () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('version = "1.0.0"');
      final manifest = Manifest(directory: dir, spec: weirdSpec);
      expect(manifest.readVersion(), throwsA(isA<ManifestException>()));
    });

    test('throws on write', () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('version = "1.0.0"');
      final manifest = Manifest(directory: dir, spec: weirdSpec);
      expect(
        manifest.writeVersion(Version.parse('2.0.0')),
        throwsA(isA<ManifestException>()),
      );
    });
  });

  group('against the bundled sample_project_ts fixture', () {
    final fixture = Directory('test/sample_project_ts');

    test('is detected as a TypeScript project', () {
      expect(detectProjectType(fixture), ProjectType.typescript);
    });

    test('reads name, version and privacy from package.json', () async {
      final manifest = Manifest(directory: fixture, spec: _tsSpec);
      expect(await manifest.readName(), 'ts_fixture');
      expect((await manifest.readVersion()).toString(), '1.0.0');
      expect(await manifest.isPrivate(), isFalse);
    });
  });

  group('ManifestException', () {
    test('has a readable toString', () {
      expect(ManifestException('boom').toString(), contains('boom'));
    });
  });
}

const _catalogJson = '''
{
  "schemaVersion": 1,
  "languages": {
    "dart": {
      "displayName": "Dart",
      "manifest": {
        "file": "pubspec.yaml",
        "format": "yaml",
        "versionPath": "version",
        "namePath": "name",
        "publishTargetMarker": "publish_to",
        "lockFile": "pubspec.lock"
      },
      "commands": {}
    },
    "typescript": {
      "displayName": "TypeScript",
      "manifest": {
        "file": "package.json",
        "format": "json",
        "versionPath": "version",
        "namePath": "name",
        "publishTargetMarker": "private",
        "lockFile": "package-lock.json"
      },
      "commands": {}
    }
  }
}
''';
