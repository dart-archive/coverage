// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'util.dart';

const _retryInterval = Duration(milliseconds: 200);

/// Collects coverage for all isolates in the running VM.
///
/// Collects a hit-map containing merged coverage for all isolates in the Dart
/// VM associated with the specified [serviceUri]. Returns a map suitable for
/// input to the coverage formatters that ship with this package.
///
/// [serviceUri] must specify the http/https URI of the service port of a
/// running Dart VM and must not be null.
///
/// If [resume] is true, all isolates will be resumed once coverage collection
/// is complete.
///
/// If [waitPaused] is true, collection will not begin until all isolates are
/// in the paused state.
///
/// If [onExit] is true, collection will be run for each isolate before its
/// exists. If [onExit] is true, the [waitPaused] parameter will be ignored.
Future<Map<String, dynamic>> collect(Uri serviceUri,
    {bool resume = false,
    bool waitPaused = false,
    bool onExit = false,
    bool includeDart = false,
    Duration timeout}) async {
  _CoverageCollector collector;
  if (onExit) {
    collector =
        _OnExitCollector(serviceUri, includeDart, resume, timeout: timeout);
  } else {
    collector = _OneTimeCollector(serviceUri, includeDart, waitPaused, resume,
        timeout: timeout);
  }

  return await collector.collect();
}

abstract class _CoverageCollector {
  _CoverageCollector(this.serviceUri, this.includeDart, {this.timeout}) {
    if (serviceUri == null) throw ArgumentError('serviceUri must not be null');
  }

  final List<Map<String, dynamic>> _collectedCoverage = [];

  final Duration timeout;
  final Uri serviceUri;
  final bool includeDart;

  VmService service;

  Future<VmService> connectToVMService() async {
    // Create websocket URI. Handle any trailing slashes.
    final pathSegments =
        serviceUri.pathSegments.where((c) => c.isNotEmpty).toList()..add('ws');
    final uri = serviceUri.replace(scheme: 'ws', pathSegments: pathSegments);

    return await retry(() async {
      try {
        final options = const CompressionOptions(enabled: false);
        final socket = await WebSocket.connect('$uri', compression: options);
        final controller = StreamController<String>();
        socket.listen((dynamic data) => controller.add(data));
        final service = VmService(
            controller.stream, (String message) => socket.add(message),
            log: StdoutLog(), disposeHandler: () => socket.close());
        await service.getVM().timeout(_retryInterval);

        return service;
      } on TimeoutException {
        service.dispose();
        rethrow;
      }
    }, _retryInterval, timeout: timeout);
  }

  Future prepare();
  Future collectCoverage();
  Future tearDown();

  Future<Map<String, dynamic>> collect() async {
    service = await connectToVMService();

    try {
      await prepare();
      await collectCoverage();
    } finally {
      await tearDown();
      service.dispose();
    }

    return <String, dynamic>{
      'type': 'CodeCoverage',
      'coverage': _collectedCoverage,
    };
  }

  Future<void> collectFromIsolate(IsolateRef isolateRef) async {
    final SourceReport report = await service.getSourceReport(
      isolateRef.id,
      <String>[SourceReportKind.kCoverage],
      forceCompile: true,
    );
    final coverage =
        await _getCoverageJson(service, isolateRef, report, includeDart);

    _collectedCoverage.addAll(coverage);
  }

  /// Resumes the [isolateRef], if its not in a resumed state.
  Future<void> resumeIsolate(IsolateRef isolateRef) async {
    final Isolate isolate = await service.getIsolate(isolateRef.id);
    if (isolate.pauseEvent.kind != EventKind.kResume) {
      await service.resume(isolateRef.id);
    }
  }
}

/// Collects coverage once, optionally waiting until all isolates have paused
/// and optionally resuming them afterwards.
class _OneTimeCollector extends _CoverageCollector {
  _OneTimeCollector(
      Uri serviceUri, bool includeDart, this.waitPaused, this.resume,
      {Duration timeout})
      : super(serviceUri, includeDart, timeout: timeout);

  final bool waitPaused;
  final bool resume;

