library coverage.resolver;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// [Resolver] resolves imports with respect to a given environment.
class Resolver {
  static const DART_PREFIX = 'dart:';
  static const PACKAGE_PREFIX = 'package:';
  static const FILE_PREFIX = 'file://';
  static const HTTP_PREFIX = 'http://';

  final String pkgRoot;
  final String sdkRoot;
  final List<String> failed = [];

  Resolver({packageRoot: null, sdkRoot: null})
      : pkgRoot = packageRoot,
        sdkRoot = sdkRoot;

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(String uri) {
    if (uri.startsWith(DART_PREFIX)) {
      if (sdkRoot == null) {
        // No sdk-root given, do not resolve dart: URIs.
        return null;
      }
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
      if (pkgRoot == null) {
        // No package-root given, do not resolve package: URIs.
        return null;
      }
      var path = uri.substring(PACKAGE_PREFIX.length, uri.length);
      return resolveSymbolicLinks('$pkgRoot/$path');
    }
    if (uri.startsWith(FILE_PREFIX)) {
      return resolveSymbolicLinks(p.fromUri(Uri.parse(uri)));
    }
    if (uri.startsWith(HTTP_PREFIX)) {
      return uri;
    }
    // We cannot deal with anything else.
    failed.add(uri);
    return null;
  }

  String resolveSymbolicLinks(String path) {
    return new File(p.normalize(path)).resolveSymbolicLinksSync();
  }
}

/// Loads the lines of imported resources.
class Loader {
  final List<String> failed = [];

  /// Loads an imported resource and returns a [Future] with a [List] of lines.
  /// Returns [null] if the resource could not be loaded.
  Future<List<String>> load(String uri) {
    if (uri.startsWith('http')) {
      Completer c = new Completer();
      HttpClient client = new HttpClient();
      client
          .getUrl(Uri.parse(uri))
          .then((request) => request.close())
          .then((response) => response.transform(UTF8.decoder).toList())
          .then((data) => c.complete(data))
          .then((_) => client.close())
          .catchError((e) {
        failed.add(uri);
        c.complete(null);
      });
      return c.future;
    }
    return new File(uri).readAsLines().catchError((e) => new Future.value());
  }
}
