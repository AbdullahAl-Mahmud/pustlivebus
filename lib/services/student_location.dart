import 'dart:async';

import 'package:geolocator/geolocator.dart';

class StudentFix {
  const StudentFix(this.lat, this.lng, this.accuracy, this.capturedAt);
  final double lat, lng, accuracy;
  final DateTime capturedAt;
  bool get fresh {
    final age = DateTime.now().difference(capturedAt).inSeconds;
    return age >= -5 && age < 120;
  }
}

/// One explicit permission request and one fix. No watch, disk or server write.
Future<StudentFix> requestStudentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('ফোনের Location / GPS চালু করুন।');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw StateError(
      'Location permission বন্ধ আছে। Browser বা ফোনের settings থেকে অনুমতি দিন, অথবা স্টপ নিজে বেছে নিন।',
    );
  }
  if (permission == LocationPermission.denied) {
    throw StateError(
      'Location permission দেওয়া হয়নি। স্টপ নিজে বেছে নিতে পারবেন।',
    );
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  ).timeout(const Duration(seconds: 25));
  final fix = StudentFix(
    position.latitude,
    position.longitude,
    position.accuracy,
    position.timestamp,
  );
  if (!fix.lat.isFinite ||
      !fix.lng.isFinite ||
      fix.lat.abs() > 90 ||
      fix.lng.abs() > 180 ||
      !fix.accuracy.isFinite ||
      fix.accuracy < 0 ||
      fix.accuracy > 200 ||
      !fix.fresh) {
    throw StateError(
      'বর্তমান অবস্থান যথেষ্ট নির্ভুল নয়। খোলা জায়গায় আবার চেষ্টা করুন অথবা স্টপ বেছে নিন।',
    );
  }
  return fix;
}

String metersLabel(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
