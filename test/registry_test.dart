// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_process/gg_process.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

const _httpSpec = RegistrySpec(
  kind: 'http',
  url: 'https://pub.dev/api/packages/{name}',
  latestPath: 'latest.version',
  versionsPath: 'versions',
);

const _tsLang = LanguageSpec(
  displayName: 'TypeScript',
  manifest: ManifestSpec(
    file: 'package.json',
    format: 'json',
    versionPath: 'version',
    namePath: 'name',
    publishTargetMarker: 'private',
    lockFile: 'package-lock.json',
  ),
  registry: RegistrySpec(
    kind: 'cli',
    command: 'registryVersion',
    versionsCommand: 'registryVersions',
  ),
  commands: {
    'registryVersion': LanguageCommand(
      label: 'npm view {name} version',
      exec: 'npm',
      args: ['view', '{name}', 'version'],
    ),
    'registryVersions': LanguageCommand(
      label: 'npm view {name} versions --json',
      exec: 'npm',
      args: ['view', '{name}', 'versions', '--json'],
    ),
  },
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  group('PubDevRegistry', () {
    test('returns the latest published version', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'latest': {'version': '1.2.3'},
          }),
          200,
        ),
      );
      final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
      final version = await registry.latestVersion(packageName: 'foo');
      expect(version.toString(), '1.2.3');
    });

    test('returns null on 404 (never published)', () async {
      final client = MockClient((_) async => http.Response('', 404));
      final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
      expect(await registry.latestVersion(packageName: 'foo'), isNull);
    });

    test('throws on a non-200/404 status', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
      expect(
        registry.latestVersion(packageName: 'foo'),
        throwsA(isA<RegistryException>()),
      );
    });

    test('throws when the latest path is missing', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'other': 1}), 200),
      );
      final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
      expect(
        registry.latestVersion(packageName: 'foo'),
        throwsA(isA<RegistryException>()),
      );
    });

    test('throws when the request exceeds the request timeout', () async {
      // A stalled connection must not hang the caller forever.
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('', 200);
      });
      final registry = PubDevRegistry(
        spec: _httpSpec,
        httpClient: client,
        requestTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        registry.latestVersion(packageName: 'foo'),
        throwsA(
          isA<RegistryException>().having(
            (e) => e.message,
            'message',
            contains('No response from'),
          ),
        ),
      );
    });

    test('wraps transport errors', () async {
      final client = MockClient((_) async => throw const SocketException('x'));
      final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
      expect(
        registry.latestVersion(packageName: 'foo'),
        throwsA(isA<RegistryException>()),
      );
    });

    group('allVersions', () {
      test('returns all versions from a list of version objects', () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'versions': [
                {'version': '1.0.0'},
                {'version': '1.1.0-rc.1'},
                {'version': '1.1.0'},
              ],
            }),
            200,
          ),
        );
        final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
        final versions = await registry.allVersions(packageName: 'foo');
        expect(versions.map((v) => v.toString()), [
          '1.0.0',
          '1.1.0-rc.1',
          '1.1.0',
        ]);
      });

      test('supports plain version strings as list entries', () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'versions': ['1.0.0', '2.0.0'],
            }),
            200,
          ),
        );
        final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
        final versions = await registry.allVersions(packageName: 'foo');
        expect(versions.map((v) => v.toString()), ['1.0.0', '2.0.0']);
      });

      test('returns an empty list on 404 (never published)', () async {
        final client = MockClient((_) async => http.Response('', 404));
        final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
        expect(await registry.allVersions(packageName: 'foo'), isEmpty);
      });

      test('throws when the versions path is not a list', () async {
        final client = MockClient(
          (_) async => http.Response(jsonEncode({'versions': 'oops'}), 200),
        );
        final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
        expect(
          registry.allVersions(packageName: 'foo'),
          throwsA(isA<RegistryException>()),
        );
      });

      test('wraps an unparseable version entry as RegistryException', () async {
        // A malformed entry must surface as RegistryException (not a raw
        // FormatException) so callers catching RegistryException handle it.
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'versions': [
                {'version': 'not-a-version'},
              ],
            }),
            200,
          ),
        );
        final registry = PubDevRegistry(spec: _httpSpec, httpClient: client);
        expect(
          registry.allVersions(packageName: 'foo'),
          throwsA(isA<RegistryException>()),
        );
      });
    });
  });

  group('NpmRegistry', () {
    late MockGgProcessWrapper wrapper;

    setUp(() {
      wrapper = MockGgProcessWrapper();
    });

    void stub(ProcessResult result) {
      when(
        () => wrapper.run(any(), any(), runInShell: any(named: 'runInShell')),
      ).thenAnswer((_) async => result);
    }

    test('returns the highest published version', () async {
      stub(ProcessResult(0, 0, '["1.0.0", "4.5.6", "2.0.0"]\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      final version = await registry.latestVersion(packageName: 'ts_pkg');
      expect(version.toString(), '4.5.6');
    });

    test('ignores the "latest" dist-tag', () async {
      // A private feed (e.g. Azure Artifacts) can leave the "latest" dist-tag
      // pointing at an older release. `npm view <name> version` would then
      // report 0.0.0 and make 0.0.1 look unpublished. The version list is
      // authoritative, so the lookup must not go through the dist-tag.
      stub(ProcessResult(0, 0, '["0.0.0", "0.0.1"]\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      final version = await registry.latestVersion(packageName: 'ts_pkg');
      expect(version.toString(), '0.0.1');

      // The versions command is used, not the single-version one.
      verify(
        () => wrapper.run('npm', [
          'view',
          'ts_pkg',
          'versions',
          '--json',
        ], runInShell: any(named: 'runInShell')),
      ).called(1);
    });

    test('prefers a stable release over a higher prerelease', () async {
      stub(ProcessResult(0, 0, '["1.0.0", "1.1.0-rc.1"]\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      final version = await registry.latestVersion(packageName: 'ts_pkg');
      expect(version.toString(), '1.0.0');
    });

    test('falls back to prereleases when nothing stable exists', () async {
      stub(ProcessResult(0, 0, '["1.0.0-rc.1", "1.0.0-rc.2"]\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      final version = await registry.latestVersion(packageName: 'ts_pkg');
      expect(version.toString(), '1.0.0-rc.2');
    });

    test('handles a single published version', () async {
      stub(ProcessResult(0, 0, '"4.5.6"\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      final version = await registry.latestVersion(packageName: 'ts_pkg');
      expect(version.toString(), '4.5.6');
    });

    test('returns null on an npm E404', () async {
      stub(ProcessResult(0, 1, '', 'npm ERR! code E404'));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      expect(await registry.latestVersion(packageName: 'ts_pkg'), isNull);
    });

    test('returns null when stdout is empty', () async {
      stub(ProcessResult(0, 0, '\n', ''));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      expect(await registry.latestVersion(packageName: 'ts_pkg'), isNull);
    });

    test('throws on a non-404 npm error', () async {
      stub(ProcessResult(0, 1, '', 'npm ERR! network failure'));
      final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
      expect(
        registry.latestVersion(packageName: 'ts_pkg'),
        throwsA(isA<RegistryException>()),
      );
    });

    test('throws when the npm lookup exceeds the request timeout', () async {
      // npm waiting for interactive credentials must not hang the caller.
      when(
        () => wrapper.run(any(), any(), runInShell: any(named: 'runInShell')),
      ).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return ProcessResult(0, 0, '["1.0.0"]\n', '');
      });
      final registry = NpmRegistry(
        spec: _tsLang,
        processWrapper: wrapper,
        requestTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        registry.latestVersion(packageName: 'ts_pkg'),
        throwsA(
          isA<RegistryException>().having(
            (e) => e.message,
            'message',
            contains('did not finish within'),
          ),
        ),
      );
    });

    test('runs npm in the given working directory', () async {
      // npm resolves the project-level .npmrc from its CWD — without it,
      // packages on scoped/private registries look unpublished.
      when(
        () => wrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '["4.5.6"]\n', ''));
      final registry = NpmRegistry(
        spec: _tsLang,
        processWrapper: wrapper,
        workingDirectory: '/pkg/dir',
      );
      await registry.latestVersion(packageName: 'ts_pkg');
      verify(
        () => wrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: '/pkg/dir',
        ),
      ).called(1);
    });

    group('allVersions', () {
      test('parses the JSON list printed by npm view versions', () async {
        stub(ProcessResult(0, 0, '["1.0.0", "1.1.0-rc.1", "1.1.0"]\n', ''));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        final versions = await registry.allVersions(packageName: 'ts_pkg');
        expect(versions.map((v) => v.toString()), [
          '1.0.0',
          '1.1.0-rc.1',
          '1.1.0',
        ]);
      });

      test('wraps a single JSON string into a one-element list', () async {
        stub(ProcessResult(0, 0, '"1.0.0"\n', ''));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        final versions = await registry.allVersions(packageName: 'ts_pkg');
        expect(versions.map((v) => v.toString()), ['1.0.0']);
      });

      test('returns an empty list on an npm E404', () async {
        stub(ProcessResult(0, 1, '', 'npm ERR! code E404'));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        expect(await registry.allVersions(packageName: 'ts_pkg'), isEmpty);
      });

      test('returns an empty list when stdout is empty', () async {
        stub(ProcessResult(0, 0, '\n', ''));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        expect(await registry.allVersions(packageName: 'ts_pkg'), isEmpty);
      });

      test('throws on a non-404 npm error', () async {
        stub(ProcessResult(0, 1, '', 'npm ERR! network failure'));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        expect(
          registry.allVersions(packageName: 'ts_pkg'),
          throwsA(isA<RegistryException>()),
        );
      });

      test('wraps malformed JSON output as RegistryException', () async {
        stub(ProcessResult(0, 0, 'not json at all', ''));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        expect(
          registry.allVersions(packageName: 'ts_pkg'),
          throwsA(isA<RegistryException>()),
        );
      });

      test('wraps an unparseable version entry as RegistryException', () async {
        stub(ProcessResult(0, 0, '["1.0.0", "not-a-version"]', ''));
        final registry = NpmRegistry(spec: _tsLang, processWrapper: wrapper);
        expect(
          registry.allVersions(packageName: 'ts_pkg'),
          throwsA(isA<RegistryException>()),
        );
      });
    });
  });

  group('RegistryFactory', () {
    test('returns a PubDevRegistry for http registries', () {
      final spec = LanguageCatalog.fromString(_catalogJson)
          .spec(ProjectType.dart);
      final registry = const RegistryFactory().forProjectType(
        ProjectType.dart,
        spec: spec,
      );
      expect(registry, isA<PubDevRegistry>());
    });

    test('returns an NpmRegistry for cli registries', () {
      final registry = const RegistryFactory().forProjectType(
        ProjectType.typescript,
        spec: _tsLang,
      );
      expect(registry, isA<NpmRegistry>());
    });

    test('forwards the working directory to the NpmRegistry', () async {
      final wrapper = MockGgProcessWrapper();
      when(
        () => wrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, 0, '["1.0.0"]\n', ''));
      final registry = RegistryFactory(processWrapper: wrapper).forProjectType(
        ProjectType.typescript,
        spec: _tsLang,
        workingDirectory: '/pkg/dir',
      );
      await registry.latestVersion(packageName: 'ts_pkg');
      verify(
        () => wrapper.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
          workingDirectory: '/pkg/dir',
        ),
      ).called(1);
    });

    test('throws when no registry is configured', () {
      const spec = LanguageSpec(
        displayName: 'NoReg',
        manifest: ManifestSpec(
          file: 'pubspec.yaml',
          format: 'yaml',
          versionPath: 'version',
          namePath: 'name',
          publishTargetMarker: 'publish_to',
          lockFile: 'pubspec.lock',
        ),
        commands: {},
      );
      expect(
        () => const RegistryFactory().forProjectType(
          ProjectType.dart,
          spec: spec,
        ),
        throwsA(isA<RegistryException>()),
      );
    });

    test('throws on an unknown registry kind', () {
      const spec = LanguageSpec(
        displayName: 'Weird',
        manifest: ManifestSpec(
          file: 'pubspec.yaml',
          format: 'yaml',
          versionPath: 'version',
          namePath: 'name',
          publishTargetMarker: 'publish_to',
          lockFile: 'pubspec.lock',
        ),
        registry: RegistrySpec(kind: 'carrier-pigeon'),
        commands: {},
      );
      expect(
        () => const RegistryFactory().forProjectType(
          ProjectType.dart,
          spec: spec,
        ),
        throwsA(isA<RegistryException>()),
      );
    });
  });

  group('RegistryException', () {
    test('has a readable toString', () {
      expect(RegistryException('boom').toString(), contains('boom'));
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
      "registry": {
        "kind": "http",
        "url": "https://pub.dev/api/packages/{name}",
        "latestPath": "latest.version"
      },
      "commands": {}
    }
  }
}
''';
