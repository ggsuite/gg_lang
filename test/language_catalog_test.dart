// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:test/test.dart';

const _json = '''
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
      "commands": {
        "analyze": {
          "label": "dart analyze",
          "exec": "dart",
          "args": ["analyze", "--fatal-infos"]
        }
      }
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
      "registry": { "kind": "cli", "command": "registryVersion" },
      "packageManager": { "wrap": true },
      "commands": {
        "analyze": {
          "label": "tsc --noEmit",
          "tool": "tsc",
          "args": ["--noEmit"],
          "runInShell": true
        },
        "registryVersion": {
          "label": "npm view {name} version",
          "exec": "npm",
          "args": ["view", "{name}", "version"]
        }
      }
    }
  }
}
''';

void main() {
  late LanguageCatalog catalog;

  setUp(() {
    catalog = LanguageCatalog.fromString(_json);
  });

  group('LanguageCatalog', () {
    group('fromString', () {
      test('parses all languages', () {
        expect(catalog.specByKey('dart').displayName, 'Dart');
        expect(catalog.specByKey('typescript').displayName, 'TypeScript');
      });
    });

    group('spec', () {
      test('maps each ProjectType to its language key', () {
        expect(catalog.spec(ProjectType.dart).displayName, 'Dart');
        expect(catalog.spec(ProjectType.typescript).displayName, 'TypeScript');
      });
    });

    group('specByKey', () {
      test('throws for an unknown language', () {
        expect(() => catalog.specByKey('rust'), throwsA(isA<ArgumentError>()));
      });
    });

    group('load', () {
      test(
        'returns the embedded catalog (AOT-safe, no asset lookup)',
        () async {
          final loaded = await LanguageCatalog.load();
          expect(loaded.specByKey('dart').displayName, 'Dart');
          expect(loaded.specByKey('flutter'), isNotNull);
          expect(loaded.specByKey('typescript').displayName, 'TypeScript');
        },
      );
    });
  });

  group('LanguageSpec', () {
    test('exposes the manifest', () {
      final manifest = catalog.specByKey('typescript').manifest;
      expect(manifest.file, 'package.json');
      expect(manifest.format, 'json');
      expect(manifest.versionPath, 'version');
      expect(manifest.namePath, 'name');
      expect(manifest.publishTargetMarker, 'private');
      expect(manifest.lockFile, 'package-lock.json');
    });

    test('exposes the package manager when present', () {
      expect(catalog.specByKey('typescript').packageManager?.wrap, isTrue);
    });

    test('has a null package manager when absent', () {
      expect(catalog.specByKey('dart').packageManager, isNull);
    });

    group('registry', () {
      test('parses an http registry', () {
        final registry = catalog.specByKey('dart').registry;
        expect(registry?.kind, 'http');
        expect(registry?.url, 'https://pub.dev/api/packages/{name}');
        expect(registry?.latestPath, 'latest.version');
        expect(registry?.command, isNull);
      });

      test('parses a cli registry', () {
        final registry = catalog.specByKey('typescript').registry;
        expect(registry?.kind, 'cli');
        expect(registry?.command, 'registryVersion');
        expect(registry?.url, isNull);
      });
    });

    group('command', () {
      test('returns a defined command', () {
        expect(catalog.specByKey('dart').command('analyze').exec, 'dart');
      });

      test('throws for an undefined command', () {
        expect(
          () => catalog.specByKey('dart').command('publish'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('hasCommand', () {
      test('returns true for a defined command', () {
        expect(catalog.specByKey('dart').hasCommand('analyze'), isTrue);
      });

      test('returns false for an undefined command', () {
        expect(catalog.specByKey('dart').hasCommand('publish'), isFalse);
      });
    });
  });

  group('LanguageCommand', () {
    test('parses an exec command and defaults runInShell to false', () {
      final command = catalog.specByKey('dart').command('analyze');
      expect(command.label, 'dart analyze');
      expect(command.exec, 'dart');
      expect(command.tool, isNull);
      expect(command.args, ['analyze', '--fatal-infos']);
      expect(command.runInShell, isFalse);
    });

    test('parses a tool command with runInShell', () {
      final command = catalog.specByKey('typescript').command('analyze');
      expect(command.exec, isNull);
      expect(command.tool, 'tsc');
      expect(command.runInShell, isTrue);
    });

    group('withValues', () {
      test('replaces placeholders in an exec command', () {
        final command = catalog
            .specByKey('typescript')
            .command('registryVersion')
            .withValues({'name': 'my_pkg'});
        expect(command.label, 'npm view my_pkg version');
        expect(command.exec, 'npm');
        expect(command.tool, isNull);
        expect(command.args, ['view', 'my_pkg', 'version']);
      });

      test('replaces placeholders in a tool command', () {
        final command = catalog
            .specByKey('typescript')
            .command('analyze')
            .withValues({'name': 'unused'});
        expect(command.exec, isNull);
        expect(command.tool, 'tsc');
        expect(command.args, ['--noEmit']);
      });
    });
  });

  group('bundled languages.json asset', () {
    test('is valid and exposes dart, flutter and typescript', () {
      final source = File('lib/src/assets/languages.json').readAsStringSync();
      final bundled = LanguageCatalog.fromString(source);
      expect(bundled.spec(ProjectType.dart).command('analyze').exec, 'dart');
      expect(bundled.spec(ProjectType.flutter).command('test').exec, 'flutter');
      expect(
        bundled.spec(ProjectType.typescript).command('publish').exec,
        'npm',
      );
    });

    test('every language exposes a registry block', () {
      final source = File('lib/src/assets/languages.json').readAsStringSync();
      final bundled = LanguageCatalog.fromString(source);
      expect(bundled.spec(ProjectType.dart).registry?.kind, 'http');
      expect(bundled.spec(ProjectType.flutter).registry?.kind, 'http');
      expect(bundled.spec(ProjectType.typescript).registry?.kind, 'cli');
      expect(
        bundled.spec(ProjectType.typescript).registry?.command,
        'registryVersion',
      );
    });
  });
}
