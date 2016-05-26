import 'package:test/test.dart';

import 'collect_test.dart' as collect;
import 'lcov_formatter_test.dart' as lcov_formatter;
import 'run_and_collect_test.dart' as run_and_collect;
import 'util_test.dart' as util;

void main() {
  group('collect_coverage_api', collect.main);
  group('lcov_formatter', lcov_formatter.main);
  group('run_and_collect', run_and_collect.main);
  group('util', util.main);
}
