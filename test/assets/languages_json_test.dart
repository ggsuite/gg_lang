// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_lang/gg_lang.dart';
import 'package:test/test.dart';

void main() {
  group('languagesJsonSource', () {
    test('stays in sync with lib/src/assets/languages.json', () {
      // The JSON file is the editable source of truth; the constant is what
      // `LanguageCatalog.load` uses at runtime (AOT-safe). Both must match.
      final fromFile = File('lib/src/assets/languages.json')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .trim();
      final embedded = languagesJsonSource.replaceAll('\r\n', '\n').trim();
      expect(
        embedded,
        fromFile,
        reason:
            'lib/src/assets/languages_json.dart is out of sync with '
            'languages.json — copy the JSON content into the constant.',
      );
    });

    test('parses as a valid catalog', () {
      final catalog = LanguageCatalog.fromString(languagesJsonSource);
      expect(catalog.specByKey('dart'), isNotNull);
      expect(catalog.specByKey('flutter'), isNotNull);
      expect(catalog.specByKey('typescript'), isNotNull);
    });
  });
}
