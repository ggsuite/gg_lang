// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late LanguageCatalog catalog;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('gg_publish_targets_test_');
    catalog = await LanguageCatalog.load();
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  // ...........................................................................
  void writePubspec({String? publishTo, String version = '1.0.0'}) {
    File('${tmp.path}/pubspec.yaml').writeAsStringSync(
      'name: foo\n'
      'version: $version\n'
      '${publishTo == null ? '' : 'publish_to: $publishTo\n'}',
    );
  }

  void writePackageJson({bool? private, String version = '1.0.0'}) {
    File('${tmp.path}/package.json').writeAsStringSync(
      '{\n'
      '  "name": "@org/foo",\n'
      '  "version": "$version"'
      '${private == null ? '' : ',\n  "private": $private'}\n'
      '}\n',
    );
  }

  void writeTsConfig() {
    File('${tmp.path}/tsconfig.json').writeAsStringSync('{}\n');
  }

  Future<Set<PublishTarget>> targets() =>
      publishTargetsOf(tmp, catalog: catalog);

  // ###########################################################################
  group('PublishTarget', () {
    group('id', () {
      test('names the registry', () {
        expect(PublishTarget.pubDev.id, 'pub.dev');
        expect(PublishTarget.npm.id, 'npm');
      });
    });

    // .........................................................................
    group('projectTypeIn(directory)', () {
      test('resolves pubDev to dart for a plain pubspec', () {
        writePubspec();
        expect(PublishTarget.pubDev.projectTypeIn(tmp), ProjectType.dart);
      });

      test('resolves pubDev to flutter for a flutter pubspec', () {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync(
          'name: foo\n'
          'version: 1.0.0\n'
          'flutter:\n'
          '  uses-material-design: true\n',
        );
        expect(PublishTarget.pubDev.projectTypeIn(tmp), ProjectType.flutter);
      });

      test('resolves pubDev to dart for a hybrid', () {
        // checkProjectType would answer typescript here - the whole point of
        // PublishTarget is that the Dart side keeps its own type.
        writePubspec();
        writePackageJson();
        expect(PublishTarget.pubDev.projectTypeIn(tmp), ProjectType.dart);
      });

      test('resolves npm to typescript, also without a tsconfig', () {
        writePubspec();
        writePackageJson();
        expect(PublishTarget.npm.projectTypeIn(tmp), ProjectType.typescript);
      });
    });

    // .........................................................................
    group('manifestIn(directory, catalog)', () {
      test('reads each side from its own manifest', () async {
        writePubspec(version: '2.0.0');
        writePackageJson(version: '1.0.0');

        final dart = PublishTarget.pubDev.manifestIn(tmp, catalog);
        final node = PublishTarget.npm.manifestIn(tmp, catalog);

        expect(await dart.readName(), 'foo');
        expect(await dart.readVersion(), Version(2, 0, 0));
        expect(await node.readName(), '@org/foo');
        expect(await node.readVersion(), Version(1, 0, 0));
      });
    });

    // .........................................................................
    group('specIn(directory, catalog)', () {
      test('returns the catalog entry of the target', () {
        writePubspec();
        writePackageJson();
        expect(
          PublishTarget.pubDev.specIn(tmp, catalog).manifest.file,
          'pubspec.yaml',
        );
        expect(
          PublishTarget.npm.specIn(tmp, catalog).manifest.file,
          'package.json',
        );
      });
    });
  });

  // ###########################################################################
  group('PublishTargetsX', () {
    test('ordered puts pub.dev before npm', () {
      expect(
        <PublishTarget>{PublishTarget.npm, PublishTarget.pubDev}.ordered,
        <PublishTarget>[PublishTarget.pubDev, PublishTarget.npm],
      );
    });

    test('isGitOnly is true only for an empty set', () {
      expect(<PublishTarget>{}.isGitOnly, isTrue);
      expect(<PublishTarget>{PublishTarget.npm}.isGitOnly, isFalse);
    });

    test('label describes the set', () {
      expect(<PublishTarget>{}.label, 'none');
      expect(<PublishTarget>{PublishTarget.pubDev}.label, 'pub.dev');
      expect(<PublishTarget>{PublishTarget.npm}.label, 'npm');
      expect(
        <PublishTarget>{PublishTarget.npm, PublishTarget.pubDev}.label,
        'pub.dev+npm',
      );
    });
  });

  // ###########################################################################
  group('publishTargetsOf(directory)', () {
    group('single language', () {
      test('a plain dart package publishes to pub.dev', () async {
        writePubspec();
        expect(await targets(), <PublishTarget>{PublishTarget.pubDev});
      });

      test('publish_to: none takes the dart package out', () async {
        writePubspec(publishTo: 'none');
        expect(await targets(), isEmpty);
      });

      test('a public typescript package publishes to npm', () async {
        writePackageJson();
        writeTsConfig();
        expect(await targets(), <PublishTarget>{PublishTarget.npm});
      });

      test('private: true takes the npm package out', () async {
        writePackageJson(private: true);
        writeTsConfig();
        expect(await targets(), isEmpty);
      });

      test('private: false publishes to npm', () async {
        writePackageJson(private: false);
        writeTsConfig();
        expect(await targets(), <PublishTarget>{PublishTarget.npm});
      });

      test(
        'a package.json without a tsconfig still publishes to npm',
        () async {
          // detectProjectType calls this »none«, but the manifest is there and
          // it is not private - so npm is a real target.
          writePackageJson();
          expect(await targets(), <PublishTarget>{PublishTarget.npm});
        },
      );

      test('a directory without a manifest publishes nowhere', () async {
        expect(await targets(), isEmpty);
      });
    });

    // .........................................................................
    group('hybrid', () {
      test('publishes to both when neither side opts out', () async {
        // The base_dna case.
        writePubspec();
        writePackageJson();
        expect(await targets(), <PublishTarget>{
          PublishTarget.pubDev,
          PublishTarget.npm,
        });
      });

      test('publish_to: none leaves npm alone', () async {
        // The ds_dna case: private on pub.dev, public on npm.
        writePubspec(publishTo: 'none');
        writePackageJson(private: false);
        expect(await targets(), <PublishTarget>{PublishTarget.npm});
      });

      test('private: true leaves pub.dev alone', () async {
        writePubspec();
        writePackageJson(private: true);
        expect(await targets(), <PublishTarget>{PublishTarget.pubDev});
      });

      test('both markers set publishes nowhere', () async {
        writePubspec(publishTo: 'none');
        writePackageJson(private: true);
        expect(await targets(), isEmpty);
      });
    });

    // .........................................................................
    group('broken manifests', () {
      test('an unparsable pubspec does not publish to pub.dev', () async {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: [\n');
        writePackageJson();
        expect(await targets(), <PublishTarget>{PublishTarget.npm});
      });

      test('an unparsable package.json does not publish to npm', () async {
        writePubspec();
        File('${tmp.path}/package.json').writeAsStringSync('{ "name": ');
        expect(await targets(), <PublishTarget>{PublishTarget.pubDev});
      });
    });

    // .........................................................................
    test('loads the bundled catalog when none is given', () async {
      writePubspec();
      expect(await publishTargetsOf(tmp), <PublishTarget>{
        PublishTarget.pubDev,
      });
    });
  });

  // ###########################################################################
  group('hybridVersions(directory)', () {
    test('returns both versions of a hybrid', () async {
      writePubspec(version: '1.0.2');
      writePackageJson(version: '1.0.1');

      final versions = await hybridVersions(tmp, catalog: catalog);
      expect(versions?.pubspec, Version(1, 0, 2));
      expect(versions?.packageJson, Version(1, 0, 1));
    });

    test('returns null for a non-hybrid', () async {
      writePubspec();
      expect(await hybridVersions(tmp, catalog: catalog), isNull);
    });

    test('returns null when a version cannot be parsed', () async {
      writePubspec(version: 'not-a-version');
      writePackageJson();
      expect(await hybridVersions(tmp, catalog: catalog), isNull);
    });

    test('loads the bundled catalog when none is given', () async {
      writePubspec(version: '1.0.0');
      writePackageJson(version: '1.0.0');
      expect((await hybridVersions(tmp))?.pubspec, Version(1, 0, 0));
    });
  });

  // ###########################################################################
  group('hybridVersionsDiffer(directory)', () {
    test('is true when the two manifests disagree', () async {
      writePubspec(version: '1.0.2');
      writePackageJson(version: '1.0.1');
      expect(await hybridVersionsDiffer(tmp, catalog: catalog), isTrue);
    });

    test('is false when they agree', () async {
      writePubspec(version: '1.0.1');
      writePackageJson(version: '1.0.1');
      expect(await hybridVersionsDiffer(tmp, catalog: catalog), isFalse);
    });

    test('is false for a non-hybrid', () async {
      writePubspec();
      expect(await hybridVersionsDiffer(tmp, catalog: catalog), isFalse);
    });

    test('is false when a version is unreadable', () async {
      // Callers use this to relax a check, so an unreadable manifest must not
      // trigger them.
      writePubspec(version: '1.0.0');
      File('${tmp.path}/package.json')
          .writeAsStringSync('{"name": "@org/foo"}');
      expect(await hybridVersionsDiffer(tmp, catalog: catalog), isFalse);
    });
  });
}
