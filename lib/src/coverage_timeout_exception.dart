// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

CoverageTimeoutException newCoverageTimeoutException(
        String operation, Duration duration) =>
    new CoverageTimeoutException._(operation, duration);

class CoverageTimeoutException implements Exception {
  final String operation;
  final Duration duration;

  CoverageTimeoutException._(this.operation, this.duration);

  @override
  String toString() {
    var durationString;

    if (duration.inSeconds == 0) {
      durationString = '${duration.inMilliseconds}ms';
    } else {
      durationString = '${duration.inSeconds}s';
    }

    return 'Failed to $operation within $durationString.';
  }
}
