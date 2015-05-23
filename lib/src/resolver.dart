library coverage.resolver;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// [Resolver] resolves imports with respect to a given environment.
class Resolver {
  static const DART_PREFIX = 'dart:';
  static const PACKAGE_PREFIX = 'package:';
  static const FILE_PREFIX = 'file://';

  @Deprecated('See packageRoot. Removal in 0.7.0.')
  String get pkgRoot => packageRoot;

  final String packageRoot;
  final String sdkRoot;
  final List<String> failed = [];

  Resolver({this.packageRoot, this.sdkRoot});

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(String uri) {
    if (uri.startsWith(DART_PREFIX)) {
      if (sdkRoot == null) {
        // No sdk-root given, do not resolve dart: URIs.
        return null;
      }
      // TODO(zoechi) remove when http://dartbug.com/22846 is fixed
      const internalFiles = const [
        'internal.dart',
        'iterable.dart',
        'list.dart',
        'lists.dart',
        'print.dart',
        'sort.dart',
        'symbol.dart',
      ];
      if (uri.startsWith('${DART_PREFIX}_builtin')) {
        failed.add(uri);
        return null;
      }
      if (uri.startsWith('${DART_PREFIX}_internal')) {
        if (internalFiles.firstWhere((f) => uri.endsWith(f),
                orElse: () => '') !=
            '') {
          uri = uri.replaceFirst(
              '${DART_PREFIX}_internal', '${DART_PREFIX}internal');
        }
        if (uri == '${DART_PREFIX}_internal') {
          failed.add(uri);
          return null;
        }
      }
      // end TODO(zoechi) 22846
      var slashPos = uri.indexOf('/');
      var filePath;
      if (slashPos != -1) {
        var path = uri.substring(DART_PREFIX.length, slashPos);
        // Drop patch files, since we don't have their source in the compiled
        // SDK.
        if (path.endsWith('-patch')) {
          failed.add(uri);
          return null;
        }
        // Canonicalize path. For instance: _collection-dev => _collection_dev.
        path = path.replaceAll('-', '_');
        filePath = '$sdkRoot/${path}${uri.substring(slashPos, uri.length)}';
      } else {
        // Resolve 'dart:something' to be something/something.dart in the SDK.
        var lib = uri.substring(DART_PREFIX.length, uri.length);
        filePath = '$sdkRoot/$lib/${lib}.dart';
      }
      return resolveSymbolicLinks(filePath);
    }
    if (uri.startsWith(PACKAGE_PREFIX)) {
      if (packageRoot == null) {
        // No package-root given, do not resolve package: URIs.
        return null;
      }
      var path = uri.substring(PACKAGE_PREFIX.length, uri.length);
      return resolveSymbolicLinks(p.join(packageRoot, path));
    }
    if (uri.startsWith(FILE_PREFIX)) {
      return resolveSymbolicLinks(p.fromUri(Uri.parse(uri)));
    }
    // We cannot deal with anything else.
    failed.add(uri);
    return null;
  }

  /// Returns a canonicalized path, or `null` if the path cannot be resolved.
  String resolveSymbolicLinks(String path) {
    var normalizedPath = p.normalize(path);
    var type = FileSystemEntity.typeSync(normalizedPath, followLinks: true);
    if (type == FileSystemEntityType.NOT_FOUND) return null;
    return new File(normalizedPath).resolveSymbolicLinksSync();
  }
}

/// Loads the lines of imported resources.
class Loader {
  final List<String> failed = [];

  /// Loads an imported resource and returns a [Future] with a [List] of lines.
  /// Returns [null] if the resource could not be loaded.
  Future<List<String>> load(String path) async {
    try {
      return new File(path).readAsLines();
    } catch (_) {
      failed.add(path);
      return null;
    }
  }
}