  @override
  Future prepare() async {
    if (waitPaused) {
      return await _waitIsolatesPaused();
    }
  }

  Future<void> _waitIsolatesPaused() async {
    final pauseEvents = Set<String>.from(<String>[
      EventKind.kPauseStart,
      EventKind.kPauseException,
      EventKind.kPauseExit,
      EventKind.kPauseInterrupted,
      EventKind.kPauseBreakpoint
    ]);

    Future<void> allPaused() async {
      final VM vm = await service.getVM();
      for (var isolateRef in vm.isolates) {
        final Isolate isolate = await service.getIsolate(isolateRef.id);
        if (!pauseEvents.contains(isolate.pauseEvent.kind)) {
          throw "Unpaused isolates remaining.";
        }
      }
    }

    return retry(allPaused, _retryInterval, timeout: timeout);
  }

  @override
  Future collectCoverage() async {
    final vm = await service.getVM();

    for (var isolateRef in vm.isolates) {
      await collectFromIsolate(isolateRef);
    }
  }

  @override
  Future tearDown() async {
    if (resume) {
      final vm = await service.getVM();
      for (var isolateRef in vm.isolates) {
        await resumeIsolate(isolateRef);
      }
    }
  }
}

/// Collects coverage when isolates pause before exiting, optionally resuming
/// them afterwards.
class _OnExitCollector extends _CoverageCollector {
  _OnExitCollector(Uri serviceUri, bool includeDart, this.resume,
      {Duration timeout})
      : super(serviceUri, includeDart, timeout: timeout);

  final bool resume;
  final Completer<void> _allIsolatesExited = Completer();

  Map<IsolateRef, StreamSubscription> _exitSubscriptions = {};
  StreamSubscription _isolateStartSubscription;

  Completer<void> _currentCollection;

  @override
  Future prepare() async {
    // isolate start events are sent on kIsolate, exit events on kDebug
    await service.streamListen(EventStreams.kIsolate);
    await service.streamListen(EventStreams.kDebug);
  }

  @override
  Future collectCoverage() async {
    // Track all active isolates, also track isolates when they are started
    final vm = await service.getVM();
    var allIsolatesAlreadyPaused = true;

    // Collection could have started at a time in which all isolates have
    // already been paused before exiting. In that case, waiting for new
    // isolates to start will take forever.
    for (var isolateRef in vm.isolates) {
      final isolatePaused = await _trackIsolate(isolateRef);
      if (!isolatePaused) {
        allIsolatesAlreadyPaused = false;
      }
    }

    if (!allIsolatesAlreadyPaused) {
      final isolateStartStream = service.onIsolateEvent
          .where((e) => e.kind == EventKind.kIsolateStart)
          .map((e) => e.isolate);
      _isolateStartSubscription = isolateStartStream.listen(_trackIsolate);

      await _allIsolatesExited.future;
      await _isolateStartSubscription.cancel();
    }
  }

  // Tracks the isolate to collect coverage when it exists. Returns true if the
  // isolate is already exiting.
  Future<bool> _trackIsolate(IsolateRef isolateRef) async {
    // check if the isolate is already paused
    final Isolate isolate = await service.getIsolate(isolateRef.id);
    if (isolate.pauseEvent.kind == EventKind.kPauseExit) {
      await _collectAndResume(isolateRef);
      return true;
    } else {
      // collect coverage when the isolate is about to exit
      final exitEvent = service.onDebugEvent.where((e) {
        return e.kind == EventKind.kPauseExit && e.isolate == isolateRef;
      });
      _exitSubscriptions[isolateRef] = exitEvent.listen((_) {
        _collectFromExitingIsolate(isolateRef);
      });
      return false;
    }
  }

  Future _collectFromExitingIsolate(IsolateRef isolate) async {
    await _collectAndResume(isolate, cancelSubscription: true);

    if (_exitSubscriptions.isEmpty && !_allIsolatesExited.isCompleted) {
      _allIsolatesExited.complete(null);
    }
  }

