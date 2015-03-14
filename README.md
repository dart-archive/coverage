Coverage
========

Coverage provides coverage data collection, manipulation, and formatting for
Dart.

[![Build Status](https://travis-ci.org/dart-lang/coverage.svg?branch=master)](https://travis-ci.org/dart-lang/coverage)

Tools
-----
`collect_coverage.dart` collects coverage JSON from the Dart VM Observatory.
`format_coverage.dart` formats JSON coverage data into either
[LCOV](http://ltp.sourceforge.net/coverage/lcov.php) or pretty-printed format.

#### Install coverage

    pub global activate coverage
    
Consider adding the `pub global run` executables directory to your path. 
See [Running a script from your PATH](https://www.dartlang.org/tools/pub/cmd/pub-global.html#running-a-script-from-your-path)
for more details.    
    
#### Collecting coverage from the VM

    dart --observe=NNNN script.dart
    pub global run coverage:collect_coverage.dart --port=NNNN -o coverage.json --resume-isolates

or if the `pub global run` executables are in your path, just
    
    collect_coverage.dart --port=NNNN -o coverage.json --resume-isolates    
    
These previous two commands can also be combined to one 

    collect_coverage.dart --port=NNNN -o coverage.json --resume-isolates --script=script.dart
    
If `collect_coverage.dart` is invoked before the script from which coverage is
to be collected, it will wait until it detects a VM observatory port to which
it can connect. An optional `--connect-timeout` may be specified (in seconds).
The `--wait-paused` flag may be enabled, causing `collect_coverage.dart` to
wait until all isolates are paused before collecting coverage.

#### Collecting coverage from Dartium

    dartium --remote-debugging-port=NNNN
    # execute code in Dartium
    pub global run coverage:collect_coverage.dart --port=NNNN -o coverage.json

or if the `pub global run` executables are in your path, just

    collect_coverage.dart --port=NNNN -o coverage.json



As noted above, `collect_coverage.dart` may be invoked before Dartium, in which
case it will wait until it detects a Dartium remote debugging port, up to the
(optional) timeout. Note that coverage cannot be run against a Dartium instance
launched from Dart Editor, since the editor makes use of Dartium's remote
debugging port.

#### Formatting coverage data

    dart bin/format_coverage.dart --package-root=app_package_root -i coverage.json

where `app_package_root` is the package-root of the code whose coverage is being
collected. If `--sdk-root` is set, Dart SDK coverage will also be output.
