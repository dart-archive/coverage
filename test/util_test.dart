// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:coverage/src/coverage_timeout_exception.dart';
import 'package:coverage/src/util.dart';
import 'package:test/test.dart';

const _failCount = 5;
const _delay = const Duration(milliseconds: 10);

void main() {
  test('retry', () async {
    int count = 0;
    var stopwatch = new Stopwatch()..start();

    Future failCountTimes() async {
      expect(stopwatch.elapsed, greaterThanOrEqualTo(_delay * count));

      while (count < _failCount) {
        count++;
        throw 'not yet!';
      }
      return 42;
    }

    var value = await retry('op', failCountTimes, _delay);

    expect(value, 42);
    expect(count, _failCount);
    expect(stopwatch.elapsed, greaterThanOrEqualTo(_delay * count));
  });

  group('retry with timeout', () {
    test('if it finishes', () async {
      int count = 0;
      var stopwatch = new Stopwatch()..start();

      Future failCountTimes() async {
        expect(stopwatch.elapsed, greaterThanOrEqualTo(_delay * count));

        while (count < _failCount) {
          count++;
          throw 'not yet!';
        }
        return 42;
      }

      var safeTimoutDuration = _delay * _failCount * 2;
      var value = await retry('op', failCountTimes, _delay,
          timeout: safeTimoutDuration);

      expect(value, 42);
      expect(count, _failCount);
      expect(stopwatch.elapsed, greaterThanOrEqualTo(_delay * count));
    });

    test('if it does not finish', () async {
      int count = 0;
      var stopwatch = new Stopwatch()..start();

      var caught = false;
      var countAfterError = 0;

      Future failCountTimes() async {
        if (caught) {
          countAfterError++;
        }
        expect(stopwatch.elapsed, greaterThanOrEqualTo(_delay * count));

        count++;
        throw 'never';
      }

      var unsafeTimeoutDuration = _delay * (_failCount / 2);

      try {
        await retry('op', failCountTimes, _delay,
            timeout: unsafeTimeoutDuration);
      } on CoverageTimeoutException catch (e) {
        expect(e.duration, unsafeTimeoutDuration);
        caught = true;

        expect(countAfterError, 0,
            reason: 'Execution should stop after a timeout');

        await new Future.delayed(_delay * 3);

        expect(countAfterError, 0, reason: 'Even after a delay');
      }

      expect(caught, isTrue);
    });
  });
}
