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
  group('one time collection', () {
    _runTests(false);
  });

  group('on isolate exit', () {
    _runTests(true);
  });
}

void _runTests(bool onExit) {
  test('collect throws when serviceUri is null', () {
    expect(() => collect(null, onExit: onExit), throwsArgumentError);
  });

  test('collect_coverage_api', () async {
    final Map<String, dynamic> json = await _getCoverageResult(onExit);
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
}

Map _coverageData;
Map _onExitCoverageData;

Future<Map<String, dynamic>> _getCoverageResult(bool onExit) async {
  if (onExit) {
    return _onExitCoverageData ??= await _collectCoverage(true);
  } else {
    return _coverageData ??= await _collectCoverage(false);
  }
}

Future<Map<String, dynamic>> _collectCoverage(bool onExit) async {
  final openPort = await getOpenPort();

  // run the sample app, with the right flags
  final sampleProcess = await runTestApp(openPort);

  // Capture the VM service URI.
  final serviceUriCompleter = Completer<Uri>();
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
  });
  final Uri serviceUri = await serviceUriCompleter.future;

  return collect(serviceUri,
      resume: true,
      waitPaused: true,
      onExit: onExit,
      includeDart: false,
      timeout: timeout);
}
