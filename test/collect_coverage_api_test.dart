// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:coverage/coverage.dart';
import 'package:coverage/src/util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_util.dart';

final _isolateLibPath = p.join('test', 'test_files', 'test_app_isolate.dart');

final _sampleAppFileUri = p.toUri(p.absolute(testAppPath)).toString();
final _isolateLibFileUri = p.toUri(p.absolute(_isolateLibPath)).toString();

void main() {
  test('collect throws when serviceUri is null', () {
    expect(() => collect(null, true, false, false, Set<String>()),
        throwsArgumentError);
  });

  test('collect_coverage_api', () async {
    final Map<String, dynamic> json = await _collectCoverage();
    expect(json.keys, unorderedEquals(<String>['type', 'coverage']));
    expect(json, containsPair('type', 'CodeCoverage'));

    final List coverage = json['coverage'];
    expect(coverage, isNotEmpty);

    final sources = coverage.fold(<String, dynamic>{},
        (Map<String, dynamic> map, dynamic value) {
      final String sourceUri = value['source'];
      map.putIfAbsent(sourceUri, () => <Map>[]).add(value);
      return map;
    });

    for (Map sampleCoverageData in sources[_sampleAppFileUri]) {
      expect(sampleCoverageData['hits'], isNotNull);
    }

    for (var sampleCoverageData in sources[_isolateLibFileUri]) {
      expect(sampleCoverageData['hits'], isNotEmpty);
    }
  });

  test('collect_coverage_api with scoped output', () async {
    final Map<String, dynamic> json =
        await _collectCoverage(scopedOutput: Set<String>()..add('coverage'));
    expect(json.keys, unorderedEquals(<String>['type', 'coverage']));
    expect(json, containsPair('type', 'CodeCoverage'));

    final List coverage = json['coverage'];
    expect(coverage, isNotEmpty);

    final sources = coverage.fold(<String, dynamic>{},
        (Map<String, dynamic> map, dynamic value) {
      final String sourceUri = value['source'];
      map.putIfAbsent(sourceUri, () => <Map>[]).add(value);
      return map;
    });

    for (var key in sources.keys) {
      final uri = Uri.parse(key);
      expect(uri.path.startsWith('coverage'), isTrue);
    }
  });

  test('collect_coverage_api with isolateIds', () async {
    final Map<String, dynamic> json = await _collectCoverage(isolateIds: true);
    expect(json.keys, unorderedEquals(<String>['type', 'coverage']));
    expect(json, containsPair('type', 'CodeCoverage'));

    final List coverage = json['coverage'];
    expect(coverage, isNotEmpty);

    final Map<String, dynamic> testAppCoverage = coverage[0];
    List<int> hits = testAppCoverage['hits'];

    _expectPairs(hits, [
      [44, 0],
      [48, 0]
    ]);

    final Map<String, dynamic> isolateCoverage = coverage[2];
    hits = isolateCoverage['hits'];
    _expectPairs(hits, [
      [9, 1],
      [16, 1]
    ]);
  });
}

Future<Map<String, dynamic>> _collectCoverage(
    {Set<String> scopedOutput, bool isolateIds = false}) async {
  scopedOutput ??= Set<String>();
  final openPort = await getOpenPort();

  // run the sample app, with the right flags
  final sampleProcess = await runTestApp(openPort);

  // Capture the VM service URI.
  final serviceUriCompleter = Completer<Uri>();
  final isolateIdCompleter = Completer<String>();
  sampleProcess.stdout
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
    if (!serviceUriCompleter.isCompleted) {
      final Uri serviceUri = extractObservatoryUri(line);
      if (serviceUri != null) {
        serviceUriCompleter.complete(serviceUri);
      }
    }
    if (line.contains('isolateId = ')) {
      isolateIdCompleter.complete(line.split(' = ')[1]);
    }
  });

  final Uri serviceUri = await serviceUriCompleter.future;
  final String isolateId = await isolateIdCompleter.future;
  final Set<String> isolateIdSet =
      isolateIds ? Set.from(<String>[isolateId]) : null;

  return collect(serviceUri, true, true, false, scopedOutput,
      timeout: timeout, isolateIds: isolateIdSet);
}

/// Helper function for matching hit pairs to a hitmap
/// [hits] is the hitmap returned by the collect function
/// [pairs] is a List of 2 value pairs in form [line, hit count]
void _expectPairs(List<int> hits, List<List<int>> pairs) {
  for (final pair in pairs) {
    final int hitIndex = hits.indexOf(pair[0]);
    expect(hits[hitIndex + 1], equals(pair[1]),
        reason: 'Expected line ${pair[0]} to have ${pair[1]} hits');
  }
}
