// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:benchmark_harness/benchmark_harness.dart';

import '../bin/collect_coverage.dart' as collect_coverage;
import '../bin/format_coverage.dart' as format_coverage;

// Runs a test script with various different coverage configurations.
class CoverageBenchmark extends AsyncBenchmarkBase {
  CoverageBenchmark(
    ScoreEmitter emitter,
    String name,
    this.script, {
    this.gatherCoverage = false,
    this.functionCoverage = false,
    this.branchCoverage = false,
  }) : super(name, emitter: emitter);

  final String script;
  final bool gatherCoverage;
  final bool functionCoverage;
  final bool branchCoverage;
  int iteration = 0;

  @override
  Future<void> run() async {
    final covFile = 'data/$name $iteration coverage.json';
    final lcovFile = 'data/$name $iteration lcov.info';
    ++iteration;

    final scriptProcess = await Process.start(
      Platform.executable,
      [
        if (branchCoverage) '--branch-coverage',
        'run',
        if (gatherCoverage) ...[
          '--pause-isolates-on-exit',
          '--disable-service-auth-codes',
          '--enable-vm-service=1234',
        ],
        script,
      ],
      mode: ProcessStartMode.detached,
    );
    if (gatherCoverage) {
      await collect_coverage.main([
        '--wait-paused',
        '--resume-isolates',
        '--uri=http://127.0.0.1:1234/',
        if (branchCoverage) '--branch-coverage',
        if (functionCoverage) '--function-coverage',
        '-o',
        covFile,
      ]);

      await format_coverage.main([
        '--lcov',
        '--check-ignore',
        '-i',
        covFile,
        '-o',
        lcovFile,
      ]);
    }
    await scriptProcess.exitCode;
  }
}

// Prints a JSON representation of the benchmark results, in a format compatible
// with the github benchmark action.
class JsonEmitter implements ScoreEmitter {
  final _entries = <String>[];

  @override
  void emit(String testName, double value) {
    _entries.add("""{
  "name": "$testName",
  "unit": "us",
  "value": ${value.toInt()}
}""");
  }

  String write() => '[${_entries.join(',\n')}]';
}

Future<void> runBenchmarkSet(
    ScoreEmitter emitter, String name, String script) async {
  await CoverageBenchmark(emitter, '$name - no coverage', script).report();
  await CoverageBenchmark(emitter, '$name - basic coverage', script,
          gatherCoverage: true)
      .report();
  await CoverageBenchmark(emitter, '$name - function coverage', script,
          gatherCoverage: true, functionCoverage: true)
      .report();
  await CoverageBenchmark(emitter, '$name - branch coverage', script,
          gatherCoverage: true, branchCoverage: true)
      .report();
}

Future<void> main() async {
  // Assume this script was started from the root coverage directory. Change to
  // the benchmark directory.
  Directory.current = 'benchmark';
  final emitter = JsonEmitter();
  await runBenchmarkSet(emitter, 'Many isolates', 'many_isolates.dart');
  File('data/benchmark_result.json').writeAsString(emitter.write());
}
