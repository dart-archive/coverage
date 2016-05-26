// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'collect.dart';
import 'coverage_timeout_exception.dart';
import 'util.dart';

// TODO(kevmoo) will want an option for package spec (--packages=<path>) soon
Future<Map<Uri, Map<int, bool>>> runAndCollect(String scriptPath,
    {List<String> scriptArgs, String packageRoot, Duration timeout}) async {
  var openPort = await getOpenPort();

  var process = await runDartAppWithVMService(scriptPath, openPort,
      packageRoot: packageRoot, scriptArgs: scriptArgs);

  try {
    var result = await Future.wait([
      collect(port: openPort, waitPaused: true, resume: true, timeout: timeout),
      _drainProcess(process)
    ], eagerError: true);

    return result[0] as Map<Uri, Map<int, bool>>;
  } on CoverageTimeoutException {
    // TODO(kevmoo): option for different signal on isolate pause timeout
    process.kill(ProcessSignal.SIGKILL);
    rethrow;
  }
}

/// Utility function as a place-holder for TODOs to handle non-zero exit codes.
Future _drainProcess(Process proc) async {
  // TODO(kevmoo): we may want options to fail on non-zero exit code
  // TODO(kevmoo): we may want options to include stdout/stderr data on failure
  await Future.wait([proc.exitCode, proc.stdout.drain(), proc.stderr.drain()]);
}
