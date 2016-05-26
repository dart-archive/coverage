// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:coverage/src/collect.dart';
import 'package:coverage/src/util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final testAppPath = p.join('test', 'test_files', 'test_app.dart');

final _isolateLibPath = p.join('test', 'test_files', 'test_app_isolate.dart');

final _sampleAppFileUri = p.toUri(p.absolute(testAppPath));
final _isolateLibFileUri = p.toUri(p.absolute(_isolateLibPath));

Future<Map<Uri, Map<int, bool>>> collectTestCoverage(
    {bool neverExit: false, Duration timeout}) async {
  var openPort = await getOpenPort();

  List<String> args;

  if (neverExit) {
    args = ['never-exit'];
  }
  var proc =
      await runDartAppWithVMService(testAppPath, openPort, scriptArgs: args);

  try {
    return await collect(
        port: openPort, resume: true, waitPaused: true, timeout: timeout);
  } finally {
    proc.kill(ProcessSignal.SIGKILL);
  }
}

void validateTestAppCoverage(Map lineHits) {
  expect(lineHits, hasLength(4));

  expect(lineHits, contains(Uri.parse('package:coverage/src/util.dart')));

  var sampleAppFileHits = lineHits[_sampleAppFileUri];
  expect(sampleAppFileHits, {
    12: true,
    13: true,
    14: true,
    15: true,
    21: true,
    24: false,
    27: true,
    30: true,
    31: true,
    32: true,
    34: true,
    36: true,
    40: true,
    41: true,
    42: true,
    43: true,
    46: true,
    50: false
  });

  var sampleIsolateHits = lineHits[_isolateLibFileUri];
  expect(sampleIsolateHits, {11: true, 13: true, 15: true, 17: true});
}
