// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage.test.collect_coverage_test;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:coverage/src/util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_util.dart';

final _isolateLibPath = p.join('test', 'test_files', 'test_app_isolate.dart');
final _collectAppPath = p.join('bin', 'collect_coverage.dart');

final _sampleAppFileUri = p.toUri(p.absolute(testAppPath)).toString();
final _isolateLibFileUri = p.toUri(p.absolute(_isolateLibPath)).toString();

void main() {
  test('collect_coverage', () async {
    var resultString = await _getCoverageResult();

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
      expect(sampleCoverageData['hits'], isNotNull);
    }

    for (var sampleCoverageData in sources[_isolateLibFileUri]) {
      expect(sampleCoverageData['hits'], isNotEmpty);
    }
  });

  test('createHitmap', () async {
    var resultString = await _getCoverageResult();

    var json = JSON.decode(resultString) as Map;

    var coverage = json['coverage'] as List<Map>;

    var hitMap = createHitmap(coverage);

    expect(hitMap, contains(_sampleAppFileUri));

    var isolateFile = hitMap[_isolateLibFileUri];

    expect(isolateFile, {12: 1, 14: 1, 16: 3, 18: 1});
  });

  test('parseCoverage', () async {
    var tempDir = await Directory.systemTemp.createTemp('coverage.test.');

    try {
      var outputFile = new File(p.join(tempDir.path, 'coverage.json'));

      var coverageResults = await _getCoverageResult();
      await outputFile.writeAsString(coverageResults, flush: true);

      var parsedResult = await parseCoverage([outputFile], 1);

      expect(parsedResult, contains(_sampleAppFileUri));
      expect(parsedResult, contains(_isolateLibFileUri));
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

String _coverageData;

Future<String> _getCoverageResult() async {
  if (_coverageData == null) {
    _coverageData = await _collectCoverage();
  }
  return _coverageData;
}

Future<String> _collectCoverage() async {
  expect(await FileSystemEntity.isFile(testAppPath), isTrue);

  var openPort = await getOpenPort();

  // run the sample app, with the right flags
  var sampleProcFuture = runTestApp(openPort);

  // run the tool with the right flags
  // TODO: need to get all of this functionality in the lib
  var toolResult = await Process.run('dart', [
    _collectAppPath,
    '--port',
    openPort.toString(),
    '--resume-isolates',
    '--wait-paused'
  ]).timeout(timeout, onTimeout: () {
    throw 'We timed out waiting for the tool to finish.';
  });

  if (toolResult.exitCode != 0) {
    print(toolResult.stdout);
    print(toolResult.stderr);
    fail('Tool failed with exit code ${toolResult.exitCode}.');
  }

  await sampleProcFuture;

  return toolResult.stdout;
}
