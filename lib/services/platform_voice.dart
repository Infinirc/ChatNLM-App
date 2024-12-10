// lib/services/platform_voice.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

abstract class VoicePlatform {
  Future<void> initialize();
  Future<void> startRecording();
  Future<List<int>?> stopRecording();
  Future<void> cancelRecording();
  Future<void> dispose();
  Stream<double>? get amplitudeStream;
}

@visibleForTesting
VoicePlatform createVoicePlatform() {
  throw UnsupportedError(
    'Cannot create a voice platform without dart:html',
  );
}