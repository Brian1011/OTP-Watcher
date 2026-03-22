import 'dart:async';
import 'dart:io';

import 'package:otp_watcher/otp_entry.dart';

class WatcherService {
  Timer? _timer;
  int _latsBytesOffset = 0;
  DateTime? _lastModified;

  final Duration pollInterval;

  WatcherService({this.pollInterval = const Duration(seconds: 2)});

  /// Starts watching [filePath] for new lines.
  /// Calls [onOtpDetected] whenever a new OTP matching [searchPattern] is found.
  /// Calls [onError] if something goes wrong.
  void start({
    required String filePath,
    required String searchPattern,
    required Function(OtpEntry otp) onOtpDetected,
    required Function(Object error) onError,
  }) {
    stop(); // clear any existing watcher

    final file = File(filePath);
    if (!file.existsSync()) {
      onError('File not found: $filePath');
      return;
    }

    // start from the current end of file and scan for new lines
    _latsBytesOffset = file.lengthSync();
    _lastModified = file.lastModifiedSync();

    _timer = Timer.periodic(pollInterval, (_) async {
      try {
        if (!file.existsSync()) {
          onError('File not found: $filePath');
          stop();
          return;
        }

        final currentModified = file.lastModifiedSync();

        // Only read if the file has actually changed
        if (currentModified == _lastModified) return;
        _lastModified = currentModified;

        final currentLength = file.lengthSync();

        // File was truncated / rotated - reset offset
        if (currentLength < _latsBytesOffset) {
          _latsBytesOffset = 0;
        }

        if (currentLength == _latsBytesOffset) return;

        // Read the new content
        final raf = file.openSync(mode: FileMode.read);
        raf.setPosition(_latsBytesOffset);
        final newBytes = raf.readSync(currentLength - _latsBytesOffset);
        raf.closeSync();

        _latsBytesOffset = currentLength;
        final newContent = String.fromCharCodes(newBytes);
        final newLines = newContent.split('\n');

        for (final line in newLines) {
          if (line.trim().isEmpty) continue;

          final entry = _extractOtp(line, searchPattern);

          if (entry != null) {
            onOtpDetected(entry);
          }
        }
      } catch (e) {
        onError('Watcher error: $e');
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _latsBytesOffset = 0;
    _lastModified = null;
  }

  bool get isRunning => _timer != null;

  /// Tries to extract an OTP from [line] given a [searchPattern].
  /// The OTP is the first 4–8 digit number that follows the pattern in the line.
  OtpEntry? _extractOtp(String line, String searchPattern) {
    final lowerline = line.toLowerCase();
    final lowerPattern = searchPattern.toLowerCase();

    if (!lowerline.contains(lowerPattern)) return null;

    // Find OTP digits that appear after the search pattern
    final patternIndex = lowerline.indexOf(lowerPattern);
    final afterPattern = lowerline.substring(
      patternIndex + lowerPattern.length,
    );

    final otpMatch = RegExp(r'\b(\d{4,8})\b').firstMatch(afterPattern);

    if (otpMatch == null) return null;

    return OtpEntry(
      otp: otpMatch.group(1)!,
      rawLine: line,
      detectedAt: DateTime.now(),
    );
  }
}
