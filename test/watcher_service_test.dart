import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otp_watcher/otp_entry.dart';
import 'package:otp_watcher/watcher_service.dart';

void main() {
  late Directory tmp;
  late WatcherService watcher;
  late List<OtpEntry> entries;
  late List<String> errors;
  late int stoppedCount;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otp_watcher_test');
    watcher = WatcherService(pollInterval: const Duration(milliseconds: 20));
    entries = [];
    errors = [];
    stoppedCount = 0;
  });

  tearDown(() {
    watcher.stop();
    tmp.deleteSync(recursive: true);
  });

  File makeFile(String name, [String content = '']) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(content);
    return f;
  }

  // Appends and bumps mtime so the change is detected even on filesystems
  // with coarse timestamp resolution.
  var tick = 0;
  void append(File f, String text) {
    f.writeAsStringSync(text, mode: FileMode.append);
    f.setLastModifiedSync(
      DateTime.now().add(Duration(seconds: ++tick)),
    );
  }

  void start(List<String> paths, {String pattern = 'Your OTP is'}) {
    watcher.start(
      filePaths: paths,
      searchPattern: pattern,
      onOtpDetected: entries.add,
      onError: errors.add,
      onStopped: () => stoppedCount++,
    );
  }

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 150));

  group('single file', () {
    test('detects an OTP appended after start', () async {
      final f = makeFile('a.log');
      start([f.path]);

      append(f, 'Your OTP is 482193. It expires in 5 minutes.\n');
      await pump();

      expect(entries, hasLength(1));
      expect(entries.single.otp, '482193');
      expect(entries.single.sourcePath, f.path);
      expect(watcher.isRunning, isTrue);
    });

    test('ignores lines already present when watching starts', () async {
      final f = makeFile('a.log', 'Your OTP is 111111\n');
      start([f.path]);
      await pump();

      expect(entries, isEmpty);
    });

    test('matches pattern case-insensitively', () async {
      final f = makeFile('a.log');
      start([f.path]);

      append(f, 'YOUR otp IS 123456\n');
      await pump();

      expect(entries.single.otp, '123456');
    });

    test('ignores lines without the pattern or without a 4-8 digit code',
        () async {
      final f = makeFile('a.log');
      start([f.path]);

      append(f, 'Hello 123456\nYour OTP is 12\nYour OTP is 123456789\n');
      await pump();

      expect(entries, isEmpty);
    });

    test('picks up multiple OTPs written in one batch', () async {
      final f = makeFile('a.log');
      start([f.path]);

      append(f, 'Your OTP is 1111\nYour OTP is 2222\n');
      await pump();

      expect(entries.map((e) => e.otp), ['1111', '2222']);
    });

    test('does not re-report old lines on later appends', () async {
      final f = makeFile('a.log');
      start([f.path]);

      append(f, 'Your OTP is 1111\n');
      await pump();
      append(f, 'Your OTP is 2222\n');
      await pump();

      expect(entries.map((e) => e.otp), ['1111', '2222']);
    });

    test('recovers after the file is truncated', () async {
      final f = makeFile('a.log', 'some long existing content here\n');
      start([f.path]);

      f.writeAsStringSync('Your OTP is 9999\n'); // shorter than before
      f.setLastModifiedSync(DateTime.now().add(Duration(seconds: ++tick)));
      await pump();

      expect(entries.map((e) => e.otp), ['9999']);
    });
  });

  group('multiple files', () {
    test('detects OTPs from each file and tags the source', () async {
      final a = makeFile('a.log');
      final b = makeFile('b.log');
      start([a.path, b.path]);

      append(a, 'Your OTP is 1111\n');
      append(b, 'Your OTP is 2222\n');
      await pump();

      final bySource = {for (final e in entries) e.sourcePath: e.otp};
      expect(bySource, {a.path: '1111', b.path: '2222'});
    });

    test('tracks read offsets independently per file', () async {
      final a = makeFile('a.log', 'padding padding padding padding\n');
      final b = makeFile('b.log');
      start([a.path, b.path]);

      append(b, 'Your OTP is 2222\n');
      await pump();
      append(a, 'Your OTP is 1111\n');
      await pump();

      expect(entries.map((e) => e.otp), unorderedEquals(['1111', '2222']));
      expect(entries, hasLength(2));
    });

    test('duplicate paths are only watched once', () async {
      final a = makeFile('a.log');
      start([a.path, a.path]);

      append(a, 'Your OTP is 1111\n');
      await pump();

      expect(entries, hasLength(1));
    });

    test('a missing file reports an error but others keep working', () async {
      final a = makeFile('a.log');
      final missing = '${tmp.path}/nope.log';
      start([missing, a.path]);

      append(a, 'Your OTP is 1111\n');
      await pump();

      expect(errors, ['File not found: $missing']);
      expect(entries.single.otp, '1111');
      expect(watcher.isRunning, isTrue);
      expect(stoppedCount, 0);
    });

    test('a deleted file is dropped while the rest continue', () async {
      final a = makeFile('a.log');
      final b = makeFile('b.log');
      start([a.path, b.path]);

      a.deleteSync();
      await pump();
      append(b, 'Your OTP is 2222\n');
      await pump();

      expect(errors, ['File no longer exists: ${a.path}']);
      expect(entries.single.otp, '2222');
      expect(watcher.isRunning, isTrue);
      expect(stoppedCount, 0);
    });

    test('stops and notifies once every file is gone', () async {
      final a = makeFile('a.log');
      final b = makeFile('b.log');
      start([a.path, b.path]);

      a.deleteSync();
      b.deleteSync();
      await pump();

      expect(errors, hasLength(2));
      expect(watcher.isRunning, isFalse);
      expect(stoppedCount, 1);
    });
  });

  group('start / stop', () {
    test('notifies stopped when no file can be watched', () {
      start(['${tmp.path}/missing.log']);

      expect(errors, hasLength(1));
      expect(watcher.isRunning, isFalse);
      expect(stoppedCount, 1);
    });

    test('stop() halts detection', () async {
      final f = makeFile('a.log');
      start([f.path]);
      watcher.stop();

      append(f, 'Your OTP is 1111\n');
      await pump();

      expect(entries, isEmpty);
      expect(watcher.isRunning, isFalse);
    });

    test('restarting replaces the previous watch set', () async {
      final a = makeFile('a.log');
      final b = makeFile('b.log');
      start([a.path]);
      start([b.path]);

      append(a, 'Your OTP is 1111\n');
      append(b, 'Your OTP is 2222\n');
      await pump();

      expect(entries.map((e) => e.otp), ['2222']);
    });
  });
}
