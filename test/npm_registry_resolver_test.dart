// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:gg_process/gg_process.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  // ###########################################################################
  group('npmStatusUrlTemplate(registryUrl)', () {
    group('the public npm registry', () {
      for (final host in <String>[
        'https://registry.npmjs.org/',
        'https://registry.npmjs.org',
        'https://registry.npmjs.com/',
        'https://registry.yarnpkg.com/',
        'HTTPS://REGISTRY.NPMJS.ORG/',
      ]) {
        test('maps $host to the npmjs.com versions tab', () {
          expect(npmStatusUrlTemplate(host), npmjsStatusUrl);
        });
      }
    });

    // .........................................................................
    group('Azure Artifacts', () {
      test('maps a project-scoped feed to its feed page', () {
        // The ds_dna case.
        expect(
          npmStatusUrlTemplate(
            'https://pkgs.dev.azure.com/mhk-carat/ds_cdm/_packaging/'
            'ds-cdm/npm/registry/',
          ),
          'https://dev.azure.com/mhk-carat/ds_cdm/_artifacts/feed/ds-cdm',
        );
      });

      test('maps an organization-scoped feed to its feed page', () {
        expect(
          npmStatusUrlTemplate(
            'https://pkgs.dev.azure.com/mhk-carat/_packaging/'
            'ds-cdm/npm/registry/',
          ),
          'https://dev.azure.com/mhk-carat/_artifacts/feed/ds-cdm',
        );
      });

      test('strips a feed view from the feed name', () {
        // A feed addressed through one of its views (@local, @release) must
        // still link to the feed itself.
        expect(
          npmStatusUrlTemplate(
            'https://pkgs.dev.azure.com/mhk-carat/ds_cdm/_packaging/'
            'ds-cdm@local/npm/registry/',
          ),
          'https://dev.azure.com/mhk-carat/ds_cdm/_artifacts/feed/ds-cdm',
        );
      });

      test('moves the org out of a legacy visualstudio.com host', () {
        expect(
          npmStatusUrlTemplate(
            'https://mhk-carat.pkgs.visualstudio.com/ds_cdm/_packaging/'
            'ds-cdm/npm/registry/',
          ),
          'https://dev.azure.com/mhk-carat/ds_cdm/_artifacts/feed/ds-cdm',
        );
      });

      test('handles a legacy host without a project', () {
        expect(
          npmStatusUrlTemplate(
            'https://mhk-carat.pkgs.visualstudio.com/_packaging/'
            'ds-cdm/npm/registry/',
          ),
          'https://dev.azure.com/mhk-carat/_artifacts/feed/ds-cdm',
        );
      });

      test('keeps a self-hosted Azure DevOps Server on its own host', () {
        expect(
          npmStatusUrlTemplate(
            'https://tfs.example.com:8080/DefaultCollection/proj/_packaging/'
            'feed1/npm/registry/',
          ),
          'https://tfs.example.com:8080/DefaultCollection/proj/'
          '_artifacts/feed/feed1',
        );
      });

      test('falls back when _packaging is the last segment', () {
        expect(
          npmStatusUrlTemplate('https://pkgs.dev.azure.com/org/_packaging'),
          'https://pkgs.dev.azure.com/org/_packaging/{name}',
        );
      });

      test('falls back when the org part of a legacy host is empty', () {
        expect(
          npmStatusUrlTemplate(
            'https://.pkgs.visualstudio.com/_packaging/feed1/npm/registry/',
          ),
          'https://.pkgs.visualstudio.com/_packaging/feed1/npm/registry/{name}',
        );
      });
    });

    // .........................................................................
    group('unknown registries', () {
      test('falls back to the packument url', () {
        expect(
          npmStatusUrlTemplate('https://npm.pkg.github.com/'),
          'https://npm.pkg.github.com/{name}',
        );
      });

      test('adds exactly one slash when the registry has none', () {
        expect(
          npmStatusUrlTemplate('https://verdaccio.example.com'),
          'https://verdaccio.example.com/{name}',
        );
      });

      test('collapses repeated trailing slashes', () {
        expect(
          npmStatusUrlTemplate('https://verdaccio.example.com///'),
          'https://verdaccio.example.com/{name}',
        );
      });

      test('trims surrounding whitespace', () {
        expect(
          npmStatusUrlTemplate('  https://verdaccio.example.com/  '),
          'https://verdaccio.example.com/{name}',
        );
      });
    });

    // .........................................................................
    group('malformed input', () {
      test('a value without an authority falls back', () {
        expect(npmStatusUrlTemplate('not-a-url'), 'not-a-url/{name}');
      });

      test('an unparsable value falls back instead of throwing', () {
        expect(npmStatusUrlTemplate('http://[::1'), 'http://[::1/{name}');
      });

      test('an empty value falls back instead of throwing', () {
        expect(npmStatusUrlTemplate(''), '/{name}');
      });
    });
  });

  // ###########################################################################
  group('NpmRegistryResolver', () {
    late Directory tmp;
    late MockGgProcessWrapper wrapper;
    late NpmRegistryResolver resolver;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gg_npm_registry_resolver_');
      wrapper = MockGgProcessWrapper();
      resolver = NpmRegistryResolver(processWrapper: wrapper);
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    // .........................................................................
    void writePackageJson(String content) {
      File('${tmp.path}/package.json').writeAsStringSync(content);
    }

    void stubConfig(String key, {String? value, int exitCode = 0}) {
      when(
        () => wrapper.run(
          any(),
          <String>['config', 'get', key],
          workingDirectory: any(named: 'workingDirectory'),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((_) async => ProcessResult(0, exitCode, value ?? '', ''));
    }

    // .........................................................................
    group('registryOf(directory)', () {
      test('prefers publishConfig.registry from package.json', () async {
        writePackageJson(
          '{"name": "@org/foo", '
          '"publishConfig": {"registry": "https://publish.example/"}}',
        );

        expect(
          await resolver.registryOf(directory: tmp),
          'https://publish.example/',
        );

        // No config lookup is needed when package.json already answers.
        verifyNever(
          () => wrapper.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        );
      });

      test('falls back to the scope registry for a scoped package', () async {
        writePackageJson('{"name": "@carat-ds/ds-dna"}');
        stubConfig('@carat-ds:registry', value: 'https://azure.example/feed/');

        expect(
          await resolver.registryOf(directory: tmp),
          'https://azure.example/feed/',
        );
      });

      test(
        'falls back to the default registry when the scope has none',
        () async {
          writePackageJson('{"name": "@org/foo"}');
          stubConfig('@org:registry', value: 'undefined');
          stubConfig('registry', value: 'https://registry.npmjs.org/');

          expect(
            await resolver.registryOf(directory: tmp),
            'https://registry.npmjs.org/',
          );
        },
      );

      test('skips the scope lookup for an unscoped package', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');

        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.npmjs.org/',
        );

        verifyNever(
          () => wrapper.run(
            any(),
            <String>['config', 'get', '@org:registry'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        );
      });

      test('works without a package.json at all', () async {
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.npmjs.org/',
        );
      });

      test('tolerates an unparsable package.json', () async {
        writePackageJson('{ "name": ');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.npmjs.org/',
        );
      });

      test('tolerates a package.json that is not an object', () async {
        writePackageJson('[1, 2, 3]');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.npmjs.org/',
        );
      });

      test('ignores a publishConfig without a registry field', () async {
        writePackageJson('{"name": "foo", "publishConfig": {"access": "l"}}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.npmjs.org/',
        );
      });

      test('treats a failing lookup as no registry', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', exitCode: 1);
        expect(await resolver.registryOf(directory: tmp), isNull);
      });

      for (final empty in <String>['', '  ', 'undefined', 'null']) {
        test('treats "$empty" as no registry', () async {
          writePackageJson('{"name": "foo"}');
          stubConfig('registry', value: empty);
          expect(await resolver.registryOf(directory: tmp), isNull);
        });
      }

      test('strips quotes around the value', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: '"https://quoted.example/"');
        expect(
          await resolver.registryOf(directory: tmp),
          'https://quoted.example/',
        );
      });

      test('strips single quotes as well', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: "'https://quoted.example/'");
        expect(
          await resolver.registryOf(directory: tmp),
          'https://quoted.example/',
        );
      });

      test('picks the url line out of a noisy output', () async {
        // yarn classic wraps the value in a banner and a footer.
        writePackageJson('{"name": "foo"}');
        stubConfig(
          'registry',
          value:
              'yarn config v1.22.19\n'
              'https://registry.yarnpkg.com/\n'
              '✨  Done in 0.05s.\n',
        );
        expect(
          await resolver.registryOf(directory: tmp),
          'https://registry.yarnpkg.com/',
        );
      });

      test('falls back to the first meaningful line without a url', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: '\nlocalhost:4873\n');
        expect(await resolver.registryOf(directory: tmp), 'localhost:4873');
      });

      test('runs in the package directory so .npmrc is merged', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        await resolver.registryOf(directory: tmp);

        verify(
          () => wrapper.run(
            'npm',
            <String>['config', 'get', 'registry'],
            workingDirectory: tmp.path,
            runInShell: true,
          ),
        ).called(1);
      });

      test('uses the detected package manager', () async {
        File('${tmp.path}/pnpm-lock.yaml').writeAsStringSync('lockfileVersion');
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        await resolver.registryOf(directory: tmp);

        verify(
          () => wrapper.run(
            'pnpm',
            <String>['config', 'get', 'registry'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      test('honors an explicitly given package manager', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        await resolver.registryOf(
          directory: tmp,
          packageManager: TypeScriptPackageManager.yarn,
        );

        verify(
          () => wrapper.run(
            'yarn',
            <String>['config', 'get', 'registry'],
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      test('never reads an auth key', () async {
        writePackageJson('{"name": "@org/foo"}');
        stubConfig('@org:registry', value: 'undefined');
        stubConfig('registry', value: 'https://registry.npmjs.org/');
        await resolver.registryOf(directory: tmp);

        final keys = verify(
          () => wrapper.run(
            any(),
            captureAny(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).captured.cast<List<String>>().map((args) => args.last);

        expect(keys, everyElement(isNot(contains('_auth'))));
        expect(keys, everyElement(isNot(startsWith('//'))));
      });
    });

    // .........................................................................
    group('caching', () {
      test('resolves a directory only once', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');

        await resolver.registryOf(directory: tmp);
        await resolver.registryOf(directory: tmp);

        verify(
          () => wrapper.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      test('collapses concurrent lookups into one subprocess', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');

        await Future.wait(<Future<String?>>[
          resolver.registryOf(directory: tmp),
          resolver.registryOf(directory: tmp),
        ]);

        verify(
          () => wrapper.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(1);
      });

      test('clearCache() makes the next lookup resolve again', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');

        await resolver.registryOf(directory: tmp);
        resolver.clearCache();
        await resolver.registryOf(directory: tmp);

        verify(
          () => wrapper.run(
            any(),
            any(),
            workingDirectory: any(named: 'workingDirectory'),
            runInShell: any(named: 'runInShell'),
          ),
        ).called(2);
      });
    });

    // .........................................................................
    group('statusUrlTemplateOf(directory)', () {
      test('derives the template from the resolved registry', () async {
        writePackageJson('{"name": "@carat-ds/ds-dna"}');
        stubConfig(
          '@carat-ds:registry',
          value:
              'https://pkgs.dev.azure.com/mhk-carat/ds_cdm/_packaging/'
              'ds-cdm/npm/registry/',
        );

        expect(
          await resolver.statusUrlTemplateOf(directory: tmp),
          'https://dev.azure.com/mhk-carat/ds_cdm/_artifacts/feed/ds-cdm',
        );
      });

      test('returns the fallback when no registry is configured', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', exitCode: 1);

        expect(
          await resolver.statusUrlTemplateOf(
            directory: tmp,
            fallback: npmjsStatusUrl,
          ),
          npmjsStatusUrl,
        );
      });

      test('returns null when there is no fallback either', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', exitCode: 1);
        expect(await resolver.statusUrlTemplateOf(directory: tmp), isNull);
      });

      test('honors an explicitly given package manager', () async {
        writePackageJson('{"name": "foo"}');
        stubConfig('registry', value: 'https://registry.npmjs.org/');

        expect(
          await resolver.statusUrlTemplateOf(
            directory: tmp,
            packageManager: TypeScriptPackageManager.npm,
          ),
          npmjsStatusUrl,
        );
      });
    });

    // .........................................................................
    test('example instance can be created', () {
      expect(NpmRegistryResolver.example(), isA<NpmRegistryResolver>());
    });

    test('MockNpmRegistryResolver can be created', () {
      expect(MockNpmRegistryResolver(), isA<NpmRegistryResolver>());
    });
  });
}
