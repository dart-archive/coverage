// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/command_runner.dart';

import '../coverage_timeout_exception.dart';
import 'collect_command.dart';
import 'exit_codes.dart' as codes;

main(List<String> args) async {
  var runner = new CommandRunner(
      'coverage', 'Collect code coverage information for a Dart program.')
    ..addCommand(new CollectCommand());

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = codes.usage;
  } on CoverageTimeoutException catch (e) {
    print(e);
    exitCode = codes.software;
  }
}
