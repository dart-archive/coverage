// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'formatter.dart';
import 'resolver.dart';

/// Converts the given [hitMap] to a [Stream] containing lcov formatted outputs
/// for each file.
class LcovFormatter implements Formatter {
  final Resolver resolver;
  LcovFormatter(this.resolver);

  Stream<String> format(Map<Uri, Map<int, bool>> hitMap) async* {
    var buffer = new StringBuffer();
    for (var key in hitMap.keys) {
      buffer.clear();

      var fileLineCoverage = hitMap[key];
      var source = resolver.resolve(key);
      if (source == null) {
        continue;
      }

      buffer.writeln('SF:${source}');

      var executedLineCount = 0;
      fileLineCoverage.forEach((lineIndex, isExecuted) {
        var number = isExecuted ? '1' : '0';
        if (isExecuted) executedLineCount++;
        buffer.writeln('DA:${lineIndex + 1},${number}');
      });

      buffer.writeln('LH:$executedLineCount');
      buffer.writeln('LF:${fileLineCoverage.length}');
      buffer.write('end_of_record');

      yield buffer.toString();
    }
  }
}
