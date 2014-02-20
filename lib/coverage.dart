// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage;

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:isolate";

import "package:path/path.dart";

/// [Resolver] resolves imports with respect to a given environment.
class Resolver {
  static const DART_PREFIX = "dart:";
  static const PACKAGE_PREFIX = "package:";
  static const FILE_PREFIX = "file://";
  static const HTTP_PREFIX = "http://";

  Map _env;
  List failed = [];

  Resolver(this._env);

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(String uri) {
    if (uri.startsWith(DART_PREFIX)) {
      if (_env["sdkRoot"] == null) {
        // No sdk-root given, do not resolve dart: URIs.
        return null;
      }
      var slashPos = uri.indexOf("/");
      var filePath;
      if (slashPos != -1) {
        var path = uri.substring(DART_PREFIX.length, slashPos);
        // Drop patch files, since we don't have their source in the compiled
        // SDK.
        if (path.endsWith("-patch")) {
          failed.add(uri);
          return null;
        }
        // Canonicalize path. For instance: _collection-dev => _collection_dev.
        path = path.replaceAll("-", "_");
        filePath = "${_env["sdkRoot"]}"
                   "/${path}${uri.substring(slashPos, uri.length)}";
      } else {
        // Resolve 'dart:something' to be something/something.dart in the SDK.
        var lib = uri.substring(DART_PREFIX.length, uri.length);
        filePath = "${_env["sdkRoot"]}/${lib}/${lib}.dart";
      }
      return filePath;
    }
    if (uri.startsWith(PACKAGE_PREFIX)) {
      if (_env["pkgRoot"] == null) {
        // No package-root given, do not resolve package: URIs.
        return null;
      }
      var filePath =
          "${_env["pkgRoot"]}"
          "/${uri.substring(PACKAGE_PREFIX.length, uri.length)}";
      return filePath;
    }
    if (uri.startsWith(FILE_PREFIX)) {
      var filePath = fromUri(Uri.parse(uri));
      return filePath;
    }
    if (uri.startsWith(HTTP_PREFIX)) {
      return uri;
    }
    // We cannot deal with anything else.
    failed.add(uri);
    return null;
  }
}

/// Converts the given hitmap to lcov format and appends the result to
/// env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
Future lcov(Map hitmap, IOSink output) {
  var emitOne = (key) {
    var v = hitmap[key];
    StringBuffer entry = new StringBuffer();
    entry.write("SF:${key}\n");
    v.keys.toList()
          ..sort()
          ..forEach((k) {
      entry.write("DA:${k},${v[k]}\n");
    });
    entry.write("end_of_record\n");
    output.write(entry.toString());
    return new Future.value(null);
  };

  return Future.forEach(hitmap.keys, emitOne);
}

/// Converts the given hitmap to a pretty-print format and appends the result
/// to env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
Future prettyPrint(Map hitMap, List failedLoads, IOSink output) {
  var emitOne = (key) {
    var v = hitMap[key];
    var c = new Completer();
    loadResource(key).then((lines) {
      if (lines == null) {
        failedLoads.add(key);
        c.complete();
        return;
      }
      output.write("${key}\n");
      for (var line = 1; line <= lines.length; line++) {
        String prefix = "       ";
        if (v.containsKey(line)) {
          prefix = v[line].toString();
          StringBuffer b = new StringBuffer();
          for (int i = prefix.length; i < 7; i++) {
            b.write(" ");
          }
          b.write(prefix);
          prefix = b.toString();
        }
        output.write("${prefix}|${lines[line-1]}\n");
      }
      c.complete();
    });
    return c.future;
  };

  return Future.forEach(hitMap.keys, emitOne);
}

/// Load an import resource and return a [Future] with a [List] of its lines.
/// Returns [null] instead of a list if the resource could not be loaded.
Future<List> loadResource(String uri) {
  if (uri.startsWith("http")) {
    Completer c = new Completer();
    HttpClient client = new HttpClient();
    client.getUrl(Uri.parse(uri))
        .then((HttpClientRequest request) {
          return request.close();
        })
        .then((HttpClientResponse response) {
          response.transform(UTF8.decoder).toList().then((data) {
            c.complete(data);
            client.close();
          });
        })
        .catchError((e) {
          c.complete(null);
        });
    return c.future;
  } else {
    File f = new File(uri);
    return f.readAsLines()
        .catchError((e) {
          return new Future.value(null);
        });
  }
}

