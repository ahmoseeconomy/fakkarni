// ignore_for_file: avoid_print
//
// Regenerates THIRD_PARTY_LICENSES.md from the resolved dependency graphs of
// both packages in this repo (the mobile app at `.` and the admin dashboard
// at `admin/`).
//
//   dart run tool/generate_licenses.dart
//
// Run it after any dependency change. It reads:
//   * `flutter pub deps --json`        — names, versions, dependency kinds
//   * `.dart_tool/package_config.json` — where each package actually lives
// and then reads the LICENSE file on disk. Nothing is hardcoded per package,
// so a new dependency shows up without anyone remembering.
//
// **A license it cannot identify is reported as `UNKNOWN`, never guessed.**
// Guessing here is worse than a blank: somebody would rely on it.

import 'dart:convert';
import 'dart:io';

/// Packages in these two lists are shipped inside the app binary. Anything
/// else is a build-time tool — still listed, but a copyleft build tool is a
/// different (and usually harmless) question from a copyleft runtime one.
const _packageDirs = {'mobile': '.', 'admin': 'admin'};

/// Longest match wins, so LGPL/AGPL are tested before plain GPL.
const _signatures = <String, List<String>>{
  'AGPL-3.0': ['gnu affero general public license'],
  'LGPL-3.0': ['gnu lesser general public license'],
  'GPL-3.0': ['gnu general public license'],
  'MPL-2.0': ['mozilla public license'],
  'Apache-2.0': ['apache license'],
  'Unlicense': ['this is free and unencumbered software released into the public domain'],
  'Zlib': ['altered source versions must be plainly marked as such'],
  'ISC': ['permission to use, copy, modify, and/or distribute this software'],
  'MIT': ['permission is hereby granted, free of charge'],
};

const _copyleft = {'AGPL-3.0', 'GPL-3.0', 'LGPL-3.0'};

class Pkg {
  Pkg(this.name, this.version, this.kind, this.license, this.shipped, this.used,
      this.path);
  final String name;
  final String version;
  final String kind; // direct | dev | transitive
  final String license;
  final bool shipped;
  final Set<String> used; // mobile / admin

  /// How this package enters the graph, e.g. `connectivity_plus > nm > dbus`.
  /// Printed for flagged packages so a reviewer can see the provenance
  /// instead of taking the flag on trust.
  final String path;
}

String _detect(Directory? root) {
  if (root == null || !root.existsSync()) return 'UNKNOWN (package not on disk)';
  // Packages shipped inside the Flutter SDK (`flutter_test`,
  // `flutter_localizations`, `sky_engine`…) carry no LICENSE of their own —
  // the SDK's root LICENSE governs them. So walk up a few levels before
  // giving up, rather than reporting a false UNKNOWN.
  for (var dir = root, hop = 0; hop < 6; hop++) {
    final found = _licenseIn(dir);
    if (found != null) return found;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return 'UNKNOWN (no LICENSE file)';
}

String? _licenseIn(Directory root) {
  for (final name in const [
    'LICENSE', 'LICENSE.md', 'LICENSE.txt',
    'LICENCE', 'LICENCE.md', 'COPYING', 'COPYING.md',
  ]) {
    final file = File('${root.path}/$name');
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    for (final entry in _signatures.entries) {
      for (final needle in entry.value) {
        if (text.contains(needle)) {
          // BSD has no single marker phrase; split the two common variants.
          if (entry.key == 'MIT' && text.contains('redistribution and use in source')) {
            return text.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
          }
          return entry.key;
        }
      }
    }
    if (text.contains('redistribution and use in source')) {
      return text.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
    }
    return 'UNKNOWN (unrecognised text in $name)';
  }
  return null;
}

Map<String, dynamic> _deps(String dir) {
  final result = Process.runSync(
    'flutter',
    ['pub', 'deps', '--json'],
    workingDirectory: dir,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('flutter pub deps failed in $dir:\n${result.stderr}');
    exit(1);
  }
  // `flutter` can print tool banners before the JSON.
  final out = result.stdout as String;
  return jsonDecode(out.substring(out.indexOf('{'))) as Map<String, dynamic>;
}

Map<String, Directory> _roots(String dir) {
  final file = File('$dir/.dart_tool/package_config.json');
  if (!file.existsSync()) {
    stderr.writeln('missing $file — run `flutter pub get` in $dir first');
    exit(1);
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final p in json['packages'] as List)
      (p as Map)['name'] as String:
          Directory.fromUri(file.uri.resolve(p['rootUri'] as String)),
  };
}

