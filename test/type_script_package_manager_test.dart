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
    tmp = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  group('detectTypeScriptPackageManager', () {
    test('returns pnpm when pnpm-lock.yaml exists', () {
      File('${tmp.path}/pnpm-lock.yaml').writeAsStringSync('');
      expect(
        detectTypeScriptPackageManager(tmp),
        TypeScriptPackageManager.pnpm,
      );
    });

    test('returns yarn when yarn.lock exists', () {
      File('${tmp.path}/yarn.lock').writeAsStringSync('');
      expect(
        detectTypeScriptPackageManager(tmp),
        TypeScriptPackageManager.yarn,
      );
    });

    test('pnpm wins over yarn when both lockfiles are present', () {
      File('${tmp.path}/pnpm-lock.yaml').writeAsStringSync('');
      File('${tmp.path}/yarn.lock').writeAsStringSync('');
      expect(
        detectTypeScriptPackageManager(tmp),
        TypeScriptPackageManager.pnpm,
      );
    });

    test('defaults to npm when no lockfile is present', () {
      expect(detectTypeScriptPackageManager(tmp), TypeScriptPackageManager.npm);
    });
  });

  group('TypeScriptPackageManager.execCommand', () {
    test('pnpm uses "pnpm exec <tool>"', () {
      final cmd = TypeScriptPackageManager.pnpm.execCommand('eslint', ['.']);
      expect(cmd.executable, 'pnpm');
      expect(cmd.args, ['exec', 'eslint', '.']);
    });

    test('yarn uses "yarn <tool>"', () {
      final cmd = TypeScriptPackageManager.yarn.execCommand('tsc', [
        '--noEmit',
      ]);
      expect(cmd.executable, 'yarn');
      expect(cmd.args, ['tsc', '--noEmit']);
    });

    test('npm uses "npx <tool>"', () {
      final cmd = TypeScriptPackageManager.npm.execCommand('vitest', [
        'run',
        '--coverage',
      ]);
      expect(cmd.executable, 'npx');
      expect(cmd.args, ['vitest', 'run', '--coverage']);
    });
  });
}