/// Creates a single hitmap from a raw json object. Throws away all entries that
/// are not resolvable.
Map createHitmap(String rawJson, Resolver resolver) {
  Map<String, Map<int,int>> hitMap = {};

  addToMap(source, line, count) {
    if (!hitMap[source].containsKey(line)) {
      hitMap[source][line] = 0;
    }
    hitMap[source][line] += count;
  }

  JSON.decode(rawJson)['coverage'].forEach((Map e) {
    String source = resolver.resolve(e["source"]);
    if (source == null) {
      // Couldnt resolve import, so skip this entry.
      return;
    }
    if (!hitMap.containsKey(source)) {
      hitMap[source] = {};
    }
    var hits = e["hits"];
    // hits is a flat array of the following format:
    // [ <line|linerange>, <hitcount>,...]
    // line: number.
    // linerange: "<line>-<line>".
    for (var i = 0; i < hits.length; i += 2) {
      var k = hits[i];
      if (k is num) {
        // Single line.
        addToMap(source, k, hits[i+1]);
      }
      if (k is String) {
        // Linerange. We expand line ranges to actual lines at this point.
        var splitPos = k.indexOf("-");
        int start = int.parse(k.substring(0, splitPos));
        int end = int.parse(k.substring(splitPos + 1, k.length));
        for (var j = start; j <= end; j++) {
          addToMap(source, j, hits[i+1]);
        }
      }
    }
  });
  return hitMap;
}

/// Merges [newMap] into [result].
mergeHitmaps(Map newMap, Map result) {
  newMap.forEach((String file, Map v) {
    if (result.containsKey(file)) {
      v.forEach((int line, int cnt) {
        if (result[file][line] == null) {
          result[file][line] = cnt;
        } else {
          result[file][line] += cnt;
        }
      });
    } else {
      result[file] = v;
    }
  });
}

/// Given an absolute path absPath, this function returns a [List] of files
/// are contained by it if it is a directory, or a [List] containing the file if
/// it is a file.
List filesToProcess(String absPath) {
  var filePattern = new RegExp(r"^dart-cov-\d+-\d+.json$");
  if (FileSystemEntity.isDirectorySync(absPath)) {
    return new Directory(absPath).listSync(recursive: true)
        .where((entity) => entity is File &&
            filePattern.hasMatch(basename(entity.path)))
        .toList();
  }

  return [new File(absPath)];
}

worker(WorkMessage msg) {
  final start = new DateTime.now().millisecondsSinceEpoch;

  var env = msg.environment;
  List files = msg.files;
  Resolver resolver = new Resolver(env);
  var workerHitmap = {};
  files.forEach((File fileEntry) {
    // Read file sync, as it only contains 1 object.
    String contents = fileEntry.readAsStringSync();
    if (contents.length > 0) {
      mergeHitmaps(createHitmap(contents, resolver), workerHitmap);
    }
  });

  if (env["verbose"]) {
    final end = new DateTime.now().millisecondsSinceEpoch;
    print("${msg.workerName}: Finished processing ${files.length} files. "
          "Took ${end - start} ms.");
  }

  msg.replyPort.send(new ResultMessage(workerHitmap, resolver.failed));
}

class WorkMessage {
  final String workerName;
  final Map environment;
  final List files;
  final SendPort replyPort;
  WorkMessage(this.workerName, this.environment, this.files, this.replyPort);
}

class ResultMessage {
  final hitmap;
  final failedResolves;
  ResultMessage(this.hitmap, this.failedResolves);
}

List<List> split(List list, int nBuckets) {
  var buckets = new List(nBuckets);
  var bucketSize = list.length ~/ nBuckets;
  var leftover = list.length % nBuckets;
  var taken = 0;
  var start = 0;
  for (int i = 0; i < nBuckets; i++) {
    var end = (i < leftover) ? (start + bucketSize + 1) : (start + bucketSize);
    buckets[i] = list.sublist(start, end);
    taken += buckets[i].length;
    start = end;
  }
  if (taken != list.length) throw "Error splitting";
  return buckets;
}

Future<ResultMessage> spawnWorker(name, environment, files) {
  RawReceivePort port = new RawReceivePort();
  var completer = new Completer();
  port.handler = ((ResultMessage msg) {
    completer.complete(msg);
    port.close();
  });
  var msg = new WorkMessage(name, environment, files, port.sendPort);
  Isolate.spawn(worker, msg);
  return completer.future;
}

/// [Environment] stores gathered arguments information.
class Environment {
  String sdkRoot;
  String pkgRoot;
  String input;
  IOSink output;
  int workers;
  bool prettyPrint;
  bool lcov;
  bool expectMarkers;
  bool verbose;
}