// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage.test.collect_coverage_test;

import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_util.dart';

final _isolateLibPath = p.join('test', 'test_files', 'test_app_isolate.dart');

final _sampleAppFileUri = p.toUri(p.absolute(testAppPath)).toString();
final _isolateLibFileUri = p.toUri(p.absolute(_isolateLibPath)).toString();

void main() {
  test('collect_coverage', () async {
    var resultString = await getCoverageResult();

    // analyze the output json
    var json = JSON.decode(resultString) as Map;

    expect(json.keys, unorderedEquals(['type', 'coverage']));

    expect(json, containsPair('type', 'CodeCoverage'));

    var coverage = json['coverage'] as List;
    expect(coverage, isNotEmpty);

    var sources = coverage.fold(<String, dynamic>{}, (Map map, Map value) {
      var sourceUri = value['source'];

      map.putIfAbsent(sourceUri, () => <Map>[]).add(value);

      return map;
    });

    for (var sampleCoverageData in sources[_sampleAppFileUri]) {
      expect(sampleCoverageData['hits'], isNotEmpty);
    }

    for (var sampleCoverageData in sources[_isolateLibFileUri]) {
      expect(sampleCoverageData['hits'], isNotEmpty);
    }
  });

  test('createHitmap', () async {
    var resultString = await getCoverageResult();

    var json = JSON.decode(resultString) as Map;

    var coverage = json['coverage'] as List;

    var hitMap = createHitmap(coverage);

    expect(hitMap, contains(_sampleAppFileUri));

    var isolateFile = hitMap[_isolateLibFileUri];

    expect(isolateFile, {11: 1, 12: 1, 14: 1, 16: 3, 18: 1});
  });

  test('parseCoverage', () async {
    var tempDir = await Directory.systemTemp.createTemp('coverage.test.');

    var outputFile = new File(p.join(tempDir.path, 'coverage.json'));

    var coverageResults = await getCoverageResult();
    await outputFile.writeAsString(coverageResults, flush: true);

    var parsedResult = await parseCoverage([outputFile], 1);

    expect(parsedResult, contains(_sampleAppFileUri));
    expect(parsedResult, contains(_isolateLibFileUri));
  });
}
