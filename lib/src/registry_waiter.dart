// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_console_colors/gg_console_colors.dart';
import 'package:gg_lang/src/registry.dart';
import 'package:mocktail/mocktail.dart' as mocktail;
import 'package:pub_semver/pub_semver.dart';

// #############################################################################

/// Polls a [Registry] until a published version becomes visible.
///
/// Wraps any [Registry] (pub.dev / npm) with the shared "has this been
/// published yet?" and "wait until version X is visible" logic used by the
/// publish flow. Transient registry errors ([RegistryException], e.g. a 5xx
/// status or a flaky network) are treated as "not yet available" so they do
/// not abort an in-progress wait.
///
/// A wait is reported through [log] with exactly two messages: a start
/// message with the human-facing status page (see [statusUrl]) and a final
/// success message. Nothing is printed while polling — a message repeated
/// every minute only pushes the start message out of view without saying
/// anything new. The start message appears at most once per version and
/// process, and not at all when there is nothing to wait for — see
/// [waitUntilVersionAvailable].
/// The wait never hangs: every poll is bounded by the registry's own request
/// timeout, and the wait as a whole is bounded by [timeout].
class RegistryWaiter {
  /// Creates a waiter over [registry]. [registryName] is used in messages
  /// (e.g. `npm`, `pub.dev`); [delay] and [now] are injectable for tests.
  RegistryWaiter({
    required Registry registry,
    this.registryName = 'the registry',
    this.statusUrl,
    void Function(String message)? log,
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 2),
  }) : _registry = registry,
       _log = log,
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final Registry _registry;

  /// Human-readable registry name used in messages (e.g. `npm`, `pub.dev`).
  final String registryName;

  /// A human-facing web page template with a `{name}` placeholder where the
  /// publish status can be checked (e.g. the pub.dev versions page). Shown
  /// in the wait and timeout messages when configured.
  final String? statusUrl;

  final void Function(String message)? _log;
  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _now;

  /// Delay between poll attempts.
  final Duration pollInterval;

  /// Maximum time to wait for a version to appear.
  final Duration timeout;

  /// Returns [statusUrl] with the `{name}` placeholder resolved to
  /// [packageName], or null when no status url is configured.
  String? statusUrlFor({required String packageName}) =>
      statusUrl?.replaceAll('{name}', Uri.encodeComponent(packageName));

  /// Whether [packageName] has ever been published to the registry.
  Future<bool> isPublished({required String packageName}) async =>
      (await _latestVersion(packageName)) != null;

  /// Whether [version] of [packageName] is visible on the registry.
  ///
  /// Returns true once the registry's latest version is greater than or equal
  /// to [version] — reliable for the publish flow, where versions only
  /// increase, and where the just-published version becomes the latest.
  /// Prereleases never become the registry's latest version, so they are
  /// looked up in the full version list instead.
  Future<bool> isVersionAvailable({
    required String packageName,
    required String version,
  }) async {
    final target = Version.parse(version);

    if (target.isPreRelease) {
      return (await _allVersions(packageName)).contains(target);
    }

    final latest = await _latestVersion(packageName);
    return latest != null && latest >= target;
  }

  /// Waits until [version] of [packageName] becomes visible, or throws when
  /// [timeout] elapses. The timeout message contains the status page url
  /// (when configured), so the user can check the registry manually.
  ///
  /// The wait is announced at most once per version and process: the publish
  /// flow waits for the same version from more than one place (the repo
  /// publishing it, later repos depending on it), and each place builds its
  /// own waiter. A version that is already visible returns without logging
  /// anything at all — there is no wait to report. Success and timeout
  /// messages are not suppressed: a second wait that really has to poll
  /// still reports how it ended.
  Future<void> waitUntilVersionAvailable({
    required String packageName,
    required String version,
  }) async {
    final availableAlready = await isVersionAvailable(
      packageName: packageName,
      version: version,
    );
    if (availableAlready) {
      return;
    }

    final deadline = _now().add(timeout);
    final url = statusUrlFor(packageName: packageName);

    // Status messages are printed dark gray, the status url blue.
    final urlHint = url == null
        ? ''
        : '\n${darkGray('Check the status here:')} ${blue(url)}';

    // add() is false once the same version was announced before — a stale
    // registry response or a transient lookup error must not repeat the
    // announcement.
    if (_announced.add('$registryName/$packageName@$version')) {
      _log?.call(
        darkGray(
              'Waiting 2-10min until $packageName $version appears on '
              '$registryName.',
            ) +
            urlHint,
      );
    }

    while (true) {
      if (_now().isAfter(deadline)) {
        throw Exception(
          'Timed out waiting for $packageName $version to become '
          'available on $registryName after ${timeout.inSeconds} '
          'seconds.${url == null ? '' : '\nCheck the status here: $url'}',
        );
      }

      await _delay(pollInterval);

      final available = await isVersionAvailable(
        packageName: packageName,
        version: version,
      );
      if (available) {
        _log?.call(
          cDetail('$packageName $version is available on $registryName.'),
        );
        return;
      }
    }
  }

  // ...........................................................................
  /// The `registry/package@version` keys announced in this process.
  ///
  /// Deliberately static: the publish flow waits for the same version from
  /// several places and each place creates its own [RegistryWaiter], so an
  /// instance field could not tell a repeated announcement from a first one.
  static final Set<String> _announced = <String>{};

  /// Forgets which versions have been announced, so the next wait announces
  /// itself again. Intended for tests — call it in `setUp`.
  static void resetAnnouncements() => _announced.clear();

  // ...........................................................................
  /// Reads the latest version, treating transient registry errors as
  /// "not available" so a wait keeps polling instead of aborting.
  Future<Version?> _latestVersion(String packageName) async {
    try {
      return await _registry.latestVersion(packageName: packageName);
    } on RegistryException {
      return null;
    }
  }

  // ...........................................................................
  /// Reads all published versions, treating transient registry errors as
  /// "not available" so a wait keeps polling instead of aborting.
  Future<List<Version>> _allVersions(String packageName) async {
    try {
      return await _registry.allVersions(packageName: packageName);
    } on RegistryException {
      return [];
    }
  }
}

// #############################################################################
/// A mocktail mock.
class MockRegistryWaiter extends mocktail.Mock implements RegistryWaiter {}
