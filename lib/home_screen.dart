import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'watcher_service.dart';
import 'notification_service.dart';
import 'otp_entry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _filePathController = TextEditingController();
  final _patternController = TextEditingController();
  final _scrollController = ScrollController();

  final WatcherService _watcher = WatcherService();
  final NotificationService _notifier = NotificationService();

  final List<OtpEntry> _entries = [];
  bool _isWatching = false;
  String? _errorMessage;

  static const _prefFilePath = 'pref_file_path';
  static const _prefPattern = 'pref_pattern';

  @override
  void initState() {
    super.initState();
    _notifier.init();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _filePathController.text = prefs.getString(_prefFilePath) ?? '';
      _patternController.text = prefs.getString(_prefPattern) ?? 'Your OTP is';
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefFilePath, _filePathController.text.trim());
    await prefs.setString(_prefPattern, _patternController.text.trim());
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['log', 'txt'],
      dialogTitle: 'Select SMS Log File',
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _filePathController.text = result.files.single.path!);
    }
  }

  void _startWatching() {
    final filePath = _filePathController.text.trim();
    final pattern = _patternController.text.trim();

    if (filePath.isEmpty) {
      setState(() => _errorMessage = 'Please select a log file.');
      return;
    }
    if (pattern.isEmpty) {
      setState(() => _errorMessage = 'Please enter a search pattern.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isWatching = true;
    });

    _savePrefs();

    _watcher.start(
      filePath: filePath,
      searchPattern: pattern,
      onOtpDetected: (entry) {
        setState(() => _entries.insert(0, entry));
        _notifier.showOtpNotification(
          otp: entry.otp,
          message: _truncate(entry.rawLine, 80),
        );
        _copyOtp(entry.otp);
      },
      onError: (error) {
        debugPrint('Error: $error');
        setState(() {
          _errorMessage = error;
          _isWatching = false;
        });
      },
    );
  }

  void _stopWatching() {
    _watcher.stop();
    setState(() => _isWatching = false);
  }

  void _clearEntries() {
    setState(() => _entries.clear());
  }

  void _copyOtp(String otp) {
    Clipboard.setData(ClipboardData(text: otp));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP $otp copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 280,
      ),
    );
  }

  String _truncate(String text, int maxLength) {
    return text.length > maxLength ? '${text.substring(0, maxLength)}…' : text;
  }

  @override
  void dispose() {
    _watcher.stop();
    _notifier.dispose();
    _filePathController.dispose();
    _patternController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      body: Column(
        children: [
          _buildHeader(),
          _buildConfigPanel(),
          if (_errorMessage != null) _buildErrorBanner(),
          _buildEntriesHeader(),
          Expanded(child: _buildEntriesList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lock_clock,
              color: Color(0xFF38BDF8),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OTP Watcher',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                _isWatching ? 'Watching for changes…' : 'Not watching',
                style: TextStyle(
                  color: _isWatching
                      ? const Color(0xFF4ADE80)
                      : const Color(0xFF64748B),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Status dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isWatching
                  ? const Color(0xFF4ADE80)
                  : const Color(0xFF374151),
              shape: BoxShape.circle,
              boxShadow: _isWatching
                  ? [
                      BoxShadow(
                        color: const Color(0xFF4ADE80).withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File path row
          _buildLabel('Log File'),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _filePathController,
                  hint: '/path/to/africas-talking-sms.log',
                  enabled: !_isWatching,
                ),
              ),
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.folder_open_rounded,
                onTap: _isWatching ? null : _pickFile,
                tooltip: 'Browse',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pattern row
          _buildLabel('Search Pattern'),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _patternController,
            hint: 'e.g. Your OTP is',
            enabled: !_isWatching,
          ),
          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: _isWatching
                ? OutlinedButton.icon(
                    onPressed: _stopWatching,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('Stop Watching'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF87171),
                      side: const BorderSide(color: Color(0xFFF87171)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _startWatching,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Watching'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F1117),
                      // fontWeight: FontWeight.w600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF374151), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF0F1117),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1E293B)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF38BDF8)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1A1D27)),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E293B)),
          ),
          child: Icon(
            icon,
            color: onTap != null
                ? const Color(0xFF94A3B8)
                : const Color(0xFF374151),
            size: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B1B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFF87171).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _errorMessage = null),
            child: const Icon(Icons.close, color: Color(0xFFF87171), size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
      child: Row(
        children: [
          Text(
            'Detected OTPs',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          if (_entries.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_entries.length}',
                style: const TextStyle(
                  color: Color(0xFF38BDF8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const Spacer(),
          if (_entries.isNotEmpty)
            InkWell(
              onTap: _clearEntries,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Clear',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntriesList() {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              color: const Color(0xFF1E293B),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              _isWatching
                  ? 'Waiting for new OTPs…'
                  : 'Start watching to detect OTPs',
              style: const TextStyle(color: Color(0xFF374151), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _entries.length,
      itemBuilder: (context, index) =>
          _buildEntryCard(_entries[index], index == 0),
    );
  }

  Widget _buildEntryCard(OtpEntry entry, bool isLatest) {
    final timeStr = DateFormat('HH:mm:ss').format(entry.detectedAt);
    final dateStr = DateFormat('MMM d').format(entry.detectedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLatest ? const Color(0xFF0D2137) : const Color(0xFF1A1D27),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLatest
              ? const Color(0xFF38BDF8).withValues(alpha: 0.3)
              : const Color(0xFF1E293B),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OTP badge
          GestureDetector(
            onTap: () => _copyOtp(entry.otp),
            child: Tooltip(
              message: 'Click to copy',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isLatest
                      ? const Color(0xFF38BDF8)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  entry.otp,
                  style: TextStyle(
                    color: isLatest
                        ? const Color(0xFF0F1117)
                        : const Color(0xFF38BDF8),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Raw line + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.rawLine,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$dateStr · $timeStr',
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Copy icon
          InkWell(
            onTap: () => _copyOtp(entry.otp),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy_rounded,
                color: const Color(0xFF374151),
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
