// @license
// Copyright (c) 2025 Göran Hegenberg. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:gg_lang/src/assets/languages_json.dart';
import 'package:gg_lang/src/project_type.dart';

// #############################################################################

/// A single language-specific command, loaded from the language catalog.
///
/// Either [exec] (a directly invoked executable) or [tool] (a binary run via
/// the project's package manager, e.g. `npx`/`pnpm exec`) is set.
class LanguageCommand {
  /// Constructor.
  const LanguageCommand({
    required this.label,
    required this.args,
    this.exec,
    this.tool,
    this.runInShell = false,
  });

  /// Builds a [LanguageCommand] from its JSON representation.
  factory LanguageCommand.fromMap(Map<String, dynamic> map) => LanguageCommand(
    label: map['label'] as String,
    exec: map['exec'] as String?,
    tool: map['tool'] as String?,
    args: (map['args'] as List<dynamic>).cast<String>(),
    runInShell: map['runInShell'] as bool? ?? false,
  );

  /// A short human readable label, used for progress output.
  final String label;

  /// The directly invoked executable, e.g. `dart` or `npm`. Null when [tool]
  /// is set.
  final String? exec;

  /// A package-manager-provided binary, e.g. `tsc` or `eslint`. Null when
  /// [exec] is set.
  final String? tool;

  /// The arguments passed to [exec] / [tool].
  final List<String> args;

  /// Whether the command must run through a shell (required for Node tooling
  /// on Windows, which ships as `.cmd`/`.ps1` launchers).
  final bool runInShell;

  /// Returns a copy of this command with every `{key}` placeholder in [label],
  /// [exec], [tool] and [args] replaced by the matching value in [values].
  LanguageCommand withValues(Map<String, String> values) {
    String sub(String input) {
      var result = input;
      values.forEach((key, value) {
        result = result.replaceAll('{$key}', value);
      });
      return result;
    }

    return LanguageCommand(
      label: sub(label),
      exec: exec == null ? null : sub(exec!),
      tool: tool == null ? null : sub(tool!),
      args: args.map(sub).toList(),
      runInShell: runInShell,
    );
  }
}

// #############################################################################

/// Describes where a language stores its package metadata (name, version,
/// publish target).
class ManifestSpec {
  /// Constructor.
  const ManifestSpec({
    required this.file,
    required this.format,
    required this.versionPath,
    required this.namePath,
    required this.publishTargetMarker,
    required this.lockFile,
  });

  /// Builds a [ManifestSpec] from its JSON representation.
  factory ManifestSpec.fromMap(Map<String, dynamic> map) => ManifestSpec(
    file: map['file'] as String,
    format: map['format'] as String,
    versionPath: map['versionPath'] as String,
    namePath: map['namePath'] as String,
    publishTargetMarker: map['publishTargetMarker'] as String,
    lockFile: map['lockFile'] as String,
  );

  /// The manifest file name, e.g. `pubspec.yaml` or `package.json`.
  final String file;

  /// The manifest format, either `yaml` or `json`.
  final String format;

  /// The field holding the package version.
  final String versionPath;

  /// The field holding the package name.
  final String namePath;

  /// The field whose presence marks the package as not published to the
  /// public registry (Dart: `publish_to`, npm: `private`).
  final String publishTargetMarker;

  /// The dependency lock file, e.g. `pubspec.lock` or `package-lock.json`.
  final String lockFile;
}

// #############################################################################

/// Describes how a language's package manager wraps tool invocations.
class PackageManagerSpec {
  /// Constructor.
  const PackageManagerSpec({required this.wrap});

  /// Builds a [PackageManagerSpec] from its JSON representation.
  factory PackageManagerSpec.fromMap(Map<String, dynamic> map) =>
      PackageManagerSpec(wrap: map['wrap'] as bool);

  /// Whether [LanguageCommand]s referencing a `tool` must be wrapped by the
  /// detected package manager (`npx <tool>` etc.).
  final bool wrap;
}

// #############################################################################

/// Describes how to query the version a package has published to its registry.
///
/// Two kinds are supported:
/// - `http` — a JSON endpoint queried over HTTP (e.g. pub.dev). [url] is a
///   `{name}` placeholder template, [latestPath] is the dotted path to the
///   version string in the response body.
/// - `cli`  — a [LanguageCommand] (referenced by [command]) whose stdout is the
///   published version (e.g. `npm view {name} version`).
class RegistrySpec {
  /// Constructor.
  const RegistrySpec({
    required this.kind,
    this.url,
    this.statusUrl,
    this.latestPath,
    this.versionsPath,
    this.command,
    this.versionsCommand,
  });

  /// Builds a [RegistrySpec] from its JSON representation.
  factory RegistrySpec.fromMap(Map<String, dynamic> map) => RegistrySpec(
    kind: map['kind'] as String,
    url: map['url'] as String?,
    statusUrl: map['statusUrl'] as String?,
    latestPath: map['latestPath'] as String?,
    versionsPath: map['versionsPath'] as String?,
    command: map['command'] as String?,
    versionsCommand: map['versionsCommand'] as String?,
  );

  /// Either `http` or `cli`.
  final String kind;

  /// For `http`: the request URL with a `{name}` placeholder.
  final String? url;

