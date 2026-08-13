package com.audiloc.audiloc

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (still a FlutterActivity under the hood) instead of
// plain FlutterActivity — required by audio_service to share its
// FlutterEngine with the background playback service. See
// docs/building-android.md.
class MainActivity : AudioServiceActivity()
