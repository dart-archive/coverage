Coverage provides coverage data collection, manipulation, and formatting for
Dart.

[![Build Status](https://github.com/dart-lang/coverage/workflows/Dart%20CI/badge.svg)](https://github.com/dart-lang/coverage/actions?query=workflow%3A"Dart+CI"+branch%3Amaster)
[![Coverage Status](https://coveralls.io/repos/dart-lang/coverage/badge.svg?branch=master)](https://coveralls.io/r/dart-lang/coverage)
[![Pub](https://img.shields.io/pub/v/coverage.svg)](https://pub.dev/packages/coverage)


Tools
-----
`collect_coverage` collects coverage JSON from the Dart VM Observatory.
`format_coverage` formats JSON coverage data into either
[LCOV](http://ltp.sourceforge.net/coverage/lcov.php) or pretty-printed format.

#### Install coverage

    pub global activate coverage

Consider adding the `pub global run` executables directory to your path.
See [Running a script from your PATH](https://dart.dev/tools/pub/cmd/pub-global#running-a-script-from-your-path)
for more details.

#### Collecting coverage from the VM

```
dart --pause-isolates-on-exit --disable-service-auth-codes --enable-vm-service=NNNN script.dart
pub global run coverage:collect_coverage --uri=http://... -o coverage.json --resume-isolates
```

or if the `pub global run` executables are on your PATH,

```
collect_coverage --uri=http://... -o coverage.json --resume-isolates
```

where `--uri` specifies the Observatory URI emitted by the VM.

If `collect_coverage` is invoked before the script from which coverage is to be
collected, it will wait until it detects a VM observatory to which it can
connect. An optional `--connect-timeout` may be specified (in seconds).  The
`--wait-paused` flag may be enabled, causing `collect_coverage` to wait until
all isolates are paused before collecting coverage.

#### Formatting coverage data

```
pub global run coverage:format_coverage --packages=app_package/.packages -i coverage.json
```

or if the `pub global run` exectuables are on your PATH,

```
format_coverage --packages=app_package/.packages -i coverage.json
```

where `app_package` is the path to the package whose coverage is being
collected. If `--sdk-root` is set, Dart SDK coverage will also be output.

#### Ignore lines from coverage

- `// coverage:ignore-line` to ignore one line.
- `// coverage:ignore-start` and `// coverage:ignore-end` to ignore range of lines inclusive.
- `// coverage:ignore-file` to ignore the whole file.