  /// A human-facing web page with a `{name}` placeholder where the publish
  /// status of a package can be checked (e.g. the pub.dev versions page).
  final String? statusUrl;

  /// Returns [statusUrl] with the `{name}` placeholder resolved to
  /// [packageName], or null when no status url is configured.
  String? statusUrlFor(String packageName) =>
      statusUrl?.replaceAll('{name}', Uri.encodeComponent(packageName));

  /// For `http`: the dotted path to the version string in the JSON response
  /// (e.g. `latest.version`).
  final String? latestPath;

  /// For `http`: the dotted path to the list of all published versions in
  /// the JSON response (e.g. `versions`). Entries may be plain version
  /// strings or objects carrying a `version` field.
  final String? versionsPath;

  /// For `cli`: the command key in [LanguageSpec.commands] to run.
  final String? command;

  /// For `cli`: the command key in [LanguageSpec.commands] listing all
  /// published versions as JSON (e.g. `npm view {name} versions --json`).
  final String? versionsCommand;
}

// #############################################################################

/// All language-specific configuration for a single language.
class LanguageSpec {
  /// Constructor.
  const LanguageSpec({
    required this.displayName,
    required this.manifest,
    required this.commands,
    this.packageManager,
    this.registry,
  });

  /// Builds a [LanguageSpec] from its JSON representation.
  factory LanguageSpec.fromMap(Map<String, dynamic> map) {
    final commands = <String, LanguageCommand>{};
    (map['commands'] as Map<String, dynamic>).forEach((key, value) {
      commands[key] = LanguageCommand.fromMap(value as Map<String, dynamic>);
    });

    final pmRaw = map['packageManager'] as Map<String, dynamic>?;
    final registryRaw = map['registry'] as Map<String, dynamic>?;

    return LanguageSpec(
      displayName: map['displayName'] as String,
      manifest: ManifestSpec.fromMap(map['manifest'] as Map<String, dynamic>),
      packageManager: pmRaw == null ? null : PackageManagerSpec.fromMap(pmRaw),
      registry: registryRaw == null ? null : RegistrySpec.fromMap(registryRaw),
      commands: commands,
    );
  }

  /// A human readable language name.
  final String displayName;

  /// The package metadata description.
  final ManifestSpec manifest;

  /// The package manager wrapping behaviour, or null when not applicable.
  final PackageManagerSpec? packageManager;

  /// How to query the published version from the registry, or null when the
  /// language has no registry configured.
  final RegistrySpec? registry;

  /// All commands defined for this language, keyed by capability
  /// (`install`, `analyze`, `formatFix`, `test`, `publish`, ...).
  final Map<String, LanguageCommand> commands;

  /// Returns the command for [capability]. Throws when it is not defined.
  LanguageCommand command(String capability) {
    final command = commands[capability];
    if (command == null) {
      throw ArgumentError('No "$capability" command defined for $displayName.');
    }
    return command;
  }

  /// Whether a command for [capability] is defined.
  bool hasCommand(String capability) => commands.containsKey(capability);
}

// #############################################################################

/// The catalog of all language-specific commands, loaded from
/// `lib/src/assets/languages.json`.
class LanguageCatalog {
  /// Constructor.
  const LanguageCatalog(this._byKey);

  /// Parses a [LanguageCatalog] from a JSON [source] string.
  factory LanguageCatalog.fromString(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final languages = root['languages'] as Map<String, dynamic>;
    final byKey = <String, LanguageSpec>{};
    languages.forEach((key, value) {
      byKey[key] = LanguageSpec.fromMap(value as Map<String, dynamic>);
    });
    return LanguageCatalog(byKey);
  }

  final Map<String, LanguageSpec> _byKey;

  /// Maps a [ProjectType] to its language key in the catalog.
  static const Map<ProjectType, String> _keys = {
    ProjectType.dart: 'dart',
    ProjectType.flutter: 'flutter',
    ProjectType.typescript: 'typescript',
  };

  /// Returns the [LanguageSpec] for [type].
  ///
  /// Throws an [ArgumentError] for [ProjectType.none] — a project without a
  /// manifest has no language commands, manifest or registry.
  LanguageSpec spec(ProjectType type) {
    final key = _keys[type];
    if (key == null) {
      throw ArgumentError(
        'No language spec exists for ProjectType.${type.name} — '
        'a project without a manifest has no language commands, '
        'manifest or registry.',
      );
    }
    return specByKey(key);
  }

  /// Returns the [LanguageSpec] registered under [key]. Throws when unknown.
  LanguageSpec specByKey(String key) {
    final spec = _byKey[key];
    if (spec == null) {
      throw ArgumentError('No language "$key" defined in the catalog.');
    }
    return spec;
  }

  /// Loads the bundled catalog.
  ///
  /// The catalog is embedded as a Dart constant (see
  /// `lib/src/assets/languages_json.dart`) instead of being read from the
  /// `languages.json` asset at runtime, so this also works in AOT-compiled
  /// executables — there `Isolate.resolvePackageUri` returns null and asset
  /// files cannot be located.
  static Future<LanguageCatalog> load() async =>
      LanguageCatalog.fromString(languagesJsonSource);
}
