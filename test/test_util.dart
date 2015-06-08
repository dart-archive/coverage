// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library coverage.test.util;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final testAppPath = p.join('test', 'test_files', 'test_app.dart');

const _timeout = const Duration(seconds: 5);

String _coverageData;

Future<String> getCoverageResult() async {
  if (_coverageData == null) {
    _coverageData = await _collectCoverage();
  }
  return _coverageData;
}

Future<String> _collectCoverage() async {
  expect(await FileSystemEntity.isFile(testAppPath), isTrue);

  // need to find an open port
  var socket = await ServerSocket.bind(InternetAddress.ANY_IP_V4, 0);
  int openPort = socket.port;
  await socket.close();

  // run the sample app, with the right flags
  var sampleProcFuture = Process
      .run('dart', [
    '--enable-vm-service=$openPort',
    '--pause_isolates_on_exit',
    testAppPath
  ])
      .timeout(_timeout, onTimeout: () {
    throw 'We timed out waiting for the sample app to finish.';
  });

  var collectionResultFuture =
      collect('127.0.0.1', openPort, true, true, timeout: _timeout);

  await sampleProcFuture;

  return JSON.encode(await collectionResultFuture);
}
