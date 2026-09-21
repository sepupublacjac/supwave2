package com.megamendung.supwave2

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity (not plain FlutterActivity) so the audio_service
// plugin can correctly route media button presses (headset/Bluetooth) and
// keep the activity alive alongside the background playback service.
class MainActivity : AudioServiceActivity()
