// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:coverage/coverage.dart';
import 'package:test/test.dart';

import 'test_util.dart';

void main() {
  group('collect', () {
    test('collects correctly', () async {
      var lineHits = await collectTestCoverage();

      validateTestAppCoverage(lineHits);
    });

    test("handles hang correctly", () async {
      var caught = false;
      try {
        await collectTestCoverage(
            neverExit: true, timeout: const Duration(seconds: 1));
      } on CoverageTimeoutException catch (e) {
        caught = true;
        expect(e.toString(), 'Failed to pause isolates within 1s.');
      }

      expect(caught, isTrue);
    });
  });
}
