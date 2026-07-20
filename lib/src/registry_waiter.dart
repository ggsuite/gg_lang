// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

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
class RegistryWaiter {
  /// Creates a waiter over [registry]. [registryName] is used in messages
  /// (e.g. `npm`, `pub.dev`); [delay] and [now] are injectable for tests.
  RegistryWaiter({
    required Registry registry,
    this.registryName = 'the registry',
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 2),
  }) : _registry = registry,
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final Registry _registry;

  /// Human-readable registry name used in messages (e.g. `npm`, `pub.dev`).
  final String registryName;

  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _now;

  /// Delay between poll attempts.
  final Duration pollInterval;

  /// Maximum time to wait for a version to appear.
  final Duration timeout;

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
  /// [timeout] elapses.
  Future<void> waitUntilVersionAvailable({
    required String packageName,
    required String version,
  }) async {
    final deadline = _now().add(timeout);

    while (true) {
      final available = await isVersionAvailable(
        packageName: packageName,
        version: version,
      );
      if (available) {
        return;
      }

      if (_now().isAfter(deadline)) {
        throw Exception(
          'Timed out waiting for $packageName $version to become '
          'available on $registryName after ${timeout.inSeconds} seconds.',
        );
      }

      await _delay(pollInterval);
    }
  }

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
