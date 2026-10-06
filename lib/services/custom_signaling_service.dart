import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';

class CustomSignalingService {
  Map<String, dynamic> configuration = {
    'iceServers': [
      {
        'urls': [
          'stun:stun1.l.google.com:19302',
          'stun:stun2.l.google.com:19302',
        ]
      }
    ]
  };

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  // Initialize Local Media Stream (Camera / Microphone)
  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo, {
    bool isVideo = true,
  }) async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': isVideo
            ? {
                'mandatory': {
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': [],
              }
            : false,
      };

      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localStream = stream;
      localVideo.srcObject = stream;

      peerConnection = await createPeerConnection(configuration);

      peerConnection?.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          remoteVideo.srcObject = event.streams[0];
          remoteStream = event.streams[0];
        }
      };

      localStream?.getTracks().forEach((track) {
        peerConnection?.addTrack(track, localStream!);
      });
    } catch (e) {
      debugPrint('WebRTC Media Error: $e');
    }
  }

  // End Call
  Future<void> endCall() async {
    localStream?.getTracks().forEach((track) => track.stop());
    await localStream?.dispose();
    localStream = null;

    remoteStream?.getTracks().forEach((track) => track.stop());
    await remoteStream?.dispose();
    remoteStream = null;

    await peerConnection?.close();
    peerConnection = null;
  }
}
