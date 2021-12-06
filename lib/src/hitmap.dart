// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert' show json;
import 'dart:io';

import 'package:coverage/src/resolver.dart';
import 'package:coverage/src/util.dart';

/// Contains line and function hit information for a single script.
class HitMap {
  /// Constructs a HitMap.
  HitMap([Map<int, int>? _lineHits, this.funcHits, this.funcNames])
      : lineHits = _lineHits ?? <int, int>{};

  /// Map from line to hit count for that line.
  final Map<int, int> lineHits;

  /// Map from the first line of each function, to the hit count for that
  /// function. Null if function coverage info was not gathered.
  Map<int, int>? funcHits;

  /// Map from the first line of each function, to the function name. Null if
  /// function coverage info was not gathered.
  Map<int, String>? funcNames;
}

/// Class containing information about a coverage hit.
class _HitInfo {
  _HitInfo(this.firstLine, this.hitRange, this.hitCount);

  /// The line number of the first line of this hit range.
  final int firstLine;

  /// A hit range is either a number (1 line) or a String of the form
  /// "start-end" (multi-line range).
  final dynamic hitRange;

  /// How many times this hit range was executed.
  final int hitCount;
}

/// Creates a single hitmap from a raw json object. Throws away all entries that
/// are not resolvable.
///
/// DEPRECATED: Migrate to createHitmapV2.
///
/// `jsonResult` is expected to be a List<Map<String, dynamic>>.
Future<Map<String, Map<int, int>>> createHitmap(
  List<Map<String, dynamic>> jsonResult, {
  bool checkIgnoredLines = false,
  String? packagesPath,
}) async {
  final result = await createHitmapV2(
    jsonResult,
    checkIgnoredLines: checkIgnoredLines,
    packagesPath: packagesPath,
  );
  return result.map((key, value) => MapEntry(key, value.lineHits));
}

/// Creates a single hitmap from a raw json object. Throws away all entries that
/// are not resolvable.
///
/// `jsonResult` is expected to be a List<Map<String, dynamic>>.
Future<Map<String, HitMap>> createHitmapV2(
  List<Map<String, dynamic>> jsonResult, {
  bool checkIgnoredLines = false,
  String? packagesPath,
}) async {
  final resolver = Resolver(packagesPath: packagesPath);
  final loader = Loader();

  // Map of source file to map of line to hit count for that line.
  final globalHitMap = <String, HitMap>{};

  for (var e in jsonResult) {
    final source = e['source'] as String?;
    if (source == null) {
      // Couldn't resolve import, so skip this entry.
      continue;
    }

    var ignoredLinesList = <List<int>>[];

    if (checkIgnoredLines) {
      final path = resolver.resolve(source);
      if (path != null) {
        final lines = await loader.load(path);
        ignoredLinesList = getIgnoredLines(lines!);

        // Ignore the whole file.
        if (ignoredLinesList.length == 1 &&
            ignoredLinesList[0][0] == 0 &&
            ignoredLinesList[0][1] == lines.length) {
          continue;
        }
      }
    }

    // Move to the first ignore range.
    final ignoredLines = ignoredLinesList.iterator;
    var hasCurrent = ignoredLines.moveNext();

    bool _shouldIgnoreLine(Iterator<List<int>> ignoredRanges, int line) {
      if (!hasCurrent || ignoredRanges.current.isEmpty) {
        return false;
      }

      if (line < ignoredRanges.current[0]) return false;

      while (hasCurrent &&
          ignoredRanges.current.isNotEmpty &&
          ignoredRanges.current[1] < line) {
        hasCurrent = ignoredRanges.moveNext();
      }

      if (hasCurrent &&
          ignoredRanges.current.isNotEmpty &&
          ignoredRanges.current[0] <= line &&
          line <= ignoredRanges.current[1]) {
        return true;
      }

      return false;
    }

    void addToMap(Map<int, int> map, int line, int count) {
      final oldCount = map.putIfAbsent(line, () => 0);
      map[line] = count + oldCount;
    }

    void fillHitMap(List hits, Map<int, int> hitMap) {
      // Ignore line annotations require hits to be sorted.
      hits = _sortHits(hits);
      // hits is a flat array of the following format:
      // [ <line|linerange>, <hitcount>,...]
      // line: number.
      // linerange: '<line>-<line>'.
      for (var i = 0; i < hits.length; i += 2) {
        final k = hits[i];
        if (k is int) {
          // Single line.
          if (_shouldIgnoreLine(ignoredLines, k)) continue;

          addToMap(hitMap, k, hits[i + 1] as int);
        } else if (k is String) {
          // Linerange. We expand line ranges to actual lines at this point.
          final splitPos = k.indexOf('-');
          final start = int.parse(k.substring(0, splitPos));
          final end = int.parse(k.substring(splitPos + 1));
          for (var j = start; j <= end; j++) {
            if (_shouldIgnoreLine(ignoredLines, j)) continue;

            addToMap(hitMap, j, hits[i + 1] as int);
          }
        } else {
          throw StateError('Expected value of type int or String');
        }
      }
    }

    final sourceHitMap = globalHitMap.putIfAbsent(source, () => HitMap());
    fillHitMap(e['hits'] as List, sourceHitMap.lineHits);
    if (e.containsKey('funcHits')) {
      sourceHitMap.funcHits ??= <int, int>{};
      fillHitMap(e['funcHits'] as List, sourceHitMap.funcHits!);
    }
    if (e.containsKey('funcNames')) {
      sourceHitMap.funcNames ??= <int, String>{};
      final funcNames = e['funcNames'] as List;
      for (var i = 0; i < funcNames.length; i += 2) {
        sourceHitMap.funcNames![funcNames[i] as int] =
            funcNames[i + 1] as String;
      }
    }
  }
  return globalHitMap;
}

