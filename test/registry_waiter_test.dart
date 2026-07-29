// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_console_colors/gg_console_colors.dart';
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

    group('statusUrlFor', () {
      test('resolves the {name} placeholder', () {
        final waiter = RegistryWaiter(
          registry: registry,
          statusUrl: 'https://pub.dev/packages/{name}/versions',
        );
        expect(
          waiter.statusUrlFor(packageName: 'gg_lang'),
          'https://pub.dev/packages/gg_lang/versions',
        );
      });

      test('returns null when no status url is configured', () {
        final waiter = RegistryWaiter(registry: registry);
        expect(waiter.statusUrlFor(packageName: 'gg_lang'), isNull);
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

      test('logs start, progress and success messages with the url', () async {
        // Not available on the first poll, available on the second.
        var calls = 0;
        when(
          () => registry.latestVersion(packageName: any(named: 'packageName')),
        ).thenAnswer((_) async {
          calls++;
          return calls < 2 ? null : Version(1, 2, 4);
        });

        // A clock advancing one minute per look so the second poll crosses
        // the progress interval.
        var minute = 0;
        final logs = <String>[];
        final waiter = RegistryWaiter(
          registry: registry,
          registryName: 'pub.dev',
          statusUrl: 'https://pub.dev/packages/{name}/versions',
          log: logs.add,
          delay: (_) async {},
          now: () => DateTime(2026, 1, 1, 0, minute++),
          timeout: const Duration(minutes: 30),
          progressInterval: const Duration(minutes: 1),
        );

        await waiter.waitUntilVersionAvailable(
          packageName: 'a',
          version: '1.2.4',
        );

        expect(
          logs[0],
          allOf(
            contains('Waiting until a 1.2.4 appears on pub.dev'),
            contains('https://pub.dev/packages/a/versions'),
          ),
        );
        expect(
          logs[1],
          allOf(
            contains('Still waiting for a 1.2.4 on pub.dev'),
            contains('elapsed'),
            contains('https://pub.dev/packages/a/versions'),
          ),
        );
        expect(logs[2], contains('a 1.2.4 is available on pub.dev'));
        expect(logs, hasLength(3));

        // Messages are dark gray, the url blue, the success message green.
        expect(
          logs[0],
          startsWith(
            darkGray('Waiting until a 1.2.4 appears on pub.dev (up to 30m).'),
          ),
        );
        expect(logs[0], contains(blue('https://pub.dev/packages/a/versions')));
        expect(logs[2], green('a 1.2.4 is available on pub.dev.'));
      });

      test('timeout message contains the status url when configured', () {
        mockLatest(null); // never available

        final times = <DateTime>[
          DateTime(2026),
          DateTime(2026),
          DateTime(2027),
        ];
        var i = 0;

        final waiter = RegistryWaiter(
          registry: registry,
          registryName: 'npm',
          statusUrl: 'https://www.npmjs.com/package/{name}',
          delay: (_) async {},
          now: () => times[i < times.length - 1 ? i++ : i],
          timeout: const Duration(minutes: 2),
        );

        expect(
          () => waiter.waitUntilVersionAvailable(
            packageName: '@scope/a',
            version: '1.0.0',
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('Timed out'),
                contains('https://www.npmjs.com/package/%40scope%2Fa'),
              ),
            ),
          ),
        );
      });

      test('formats the timeout compactly in the start message', () async {
        mockLatest(Version(9, 9, 9)); // available immediately

        Future<String> startMessage(Duration timeout) async {
          final logs = <String>[];
          final waiter = RegistryWaiter(
            registry: registry,
            log: logs.add,
            delay: (_) async {},
            timeout: timeout,
          );
          await waiter.waitUntilVersionAvailable(
            packageName: 'a',
            version: '1.0.0',
          );
          return logs.first;
        }

        expect(
          await startMessage(const Duration(seconds: 45)),
          contains('45s'),
        );
        expect(
          await startMessage(const Duration(seconds: 90)),
          contains('1m 30s'),
        );
        expect(await startMessage(const Duration(minutes: 2)), contains('2m'));
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
