// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../collect.dart';
import '../lcov_formatter.dart';
import '../resolver.dart';

class CollectCommand extends Command {
  @override
  String get name => 'collect';

  @override
  String get description =>
      'Collect coverage information from a running process';

  CollectCommand() {
    argParser
      ..addOption('host',
          abbr: 'H', defaultsTo: 'localhost', help: 'remote VM host')
      ..addOption('port', abbr: 'p', help: 'remote VM port', defaultsTo: '8181')
      // TODO(kevmoo): Natalie has a package for parsing time formats
      //               might be good here
      ..addOption('pause-timeout',
          abbr: 't',
          help: 'Seconds to wait for all isolates to pause.\n'
              'Use `0` to wait forever.',
          defaultsTo: '5')
      ..addFlag('wait-paused',
          abbr: 'w',
          defaultsTo: false,
          help: 'wait for all isolates to be paused before collecting coverage')
      ..addFlag('resume-isolates',
          abbr: 'r', defaultsTo: false, help: 'resume all isolates on exit')
      ..addOption('output',
          abbr: 'o',
          help: 'A path to the file to write the coverage information.\n'
              'If not provided (the default) coverage is written the console.');
  }

  /// May return `null` if a 'packages' directory doesn't exist in the current
  /// working directory.
  String _getPackageRoot() {
    // TODO(kevmoo): consider adding an option for this
    var currentDirPath = Directory.current.path;

    var likelyPackageDir = p.join(currentDirPath, 'packages');

    var packageDir = new Directory(likelyPackageDir);

    if (packageDir.existsSync()) {
      return packageDir.path;
    }

    return null;
  }

  @override
  Future run() async {
    var pauseWaitTimeoutSeconds = int.parse(argResults['pause-timeout']);

    Duration pauseWaitTimeout;
    if (pauseWaitTimeoutSeconds > 0) {
      pauseWaitTimeout = new Duration(seconds: pauseWaitTimeoutSeconds);
    }

    var outputFile = argResults['output'];

    IOSink sink;
    if (outputFile == null) {
      sink = stdout;
    } else {
      sink = new File(outputFile).openWrite();
    }

    var results = await collect(
        host: argResults['host'],
        port: int.parse(argResults['port']),
        waitPaused: argResults['wait-paused'] as bool,
        timeout: pauseWaitTimeout,
        resume: argResults['resume-isolates'] as bool);

    var resolver = new Resolver(packageRoot: _getPackageRoot());

    var formatter = new LcovFormatter(resolver);

    await for (var item in formatter.format(results)) {
      sink.writeln(item);
    }

    await sink.flush();
    await sink.close();
  }
}
