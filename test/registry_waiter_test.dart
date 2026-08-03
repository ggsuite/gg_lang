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
    RegistryWaiter.resetAnnouncements();
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

      test('logs only a start and a success message with the url', () async {
        // Unavailable for the first four polls, so a wait long enough for a
        // periodic progress message to have appeared is really covered.
        var calls = 0;
        when(
          () => registry.latestVersion(packageName: any(named: 'packageName')),
        ).thenAnswer((_) async {
          calls++;
          return calls < 5 ? null : Version(1, 2, 4);
        });

        // A clock advancing one minute per look, so every poll would cross a
        // one-minute progress interval.
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
        );

        await waiter.waitUntilVersionAvailable(
          packageName: 'a',
          version: '1.2.4',
        );

        expect(
          logs[0],
          allOf(
            contains('Waiting 2-10min until a 1.2.4 appears on pub.dev'),
            contains('https://pub.dev/packages/a/versions'),
          ),
        );
        expect(logs[1], contains('a 1.2.4 is available on pub.dev'));

        // Nothing is printed while polling: the start message must not be
        // pushed out of view by a message that says nothing new.
        expect(logs, hasLength(2));
        expect(logs.where((l) => l.contains('Still waiting')), isEmpty);

        // Messages are dark gray, the url blue, the success message green.
        expect(
          logs[0],
          startsWith(
            darkGray('Waiting 2-10min until a 1.2.4 appears on pub.dev.'),
          ),
        );
        expect(logs[0], contains(blue('https://pub.dev/packages/a/versions')));
        expect(logs[1], cDetail('a 1.2.4 is available on pub.dev.'));
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

      test('logs nothing when the version is already available', () async {
        mockLatest(Version(9, 9, 9)); // available on the first look

        final logs = <String>[];
        final delays = <Duration>[];
        final waiter = RegistryWaiter(
          registry: registry,
          registryName: 'pub.dev',
          statusUrl: 'https://pub.dev/packages/{name}/versions',
          log: logs.add,
          delay: (d) async => delays.add(d),
        );

        await waiter.waitUntilVersionAvailable(
          packageName: 'a',
          version: '1.0.0',
        );

        // Announcing a wait that does not happen would repeat the message —
        // the publish flow checks the same version from several places.
        expect(logs, isEmpty);
        expect(delays, isEmpty);
      });

      group('announces the wait only once per version and process', () {
        // Each waiter is not available on its first look, so without the
        // guard both would announce. The publish flow hits this whenever a
        // stale registry response or a transient lookup error makes an
        // already published version look unpublished again.
        Future<List<String>> waitTwice({
          String secondVersion = '1.2.4',
          String secondRegistryName = 'pub.dev',
        }) async {
          final logs = <String>[];

          Future<void> wait(String version, String registryName) async {
            var calls = 0;
            when(
              () => registry.latestVersion(
                packageName: any(named: 'packageName'),
              ),
            ).thenAnswer((_) async {
              calls++;
              return calls < 2 ? null : Version.parse(version);
            });

            // A fresh waiter per call — the publish flow builds one per wait.
            await RegistryWaiter(
              registry: registry,
              registryName: registryName,
              log: logs.add,
              delay: (_) async {},
            ).waitUntilVersionAvailable(packageName: 'a', version: version);
          }

          await wait('1.2.4', 'pub.dev');
          await wait(secondVersion, secondRegistryName);

          return logs;
        }

        test('so the second wait for the same version stays quiet', () async {
          final logs = await waitTwice();

          expect(
            logs.where((l) => l.contains('Waiting 2-10min until')),
            hasLength(1),
          );
          // The second wait really polls, so its outcome is still reported.
          expect(
            logs.where((l) => l.contains('is available on pub.dev')),
            hasLength(2),
          );
        });

        test('but another version announces itself', () async {
          final logs = await waitTwice(secondVersion: '1.2.5');
          expect(
            logs.where((l) => l.contains('Waiting 2-10min until')),
            hasLength(2),
          );
        });

        test('and so does another registry', () async {
          final logs = await waitTwice(secondRegistryName: 'npm');
          expect(
            logs.where((l) => l.contains('Waiting 2-10min until')),
            hasLength(2),
          );
        });
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