/// Merges [newMap] into [result].
///
/// DEPRECATED: Migrate to mergeHitmapsV2.
void mergeHitmaps(
    Map<String, Map<int, int>> newMap, Map<String, Map<int, int>> result) {
  newMap.forEach((String file, Map<int, int> v) {
    final fileResult = result[file];
    if (fileResult != null) {
      v.forEach((int line, int cnt) {
        final lineFileResult = fileResult[line];
        if (lineFileResult == null) {
          fileResult[line] = cnt;
        } else {
          fileResult[line] = lineFileResult + cnt;
        }
      });
    } else {
      result[file] = v;
    }
  });
}

/// Merges [newMap] into [result].
void mergeHitmapsV2(Map<String, HitMap> newMap, Map<String, HitMap> result) {
  newMap.forEach((String file, HitMap v) {
    final fileResult = result[file];
    if (fileResult != null) {
      void mergeHitCounts(Map<int, int> src, Map<int, int> dest) {
        src.forEach((int line, int cnt) {
          final lineFileResult = dest[line];
          if (lineFileResult == null) {
            dest[line] = cnt;
          } else {
            dest[line] = lineFileResult + cnt;
          }
        });
      }

      mergeHitCounts(v.lineHits, fileResult.lineHits);
      if (v.funcHits != null) {
        fileResult.funcHits ??= <int, int>{};
        mergeHitCounts(v.funcHits!, fileResult.funcHits!);
      }
      if (v.funcNames != null) {
        fileResult.funcNames ??= <int, String>{};
        v.funcNames?.forEach((int line, String name) {
          fileResult.funcNames![line] = name;
        });
      }
    } else {
      result[file] = v;
    }
  });
}

/// Generates a merged hitmap from a set of coverage JSON files.
///
/// DEPRECATED: Migrate to parseCoverageV2.
Future<Map<String, Map<int, int>>> parseCoverage(
  Iterable<File> files,
  int _, {
  bool checkIgnoredLines = false,
  String? packagesPath,
}) async {
  final result = await parseCoverageV2(files, _,
      checkIgnoredLines: checkIgnoredLines, packagesPath: packagesPath);
  return result.map((key, value) => MapEntry(key, value.lineHits));
}

/// Generates a merged hitmap from a set of coverage JSON files.
Future<Map<String, HitMap>> parseCoverageV2(
  Iterable<File> files,
  int _, {
  bool checkIgnoredLines = false,
  String? packagesPath,
}) async {
  final globalHitmap = <String, HitMap>{};
  for (var file in files) {
    final contents = file.readAsStringSync();
    final jsonMap = json.decode(contents) as Map<String, dynamic>;
    if (jsonMap.containsKey('coverage')) {
      final jsonResult = jsonMap['coverage'] as List;
      mergeHitmapsV2(
        await createHitmapV2(
          jsonResult.cast<Map<String, dynamic>>(),
          checkIgnoredLines: checkIgnoredLines,
          packagesPath: packagesPath,
        ),
        globalHitmap,
      );
    }
  }
  return globalHitmap;
}

/// Returns a JSON hit map backward-compatible with pre-1.16.0 SDKs.
///
/// DEPRECATED: Migrate to toScriptCoverageJsonV2.
Map<String, dynamic> toScriptCoverageJson(Uri scriptUri, Map<int, int> hitMap) {
  return toScriptCoverageJsonV2(scriptUri, HitMap(hitMap));
}

/// Returns a JSON hit map backward-compatible with pre-1.16.0 SDKs.
Map<String, dynamic> toScriptCoverageJsonV2(Uri scriptUri, HitMap hits) {
  final json = <String, dynamic>{};
  List<T> flattenMap<T>(Map map) {
    final kvs = <T>[];
    map.forEach((k, v) {
      kvs.add(k as T);
      kvs.add(v as T);
    });
    return kvs;
  }

  json['source'] = '$scriptUri';
  json['script'] = {
    'type': '@Script',
    'fixedId': true,
    'id': 'libraries/1/scripts/${Uri.encodeComponent(scriptUri.toString())}',
    'uri': '$scriptUri',
    '_kind': 'library',
  };
  json['hits'] = flattenMap<int>(hits.lineHits);
  if (hits.funcHits != null) {
    json['funcHits'] = flattenMap<int>(hits.funcHits!);
  }
  if (hits.funcNames != null) {
    json['funcNames'] = flattenMap<dynamic>(hits.funcNames!);
  }
  return json;
}

/// Sorts the hits array based on the line numbers.
List _sortHits(List hits) {
  final structuredHits = <_HitInfo>[];
  for (var i = 0; i < hits.length - 1; i += 2) {
    final lineOrLineRange = hits[i];
    final firstLineInRange = lineOrLineRange is int
        ? lineOrLineRange
        : int.parse(lineOrLineRange.split('-')[0] as String);
    structuredHits.add(_HitInfo(firstLineInRange, hits[i], hits[i + 1] as int));
  }
  structuredHits.sort((a, b) => a.firstLine.compareTo(b.firstLine));
  return structuredHits
      .map((item) => [item.hitRange, item.hitCount])
      .expand((item) => item)
      .toList();
}
