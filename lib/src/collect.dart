// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:vm_service_client/vm_service_client.dart';

import 'coverage_timeout_exception.dart';
import 'util.dart';

final _serviceOperationTimeout = new Duration(seconds: 5);

/// If [host] is not provided, `"localhost"` is used.
/// If [port] is not provided, `8181` is used.
///
/// If [waitPaused] is `true`, `collect` will wait until all thread have paused
/// before collecting coverage information.
///
/// If [waitPaused] is `true`, [timeout] is used to specify the maximum amount
/// of time to wait for all isolates to be paused. If no value is provided,
/// `collect` will wait forever.
///
/// Lines are 0-based!
Future<Map<Uri, Map<int, bool>>> collect(
    {String host,
    int port,
    bool resume: false,
    bool waitPaused: false,
    Duration timeout,
    bool includeSdkLibraries: false,
    bool libraryUriPredicate(Uri range)}) async {
  var uri = new Uri(
      scheme: 'ws', host: host ?? 'localhost', port: port ?? 8181, path: 'ws');

  var vmService = new VMServiceClient.connect(uri);

  VM vm;
  try {
    vm = await vmService.getVM().timeout(_serviceOperationTimeout,
        onTimeout: () {
      throw newCoverageTimeoutException(
          'get the VM object from the VM service', _serviceOperationTimeout);
    });

    try {
      if (waitPaused) {
        await _waitIsolatesPaused(vm, timeout: timeout);
      }

      var coverage = _getAllCoverage(
              vm, includeSdkLibraries, libraryUriPredicate ?? _includeAllFilter)
          .expand((range) => range);

      var result = await _mergeRanges(coverage);

      return result;
    } finally {
      if (resume) {
        await _resumeIsolates(vm);
      }
    }
  } finally {
    // only try to close the service cleanly if we've got the VM object
    // otherwise, we're likely stuck
    if (vm != null) {
      await vmService.close().timeout(_serviceOperationTimeout, onTimeout: () {
        throw newCoverageTimeoutException(
            'close the connection to the VM service', _serviceOperationTimeout);
      });
    }
  }
}

bool _includeAllFilter(Uri scriptUri) => true;

int _uriComparer(Uri a, Uri b) => a.toString().compareTo(b.toString());

Future<Map<Uri, Map<int, bool>>> _mergeRanges(
    Stream<VMSourceReportRange> ranges) async {
  var result = new SplayTreeMap<Uri, Map<int, bool>>(_uriComparer);

  await for (var range in ranges) {
    var fullScript = await range.script.load();

    var map = result.putIfAbsent(
        range.script.uri, () => new SplayTreeMap<int, bool>());

    if (range.hits != null) {
      for (var hit in range.hits) {
        var location = fullScript.sourceLocation(hit);
        map[location.line] = true;
      }
    }

    if (range.misses != null) {
      for (var miss in range.misses) {
        var location = fullScript.sourceLocation(miss);
        map.putIfAbsent(location.line, () => false);
      }
    }
  }

  return result;
}

Stream<List<VMSourceReportRange>> _getAllCoverage(VM vm,
    bool includeSdkLibraries, bool libraryUriPredicate(Uri range)) async* {
  for (var isolateRef in vm.isolates) {
    var scripts = await _getFilteredIsolateScripts(
        isolateRef, includeSdkLibraries, libraryUriPredicate);

    for (var script in scripts) {
      var report = await script.getSourceReport(
          includeCoverageReport: true, forceCompile: true);
      yield report.ranges;
    }
  }
}

Future<Set<VMScriptRef>> _getFilteredIsolateScripts(VMIsolateRef isolateRef,
    bool includeSdkLibraries, bool libraryUriPredicate(Uri range)) async {
  var vmIsolate = await isolateRef.loadRunnable();

  var scriptSet = new Set<VMScriptRef>();

  for (var libUri in vmIsolate.libraries.keys) {
    if (!includeSdkLibraries && libUri.scheme == 'dart') {
      continue;
    }

    if (!libraryUriPredicate(libUri)) continue;

    var libraryRef = vmIsolate.libraries[libUri];
    var library = await libraryRef.load();

    scriptSet.addAll(library.scripts);
  }

  return scriptSet;
}

Future _resumeIsolates(VM vm) async {
  for (var isolateRef in vm.isolates) {
    var isolate = await isolateRef.load();
    if (isolate.isPaused) {
      await isolateRef.resume();
    }
  }
}

Future _waitIsolatesPaused(VM vm, {Duration timeout}) async {
  Future allPaused() async {
    for (var isolateRef in vm.isolates) {
      var isolate = await isolateRef.load();
      if (!isolate.isPaused) throw "Unpaused isolates remaining.";
    }
  }
  return retry('pause isolates', allPaused, const Duration(milliseconds: 200),
      timeout: timeout);
}
