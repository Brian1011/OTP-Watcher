class OtpEntry {
  final String otp;
  final String rawLine;
  final DateTime detectedAt;

  OtpEntry({
    required this.otp,
    required this.rawLine,
    required this.detectedAt,
  });
}