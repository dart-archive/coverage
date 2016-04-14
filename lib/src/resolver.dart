// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// [Resolver] resolves imports with respect to a given environment.
class Resolver {
  final String packageRoot;
  final String sdkRoot;

  Resolver({this.packageRoot, this.sdkRoot});

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(Uri uri) {
    if (uri.scheme == 'dart') {
      if (sdkRoot == null) {
        // No sdk-root given, do not resolve dart: URIs.
        return null;
      }

      // Resolve 'dart:something' to be something/something.dart in the SDK.
      var lib = uri.pathSegments.first;

      var pathSegments = [sdkRoot, 'lib', lib];

      if (uri.pathSegments.length > 1) {
        pathSegments.addAll(uri.pathSegments.skip(1));
      } else {
        pathSegments.add('${lib}.dart');
      }

      var filePath = p.joinAll(pathSegments);

      return _resolveSymbolicLinks(filePath);
    }
    if (uri.scheme == 'package') {
      if (packageRoot == null) {
        // No package-root given, do not resolve package: URIs.
        return null;
      }
      return _resolveSymbolicLinks(p.join(packageRoot, uri.path));
    }
    if (uri.scheme == 'file') {
      return _resolveSymbolicLinks(p.fromUri(uri));
    }

    throw new Exception('Could not resolve "$uri"');
  }
}

/// Returns a canonicalized path, or `null` if the path cannot be resolved.
String _resolveSymbolicLinks(String path) {
  var normalizedPath = p.normalize(path);
  var type = FileSystemEntity.typeSync(normalizedPath, followLinks: true);
  if (type == FileSystemEntityType.NOT_FOUND) return null;
  return new File(normalizedPath).resolveSymbolicLinksSync();
}
