class OtpEntry {
  final String otp;
  final String rawLine;
  final DateTime detectedAt;

  /// The log file this OTP was detected in.
  final String sourcePath;

  OtpEntry({
    required this.otp,
    required this.rawLine,
    required this.detectedAt,
    required this.sourcePath,
  });
}