void main() {
  final merged = <String, Pkg>{};
  final flags = <String>[];

  for (final entry in _packageDirs.entries) {
    final label = entry.key;
    final deps = _deps(entry.value);
    final roots = _roots(entry.value);
    final packages = (deps['packages'] as List).cast<Map<String, dynamic>>();
    final byName = {for (final p in packages) p['name'] as String: p};
    final root = packages.firstWhere((p) => p['kind'] == 'root');

    // Reachable from the non-dev direct dependencies. Breadth-first, so the
    // recorded parent is the shortest path in.
    final shipped = <String>{};
    final parent = <String, String?>{};
    final queue = <String>[];
    for (final name in (root['directDependencies'] as List).cast<String>()) {
      parent[name] = null;
      queue.add(name);
    }
    for (var i = 0; i < queue.length; i++) {
      final name = queue[i];
      if (!shipped.add(name)) continue;
      for (final child in ((byName[name]?['dependencies'] ?? []) as List).cast<String>()) {
        if (parent.containsKey(child)) continue;
        parent[child] = name;
        queue.add(child);
      }
    }
    String pathTo(String name) {
      final chain = <String>[];
      String? at = name;
      while (at != null && chain.length < 12) {
        chain.insert(0, at);
        at = parent[at];
      }
      return chain.join(' > ');
    }

    for (final p in packages) {
      final name = p['name'] as String;
      if (p['kind'] == 'root') continue;
      final version = '${p['version']}';
      final key = '$name@$version';
      final existing = merged[key];
      if (existing != null) {
        existing.used.add(label);
        continue;
      }
      merged[key] = Pkg(
        name,
        version,
        p['kind'] as String,
        _detect(roots[name]),
        shipped.contains(name),
        {label},
        shipped.contains(name) ? pathTo(name) : '(dev only)',
      );
    }
  }

  final all = merged.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  for (final p in all) {
    final copyleft = _copyleft.contains(p.license);
    if (!copyleft && !p.license.startsWith('UNKNOWN')) continue;
    flags.add('`${p.name}` ${p.version} — ${copyleft ? '**${p.license}**' : p.license}'
        '${p.shipped ? '' : ' — build-time only'}\n'
        '  - reached via: `${p.path}`');
  }

  final buffer = StringBuffer()
    ..writeln('# Third-party licenses')
    ..writeln()
    ..writeln('Generated by `dart run tool/generate_licenses.dart` — do not edit by hand.')
    ..writeln('Regenerate after any dependency change.')
    ..writeln()
    ..writeln('Covers both packages in this repo: the mobile app (`.`) and the')
    ..writeln('admin dashboard (`admin/`).')
    ..writeln()
    ..writeln('**Ships** means the package is reachable from a non-dev dependency,')
    ..writeln('so it is part of the shipped dependency graph. Note this includes')
    ..writeln('platform implementations for platforms we do **not** build')
    ..writeln('(Linux, Windows, macOS): a federated plugin declares all of them,')
    ..writeln('and pub resolves all of them, but only the Android/iOS (or web,')
    ..writeln('for `admin/`) implementation is compiled into a released artifact.')
    ..writeln()
    ..writeln('| Total | Ships in a binary | Build-time only |')
    ..writeln('|---|---|---|')
    ..writeln('| ${all.length} | ${all.where((p) => p.shipped).length} | '
        '${all.where((p) => !p.shipped).length} |')
    ..writeln()
    ..writeln('## Red flags')
    ..writeln();

  if (flags.isEmpty) {
    buffer
      ..writeln('None. No GPL/AGPL/LGPL dependency, and every license was')
      ..writeln('identified from the package\'s own LICENSE file.')
      ..writeln();
  } else {
    buffer
      ..writeln('Review each of these before any public release.')
      ..writeln()
      ..writeln('**Read the `reached via` path first.** If it passes through a')
      ..writeln('`*_linux`, `*_windows` or `*_macos` package, this is desktop')
      ..writeln('support for a plugin we use on mobile — the code is resolved by')
      ..writeln('pub but is not compiled into the Android/iOS binaries. If the')
      ..writeln('path does **not** go through one of those, the package is a')
      ..writeln('direct dependency of something we really ship and needs a closer')
      ..writeln('look.')
      ..writeln()
      ..writeln('This file states the facts; whether an obligation is triggered is')
      ..writeln('a legal question for the company to answer, not a build question.')
      ..writeln();
    for (final f in flags) {
      buffer.writeln('- $f');
    }
    buffer.writeln();
  }

  buffer
    ..writeln('## Licenses in use')
    ..writeln()
    ..writeln('| License | Packages |')
    ..writeln('|---|---:|');
  final counts = <String, int>{};
  for (final p in all) {
    counts[p.license] = (counts[p.license] ?? 0) + 1;
  }
  final ordered = counts.keys.toList()..sort();
  for (final license in ordered) {
    buffer.writeln('| $license | ${counts[license]} |');
  }

  buffer
    ..writeln()
    ..writeln('## All dependencies')
    ..writeln()
    ..writeln('| Package | Version | License | Kind | Ships | Used by |')
    ..writeln('|---|---|---|---|---|---|');
  for (final p in all) {
    final used = (p.used.toList()..sort()).join(', ');
    buffer.writeln('| ${p.name} | ${p.version} | ${p.license} | ${p.kind} | '
        '${p.shipped ? 'yes' : 'no'} | $used |');
  }

  File('THIRD_PARTY_LICENSES.md').writeAsStringSync(buffer.toString());
  print('THIRD_PARTY_LICENSES.md — ${all.length} packages, ${flags.length} flag(s)');
  for (final f in flags) {
    print('  ! $f');
  }
}