  Future<void> _collectAndResume(IsolateRef isolate,
      {bool cancelSubscription = false}) async {
    // only collect from one isolate at a time
    while (_currentCollection != null && !_currentCollection.isCompleted) {
      await _currentCollection.future;
    }

    _currentCollection = Completer<void>();
    await collectFromIsolate(isolate);
    if (resume) {
      await resumeIsolate(isolate);
    }

    if (cancelSubscription) {
      await _exitSubscriptions.remove(isolate).cancel();
    }

    _currentCollection.complete();
  }

  @override
  Future tearDown() async {}
}

/// Returns the line number to which the specified token position maps.
///
/// Performs a binary search within the script's token position table to locate
/// the line in question.
int _getLineFromTokenPos(Script script, int tokenPos) {
  // TODO(cbracken): investigate whether caching this lookup results in
  // significant performance gains.
  var min = 0;
  var max = script.tokenPosTable.length;
  while (min < max) {
    final mid = min + ((max - min) >> 1);
    final row = script.tokenPosTable[mid];
    if (row[1] > tokenPos) {
      max = mid;
    } else {
      for (var i = 1; i < row.length; i += 2) {
        if (row[i] == tokenPos) return row.first;
      }
      min = mid + 1;
    }
  }
  return null;
}

/// Returns a JSON coverage list backward-compatible with pre-1.16.0 SDKs.
Future<List<Map<String, dynamic>>> _getCoverageJson(VmService service,
    IsolateRef isolateRef, SourceReport report, bool includeDart) async {
  // script uri -> { line -> hit count }
  final hitMaps = <Uri, Map<int, int>>{};
  final scripts = <ScriptRef, Script>{};
  for (var range in report.ranges) {
    final scriptRef = report.scripts[range.scriptIndex];
    final Uri scriptUri = Uri.parse(report.scripts[range.scriptIndex].uri);

    // Not returned in scripts section of source report.
    if (scriptUri.scheme == 'evaluate') continue;

    // Skip scripts from dart:.
    if (!includeDart && scriptUri.scheme == 'dart') continue;

    if (!scripts.containsKey(scriptRef)) {
      scripts[scriptRef] = await service.getObject(isolateRef.id, scriptRef.id);
    }
    final script = scripts[scriptRef];

    // Look up the hit map for this script (shared across isolates).
    final hitMap = hitMaps.putIfAbsent(scriptUri, () => <int, int>{});

    // Collect hits and misses.
    final coverage = range.coverage;

    if (coverage == null) continue;

    for (final tokenPos in coverage.hits) {
      final line = _getLineFromTokenPos(script, tokenPos);
      if (line == null) {
        print('tokenPos $tokenPos has no line mapping for script $scriptUri');
      }
      hitMap[line] = hitMap.containsKey(line) ? hitMap[line] + 1 : 1;
    }
    for (final tokenPos in coverage.misses) {
      final line = _getLineFromTokenPos(script, tokenPos);
      if (line == null) {
        print('tokenPos $tokenPos has no line mapping for script $scriptUri');
      }
      hitMap.putIfAbsent(line, () => 0);
    }
  }

  // Output JSON
  final coverage = <Map<String, dynamic>>[];
  hitMaps.forEach((uri, hitMap) {
    coverage.add(_toScriptCoverageJson(uri, hitMap));
  });
  return coverage;
}

/// Returns a JSON hit map backward-compatible with pre-1.16.0 SDKs.
Map<String, dynamic> _toScriptCoverageJson(
    Uri scriptUri, Map<int, int> hitMap) {
  final json = <String, dynamic>{};
  final hits = <int>[];
  hitMap.forEach((line, hitCount) {
    hits.add(line);
    hits.add(hitCount);
  });
  json['source'] = '$scriptUri';
  json['script'] = {
    'type': '@Script',
    'fixedId': true,
    'id': 'libraries/1/scripts/${Uri.encodeComponent(scriptUri.toString())}',
    'uri': '$scriptUri',
    '_kind': 'library',
  };
  json['hits'] = hits;
  return json;
}

class StdoutLog extends Log {
  @override
  void warning(String message) => print(message);
  @override
  void severe(String message) => print(message);
}
