// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'coverage_timeout_exception.dart';

/// Retries the specified function with the specified interval and returns
/// the result on successful completion.
Future retry(String timeoutOperation, Future retryFunction(), Duration interval,
    {Duration timeout}) async {
  var keepGoing = true;

  Future _withTimeout(Future f(), {Duration duration}) {
    if (duration == null) {
      return f();
    }

    return f().timeout(duration, onTimeout: () {
      keepGoing = false;

      throw newCoverageTimeoutException(timeoutOperation, duration);
    });
  }

  return _withTimeout(() async {
    while (keepGoing) {
      try {
        var result = await retryFunction();
        return result;
      } catch (_) {
        if (keepGoing) {
          await new Future.delayed(interval);
        }
      }
    }
  }, duration: timeout);
}

// TODO(kevmoo) will want an option for package spec (--packages=<path>) soon
Future<Process> runDartAppWithVMService(String scriptPath, int openPort,
    {String packageRoot, List<String> scriptArgs}) async {
  var dartArgs = ['--enable-vm-service=$openPort', '--pause_isolates_on_exit',];

  if (packageRoot != null) {
    dartArgs.add('--package-root=$packageRoot');
  }

  dartArgs.add(scriptPath);

  if (scriptArgs != null) {
    dartArgs.addAll(scriptArgs);
  }

  var processFuture = Process.start('dart', dartArgs);

  // TODO(kevmoo): figure out why this is needed
  // For some reason, connecting right away to the vm service just hangs
  // on my MacBook, this seems to be about 4x the minimum duration to
  // never hit this issue...
  await new Future.delayed(const Duration(milliseconds: 100));

  return await processFuture;
}

/// Returns an open port by creating a temporary Socket
Future<int> getOpenPort() async {
  ServerSocket socket;

  try {
    socket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V4, 0);
  } catch (_) {
    // try again v/ V6 only. Slight possibility that V4 is disabled
    socket = await ServerSocket.bind(InternetAddress.LOOPBACK_IP_V6, 0,
        v6Only: true);
  }

  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}
