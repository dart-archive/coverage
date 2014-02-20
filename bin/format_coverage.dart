// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:io";

import "package:args/args.dart";
import "package:path/path.dart" hide split;
import "package:coverage/coverage.dart";

main(List<String> arguments) {
  final env = parseArgs(arguments);

  List files = filesToProcess(env.input);

  List failedResolves = [];
  List failedLoads = [];
  Map globalHitmap = {};
  int start = new DateTime.now().millisecondsSinceEpoch;

  if (env.verbose) {
    print("Environment:");
    print("  # files: ${files.length}");
    print("  # workers: ${env.workers}");
    print("  sdk-root: ${env.sdkRoot}");
    print("  package-root: ${env.pkgRoot}");
  }

  Map sharedEnv = {
    "sdkRoot": env.sdkRoot,
    "pkgRoot": env.pkgRoot,
    "verbose": env.verbose,
  };

  // Create workers.
  int workerId = 0;
  var results = split(files, env.workers).map((workerFiles) {
    var result = spawnWorker("Worker ${workerId++}", sharedEnv, workerFiles);
    return result.then((ResultMessage message) {
      mergeHitmaps(message.hitmap, globalHitmap);
      failedResolves.addAll(message.failedResolves);
    });
  });

  Future.wait(results).then((ignore) {
    // All workers are done. Process the data.
    if (env.verbose) {
      final end = new DateTime.now().millisecondsSinceEpoch;
      print("Done creating a global hitmap. Took ${end - start} ms.");
    }

    Future out;
    if (env.prettyPrint) {
      out = prettyPrint(globalHitmap, failedLoads, env.output);
    }
    if (env.lcov) {
      out = lcov(globalHitmap, env.output);
    }

    out.then((_) {
      env.output.close().then((_) {
        if (env.verbose) {
          final end = new DateTime.now().millisecondsSinceEpoch;
          print("Done flushing output. Took ${end - start} ms.");
        }
      });

      if (env.verbose) {
        if (failedResolves.length > 0) {
          print("Failed to resolve:");
          failedResolves.toSet().forEach((e) {
            print("  ${e}");
          });
        }
        if (failedLoads.length > 0) {
          print("Failed to load:");
          failedLoads.toSet().forEach((e) {
            print("  ${e}");
          });
        }
      }
    });
  });
}

/// Checks the validity of the provided arguments. Does not initialize actual
/// processing.
parseArgs(List<String> arguments) {
  final env = new Environment();
  var parser = new ArgParser();

  parser.addOption("sdk-root", abbr: "s",
                   help: "path to the SDK root");
  parser.addOption("package-root", abbr: "p",
                   help: "path to the package root");
  parser.addOption("in", abbr: "i",
                   help: "input(s): may be file or directory");
  parser.addOption("out", abbr: "o",
                   help: "output: may be file or stdout",
                   defaultsTo: "stdout");
  parser.addOption("workers", abbr: "j",
                   help: "number of workers",
                   defaultsTo: "1");
  parser.addFlag("pretty-print", abbr: "r",
                 help: "convert coverage data to pretty print format",
                 negatable: false);
  parser.addFlag("lcov", abbr :"l",
                 help: "convert coverage data to lcov format",
                 negatable: false);
  parser.addFlag("verbose", abbr :"v",
                 help: "verbose output",
                 negatable: false);
  parser.addFlag("help", abbr: "h",
                 help: "show this help",
                 negatable: false);

  var args = parser.parse(arguments);

  printUsage() {
    print("Usage: dart format_coverage.dart [OPTION...]\n");
    print(parser.getUsage());
  }

  fail(String msg) {
    print("\n$msg\n");
    printUsage();
    exit(1);
  }

  if (args["help"]) {
    printUsage();
    exit(0);
  }

  env.sdkRoot = args["sdk-root"];
  if (env.sdkRoot == null) {
    if (Platform.environment.containsKey("DART_SDK")) {
      env.sdkRoot =
        join(absolute(normalize(Platform.environment["DART_SDK"])), "lib");
    }
  } else {
    env.sdkRoot = join(absolute(normalize(env.sdkRoot)), "lib");
  }
  if ((env.sdkRoot != null) && !FileSystemEntity.isDirectorySync(env.sdkRoot)) {
    fail("Provided SDK root '${args["sdk-root"]}' is not a valid SDK "
         "top-level directory");
  }

  env.pkgRoot = args["package-root"];
  if (env.pkgRoot != null) {
    env.pkgRoot = absolute(normalize(args["package-root"]));
    if (!FileSystemEntity.isDirectorySync(env.pkgRoot)) {
      fail("Provided package root '${args["package-root"]}' is not directory.");
    }
  }

  if (args["in"] == null) {
    fail("No input files given.");
  } else {
    env.input = absolute(normalize(args["in"]));
    if (!FileSystemEntity.isDirectorySync(env.input) &&
        !FileSystemEntity.isFileSync(env.input)) {
      fail("Provided input '${args["in"]}' is neither a directory, nor a file.");
    }
  }

  if (args["out"] == "stdout") {
    env.output = stdout;
  } else {
    env.output = absolute(normalize(args["out"]));
    env.output = new File(env.output).openWrite();
  }

  env.lcov = args["lcov"];
  if (args["pretty-print"] && env.lcov) {
    fail("Choose one of pretty-print or lcov output");
  } else if (!env.lcov) {
    // Use pretty-print either explicitly or by default.
    env.prettyPrint = true;
  }

  try {
    env.workers = int.parse("${args["workers"]}");
  } catch (e) {
    fail("Invalid worker count: $e");
  }

  env.verbose = args["verbose"];
  return env;
}
