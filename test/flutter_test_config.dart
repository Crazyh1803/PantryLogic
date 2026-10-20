import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';

/// Linux runtime packages may ship only the versioned SQLite library.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () {
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } on ArgumentError {
        return DynamicLibrary.open('libsqlite3.so.0');
      }
    });
  }
  await testMain();
}
