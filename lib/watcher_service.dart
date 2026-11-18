import 'dart:async';
import 'dart:io';
import 'otp_entry.dart';

/// Tracks the read position of a single watched file.
class _FileState {
  final File file;
  int lastByteOffset;
  DateTime? lastModified;

  _FileState(this.file, this.lastByteOffset, this.lastModified);
}

class WatcherService {
  Timer? _timer;
  final Map<String, _FileState> _files = {};

  final Duration pollInterval;

  WatcherService({this.pollInterval = const Duration(seconds: 2)});

  /// Starts watching every path in [filePaths] for new lines.
  /// Calls [onOtpDetected] whenever a new OTP matching [searchPattern] is found.
  /// Calls [onError] if something goes wrong. A missing file only stops that
  /// file; the others keep being watched. If no file can be watched, the
  /// whole watcher stops.
  void start({
    required List<String> filePaths,
    required String searchPattern,
    required void Function(OtpEntry entry) onOtpDetected,
    required void Function(String error) onError,
    void Function()? onStopped,
  }) {
    stop(); // clear any existing watcher

    for (final path in filePaths.toSet()) {
      final file = File(path);
      if (!file.existsSync()) {
        onError('File not found: $path');
        continue;
      }
      // Start from the current end of file — we only want NEW lines
      _files[path] = _FileState(
        file,
        file.lengthSync(),
        file.lastModifiedSync(),
      );
    }

    if (_files.isEmpty) {
      onStopped?.call();
      return;
    }

    _timer = Timer.periodic(pollInterval, (_) {
      for (final path in _files.keys.toList()) {
        try {
          _poll(path, searchPattern, onOtpDetected);
        } on FileSystemException catch (e) {
          onError('Cannot read $path: ${e.message}');
        } catch (e) {
          onError('Watcher error ($path): $e');
        }
      }

      // Drop files that disappeared; stop everything once none remain.
      final gone = _files.entries
          .where((e) => !e.value.file.existsSync())
          .map((e) => e.key)
          .toList();
      for (final path in gone) {
        onError('File no longer exists: $path');
        _files.remove(path);
      }
      if (_files.isEmpty) {
        stop();
        onStopped?.call();
      }
    });
  }

  void _poll(
    String path,
    String searchPattern,
    void Function(OtpEntry entry) onOtpDetected,
  ) {
    final state = _files[path]!;
    final file = state.file;
    if (!file.existsSync()) return;

    final currentModified = file.lastModifiedSync();

    // Only read if the file has actually changed
    if (currentModified == state.lastModified) return;
    state.lastModified = currentModified;

    final currentLength = file.lengthSync();

    // File was truncated / rotated — reset offset
    if (currentLength < state.lastByteOffset) {
      state.lastByteOffset = 0;
    }

    if (currentLength == state.lastByteOffset) return;

    // Read only the new bytes
    final raf = file.openSync();
    final List<int> newBytes;
    try {
      raf.setPositionSync(state.lastByteOffset);
      newBytes = raf.readSync(currentLength - state.lastByteOffset);
    } finally {
      raf.closeSync();
    }

    state.lastByteOffset = currentLength;

    final newContent = String.fromCharCodes(newBytes);
    for (final line in newContent.split('\n')) {
      if (line.trim().isEmpty) continue;

      final entry = _extractOtp(line, searchPattern, path);
      if (entry != null) {
        onOtpDetected(entry);
      }
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _files.clear();
  }

  bool get isRunning => _timer != null;

  /// Tries to extract an OTP from [line] given a [searchPattern].
  /// The OTP is the first 4–8 digit number that follows the pattern in the line.
  OtpEntry? _extractOtp(String line, String searchPattern, String sourcePath) {
    final lowerLine = line.toLowerCase();
    final lowerPattern = searchPattern.toLowerCase();

    if (!lowerLine.contains(lowerPattern)) return null;

    // Find OTP digits that appear after the search pattern
    final patternIndex = lowerLine.indexOf(lowerPattern);
    final afterPattern = line.substring(patternIndex + searchPattern.length);

    final otpMatch = RegExp(r'\b(\d{4,8})\b').firstMatch(afterPattern);
    if (otpMatch == null) return null;

    return OtpEntry(
      otp: otpMatch.group(1)!,
      rawLine: line.trim(),
      detectedAt: DateTime.now(),
      sourcePath: sourcePath,
    );
  }
}
