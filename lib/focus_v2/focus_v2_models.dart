import 'dart:typed_data';

/// Metadata from the installed-app selection / Android package manager.
/// Never hard-code YouTube or replace a real package icon with a brand asset.
class FocusTarget {
  const FocusTarget({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });

  final String packageName;
  final String appName;
  final Uint8List? iconBytes;
}

/// Native verification outcome. This is NOT inferred from counting to 5.
class VerifiedFocusGrant {
  const VerifiedFocusGrant({
    required this.granted,
    this.accessUntil,
    this.error,
  });

  final bool granted;
  final DateTime? accessUntil;
  final String? error;

  bool isConfirmedAt(DateTime now) =>
      granted && accessUntil != null && accessUntil!.isAfter(now);

  int remainingWholeMinutesAt(DateTime now) {
    if (!isConfirmedAt(now)) return 0;
    final millis = accessUntil!.difference(now).inMilliseconds;
    return (millis / Duration.millisecondsPerMinute).ceil();
  }
}

/// Only the EXISTING ML Kit detector should produce this reading.
class FocusPoseReading {
  const FocusPoseReading({
    required this.repetitions,
    required this.poseDetected,
  });

  final int repetitions;
  final bool poseDetected;
}
