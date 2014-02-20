// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library harness_console;

import 'package:unittest/unittest.dart';
import 'package:unittest/vm_config.dart';
import "package:coverage/coverage.dart";

void main() {
  testCore(new VMConfiguration());
}

void testCore(Configuration config) {
  unittestConfiguration = config;
  groupSep = ' - ';

  group('Resolver', () {
    test('fail to resolve', () {
      Resolver resolver = new Resolver({});
      String absPath = resolver.resolve("doesnotexist");
      expect(absPath, isNull);
    });
  });
}
