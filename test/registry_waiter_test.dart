// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_lang/gg_lang.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  late MockRegistry registry;

  setUp(() {
    registry = MockRegistry();
  });

  void mockLatest(Version? version) {
    when(
      () => registry.latestVersion(packageName: any(named: 'packageName')),
    ).thenAnswer((_) async => version);
  }

  group('RegistryWaiter', () {
    group('isPublished', () {
      test('returns true when the registry has a latest version', () async {
        mockLatest(Version(1, 0, 0));
        final waiter = RegistryWaiter(registry: registry);
        expect(await waiter.isPublished(packageName: 'a'), isTrue);
      });

      test('returns false when the package was never published', () async {
        mockLatest(null);
        final waiter = RegistryWaiter(registry: registry);
        expect(await waiter.isPublished(packageName: 'a'), isFalse);
      });

      test('treats transient registry errors as not published', () async {
        when(
          () => registry.latestVersion(packageName: any(named: 'packageName')),
        ).thenThrow(RegistryException('boom'));
        final waiter = RegistryWaiter(registry: registry);
        expect(await waiter.isPublished(packageName: 'a'), isFalse);
      });
    });

    group('isVersionAvailable', () {
      test('true when latest >= version', () async {
        mockLatest(Version(1, 2, 4));
        final waiter = RegistryWaiter(registry: registry);
        expect(
          await waiter.isVersionAvailable(packageName: 'a', version: '1.2.4'),
          isTrue,
        );
      });

      test('false when latest < version', () async {
        mockLatest(Version(1, 2, 3));
        final waiter = RegistryWaiter(registry: registry);
        expect(
          await waiter.isVersionAvailable(packageName: 'a', version: '1.2.4'),
          isFalse,
        );
      });

      test('false when never published', () async {
        mockLatest(null);
        final waiter = RegistryWaiter(registry: registry);
        expect(
          await waiter.isVersionAvailable(packageName: 'a', version: '1.0.0'),
          isFalse,
        );
      });

      group('for a prerelease version', () {
        void mockAllVersions(List<Version> versions) {
          when(
            () => registry.allVersions(packageName: any(named: 'packageName')),
          ).thenAnswer((_) async => versions);
        }

        test('true when the full version list contains it', () async {
          // The latest version stays on the stable release — a prerelease
          // must still be found.
          mockAllVersions([Version(1, 2, 3), Version.parse('1.3.0-rc.1')]);
          final waiter = RegistryWaiter(registry: registry);
          expect(
            await waiter.isVersionAvailable(
              packageName: 'a',
              version: '1.3.0-rc.1',
            ),
            isTrue,
          );
          verifyNever(
            () =>
                registry.latestVersion(packageName: any(named: 'packageName')),
          );
        });

        test('false when the full version list lacks it', () async {
          mockAllVersions([Version(1, 2, 3)]);
          final waiter = RegistryWaiter(registry: registry);
          expect(
            await waiter.isVersionAvailable(
              packageName: 'a',
              version: '1.3.0-rc.1',
            ),
            isFalse,
          );
        });

        test('treats transient registry errors as not available', () async {
          when(
            () => registry.allVersions(packageName: any(named: 'packageName')),
          ).thenThrow(RegistryException('boom'));
          final waiter = RegistryWaiter(registry: registry);
          expect(
            await waiter.isVersionAvailable(
              packageName: 'a',
              version: '1.3.0-rc.1',
            ),
            isFalse,
          );
        });
      });
    });

    group('waitUntilVersionAvailable', () {
      test('returns once the version becomes available', () async {
        // Not available on the first poll, available on the second.
        var calls = 0;
        when(
          () => registry.latestVersion(packageName: any(named: 'packageName')),
        ).thenAnswer((_) async {
          calls++;
          return calls < 2 ? null : Version(1, 2, 4);
        });

        final delays = <Duration>[];
        final waiter = RegistryWaiter(
          registry: registry,
          delay: (d) async => delays.add(d),
          pollInterval: const Duration(seconds: 1),
        );

        await waiter.waitUntilVersionAvailable(
          packageName: 'a',
          version: '1.2.4',
        );

        expect(calls, 2);
        expect(delays, [const Duration(seconds: 1)]);
      });

      test('throws when the timeout elapses', () async {
        mockLatest(null); // never available

        // A clock that jumps past the deadline after the first poll.
        final times = <DateTime>[
          DateTime(2026),
          DateTime(2026),
          DateTime(2027),
        ];
        var i = 0;

        final waiter = RegistryWaiter(
          registry: registry,
          registryName: 'npm',
          delay: (_) async {},
          now: () => times[i < times.length - 1 ? i++ : i],
          timeout: const Duration(minutes: 2),
        );

        expect(
          () => waiter.waitUntilVersionAvailable(
            packageName: 'a',
            version: '1.0.0',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('Timed out'), contains('npm')),
            ),
          ),
        );
      });
    });
  });
}
