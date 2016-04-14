// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

import 'package:test/test.dart';

import 'package:coverage/coverage.dart';

import 'test_util.dart';

void main() {
  test('LcovFormatter', () async {
    var lineHits = await collectTestCoverage();

    var root = await Isolate.packageRoot;

    var resolver = new Resolver(packageRoot: root.toFilePath());

    var formatter = new LcovFormatter(resolver);

    var output = await formatter.format(lineHits).toList();

    expect(output, hasLength(4));

    // the output should be ordered as such

    var testAppContent = output[0];
    expect(testAppContent, contains('test_app.dart'));
    expect(testAppContent, endsWith(_test_app_dart));

    var testAppIsolateContent = output[1];
    expect(testAppIsolateContent, contains('test_app_isolate.dart'));
    expect(testAppIsolateContent, endsWith(_test_app_isolate_dart));

    var isolatePauseErrorContent = output[2];
    expect(
        isolatePauseErrorContent, contains('coverage_timeout_exception.dart'));

    var utilContent = output[3];
    expect(utilContent, contains('util.dart'));
  });
}

final _test_app_dart = '''DA:13,1
DA:14,1
DA:15,1
DA:16,1
DA:22,1
DA:25,0
DA:28,1
DA:31,1
DA:32,1
DA:33,1
DA:35,1
DA:37,1
DA:41,1
DA:42,1
DA:43,1
DA:44,1
DA:47,1
DA:51,0
LH:16
LF:18
end_of_record''';

final _test_app_isolate_dart = '''DA:12,1
DA:14,1
DA:16,1
DA:18,1
LH:4
LF:4
end_of_record''';
