// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:convert' show utf8, LineSplitter;

import 'package:args/args.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as path;
import 'package:coverage/src/util.dart' show extractVMServiceUri;

Future<void> dartRun(List<String> args,
    {Function(String)? onStdout, String? workingDir}) async {
  final process = await Process.start(
    Platform.executable,
    args,
    workingDirectory: workingDir,
  );
  final broadStdout = process.stdout.asBroadcastStream();
  broadStdout.listen(stdout.add);
  broadStdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(onStdout);
  process.stderr.listen(stderr.add);
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException(Platform.executable, args, '', result);
  }
}

Future<String?> getPackageName(String packageDir) async {
  final config = await findPackageConfig(Directory(packageDir));
  return config?.packageOf(Uri.directory(packageDir))?.name;
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser();
  parser.addOption(
    'package',
    help: 'Root directory of the package to test.',
    defaultsTo: '.',
  );
  parser.addOption(
    'package-name',
    help: 'Name of the package to test. '
        'Deduced from --package if not provided.',
  );
  parser.addOption('port', help: 'VM service port.', defaultsTo: '8181');
  parser.addOption('out',
      abbr: 'o', help: 'Output directory. Defaults to <package-dir>/coverage.');
  parser.addOption('test', help: 'Test script to run.', defaultsTo: 'test');
  parser.addFlag(
    'function-coverage',
    abbr: 'f',
    defaultsTo: false,
    help: 'Collect function coverage info.',
  );
  parser.addFlag(
    'branch-coverage',
    abbr: 'b',
    defaultsTo: false,
    help: 'Collect branch coverage info.',
  );
  parser.addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final args = parser.parse(arguments);

  void printUsage() {
    print('Runs tests and collects coverage for a package. By default this '
      "script assumes it's being run from the root directory of a package, and "
      'outputs a coverage.json and lcov.info to ./coverage/');
    print('Usage: dart test_with_coverage.dart [OPTIONS...]\n');
    print(parser.usage);
  }

  Never fail(String msg) {
    print('\n$msg\n');
    printUsage();
    exit(1);
  }

  if (args['help'] as bool) {
    printUsage();
    exit(0);
  }

  final packageDir = path.canonicalize(args['package'] as String);
  if (!await FileSystemEntity.isDirectory(packageDir)) {
    fail('--package is not a valid directory.');
  }

  final packageName =
      (args['package-name'] as String?) ?? await getPackageName(packageDir);
  if (packageName == null) {
    fail(
      "Couldn't figure out package name from --package. "
      'Try passing --package-name explicitly.',
    );
  }

  final outDir = (args['out'] as String?) ?? path.join(packageDir, 'coverage');
  if (!await FileSystemEntity.isDirectory(outDir)) {
    await Directory(outDir).create(recursive: true);
  }

  final port = args['port'] as String;
  final testScript = args['test'] as String;
  final functionCoverage = args['function-coverage'] as bool;
  final branchCoverage = args['branch-coverage'] as bool;
  final thisDir = path.dirname(Platform.script.path);
  final outJson = path.join(outDir, 'coverage.json');
  final outLcov = path.join(outDir, 'lcov.info');

  final serviceUriCompleter = Completer<Uri>();
  final testProcess = dartRun([
    if (branchCoverage) '--branch-coverage',
    'run',
    '--pause-isolates-on-exit',
    '--disable-service-auth-codes',
    '--enable-vm-service=$port',
    testScript,
  ], onStdout: (line) {
    if (!serviceUriCompleter.isCompleted) {
      final uri = extractVMServiceUri(line);
      if (uri != null) {
        serviceUriCompleter.complete(uri);
        print('\n');
      }
    }
  });
  final serviceUri = await serviceUriCompleter.future;

  await dartRun([
    'run',
    'collect_coverage.dart',
    '--wait-paused',
    '--resume-isolates',
    '--connect-timeout=30',
    '--uri=$serviceUri',
    '--scope-output=$packageName',
    if (branchCoverage) '--branch-coverage',
    if (functionCoverage) '--function-coverage',
    '-o',
    outJson,
  ], workingDir: thisDir);
  await testProcess;

  await dartRun([
    'run',
    'format_coverage.dart',
    '--lcov',
    '--check-ignore',
    '--package=$packageDir',
    '-i',
    outJson,
    '-o',
    outLcov,
  ], workingDir: thisDir);
}
