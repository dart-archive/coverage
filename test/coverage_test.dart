/// Unit tests for markdown.
library coverageTests;

import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:mock/mock.dart';
import 'package:unittest/unittest.dart';

void testParseCoverage() {
  File fooFile, barFile, bazFile, quxFile, corgeFile;

  setUp(() {
    fooFile = mockFileFixture('foo', [1, 10]);
    barFile = mockFileFixture('bar', [2, 12]);
    bazFile = mockFileFixture('baz', [4, 7]);
    quxFile = mockFileFixture('qux', [10, 100]);
    corgeFile = mockFileFixture('corge', [17, 49]);
  });

  test('parseCoverage', () {
    // Zero workers.
    parseCoverage([fooFile], 0).then(
      expectCorrectHitmap([fooFile], {'src/foo.dart': {1: 10}}));

    // null workers.
    parseCoverage([fooFile], null).then(
      expectCorrectHitmap([fooFile], {'src/foo.dart': {1: 10}}));

    // Single file; one worker.
    parseCoverage([fooFile], 1).then(
      expectCorrectHitmap([fooFile], {'src/foo.dart': {1: 10}}));

    // Single file; two workers.
    parseCoverage([fooFile], 2).then(
      expectCorrectHitmap([fooFile], {'src/foo.dart': {1: 10}}));

    // Two files; one worker.
    parseCoverage([fooFile, barFile], 1).then(
      expectCorrectHitmap(
        [fooFile, barFile],
        {'src/foo.dart': {1: 10}, 'src/bar.dart': {2: 12}}));

    // workers divides files.length
    parseCoverage([fooFile, barFile, bazFile, quxFile], 2).then(
      expectCorrectHitmap(
        [fooFile, barFile, bazFile, quxFile], {
          'src/foo.dart': {1: 10},
          'src/bar.dart': {2: 12},
          'src/baz.dart': {4: 7},
          'src/qux.dart': {10: 100}}));

    // files.length % workers == 1
    parseCoverage([fooFile, barFile, bazFile, quxFile, corgeFile], 4).then(
      expectCorrectHitmap(
        [fooFile, barFile, bazFile, quxFile], {
          'src/foo.dart': {1: 10},
          'src/bar.dart': {2: 12},
          'src/baz.dart': {4: 7},
          'src/qux.dart': {10: 100},
          'src/corge.dart': {17: 49}}));

    // files.length % workers == -1
    parseCoverage([fooFile, barFile, bazFile, quxFile, corgeFile], 3).then(
      expectCorrectHitmap(
        [fooFile, barFile, bazFile, quxFile], {
          'src/foo.dart': {1: 10},
          'src/bar.dart': {2: 12},
          'src/baz.dart': {4: 7},
          'src/qux.dart': {10: 100},
          'src/corge.dart': {17: 49}}));
  });
}

void main() {
  test('createHitmap', () {
    // Single file.
    expect(createHitmap(coverageArray({'foo': [1, 10]})),
      equals({'src/foo.dart': {1: 10}}));

    // Single file with multiple entires.
    expect(createHitmap(coverageArray({'foo': [1, 10, 2, 15]})),
      equals({'src/foo.dart': {1: 10, 2: 15}}));

    // Single file with multiple entries for the same line.
    expect(createHitmap(coverageArray({'foo': [5, 13, 5, 7]})),
      equals({'src/foo.dart': {5: 20}}));

    // Multiple files.
    expect(createHitmap(coverageArray({'foo': [2, 10], 'bar': [2, 30]})),
      equals({'src/foo.dart': {2: 10}, 'src/bar.dart': {2: 30}}));
  });

  test('mergeHitmaps', () {
    // Mutually exclusive files.
    Map existing = {'src/foo.dart': {2: 5, 3: 25}};
    Map newMap = {'src/bar.dart': {2: 10, 3: 20}};
    mergeHitmaps(newMap, existing);
    expect(existing, equals(
      {'src/foo.dart': {2: 5, 3: 25}, 'src/bar.dart': {2: 10, 3: 20}}));

    // Same files and line numbers.
    existing = {'src/foo.dart': {2: 5, 3: 25}};
    newMap = {'src/foo.dart': {2: 10, 3: 20}};
    mergeHitmaps(newMap, existing);
    expect(existing, equals(
      {'src/foo.dart': {2: 15, 3: 45}}));

    // Same files; existing overlaps newMap.
    existing = {'src/foo.dart': {2: 5, 5: 25}};
    newMap = {'src/foo.dart': {2: 10, 3: 20}};
    mergeHitmaps(newMap, existing);
    expect(existing, equals(
      {'src/foo.dart': {2: 15, 3: 20, 5: 25}}));

    // Same files; mutually exclusive line numbers.
    existing = {'src/foo.dart': {2: 5, 3: 25}};
    newMap = {'src/foo.dart': {5: 10, 7: 20}};
    mergeHitmaps(newMap, existing);
    expect(existing, equals(
      {'src/foo.dart': {2: 5, 3: 25, 5: 10, 7: 20}}));
  });

  testParseCoverage();
}

class MockFile extends Mock implements File {}

coverageArray(Map<String, List<int>> fileHits) {
  var fileJsons = [];
  fileHits.forEach((baseName, hits) {
    fileJsons.add(singleFile(baseName, hits));
  });
  return fileJsons;
}

expectCorrectHitmap(List<File> files, Map expected) {
  return expectAsync((Map actual) {
    // We should verify that [readAsStringSync] is called once on each File.
    // However, since const objects are not shared across isolates
    // (https://code.google.com/p/dart/issues/detail?id=9349), mocking doesn't
    // work across isolates either (Action.RETURN from main isolate !==
    // Action.RETURN from the new isolate spawned in _spawnWorker).
    //
    //files.forEach((File fileEntry) {
    //  fileEntry.getLogs(callsTo('readAsStringSync')).verify(happenedOnce);
    //});
    expect(actual, equals(expected));
  });
}

jsonFile(Map<String, List<int>> fileHits) {
  return JSON.encode({
    'type': 'CodeCoverage',
    'coverage': coverageArray(fileHits),
  });
}

mockFileFixture(String name, List<int> hits) {
  File mockFile = new MockFile();
  mockFile.when(callsTo('readAsStringSync')).alwaysReturn(jsonFile({name: hits}));
  return mockFile;
}

singleFile(baseName, hits) {
  return {'source': 'src/${baseName}.dart', 'hits': hits};
}
