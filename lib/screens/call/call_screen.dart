import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import '../../models/call_model.dart';
import '../../models/user_model.dart';
import '../../services/socket_service.dart';

class CallScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel peerUser;
  final CallType callType;
  final bool isCaller;
  final Map<String, dynamic>? incomingOffer;

  const CallScreen({
    super.key,
    required this.currentUser,
    required this.peerUser,
    required this.callType,
    required this.isCaller,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SocketService _socketService = SocketService();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isSpeaker = true;
  String _callStatusText = 'Bağlanıyor...';

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _initWebRTC();
  }

  void _initWebRTC() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Set initial audio output (Speakerphone on for video, earpiece for audio call)
    _isSpeaker = isVideo;
    Helper.setSpeakerphoneOn(_isSpeaker);

    // 1. Get Local Camera / Audio
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': isVideo ? {'facingMode': 'user'} : false,
      });
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      debugPrint('Media error: $e');
    }

    // 2. Create Peer Connection
    _peerConnection = await createPeerConnection(_iceServers);

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteRenderer.srcObject = event.streams[0];
          _remoteStream = event.streams[0];
          _callStatusText = 'Görüşme Başladı';
        });
      }
    };

    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // Send ICE candidates to peer
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _socketService.emitIceCandidate(
        targetUserId: widget.peerUser.uid,
        candidate: candidate.toMap(),
      );
    };

    // Socket Event Listeners
    _socketService.onIceCandidate = (candidateData) async {
      final candidate = candidateData['candidate'];
      if (candidate != null) {
        await _peerConnection?.addCandidate(
          RTCIceCandidate(
            candidate['candidate'],
            candidate['sdpMid'],
            candidate['sdpMLineIndex'],
          ),
        );
      }
    };

    _socketService.onCallEnded = () {
      _hangUp(notifyPeer: false);
    };

    // 3. Initiate or Answer Call
    if (widget.isCaller) {
      setState(() {
        _callStatusText = 'Çalıyor...';
      });

      _socketService.onCallAnswered = (answerData) async {
        final answer = answerData['answer'];
        if (answer != null) {
          await _peerConnection?.setRemoteDescription(
            RTCSessionDescription(answer['sdp'], answer['type']),
          );
          setState(() {
            _callStatusText = 'Görüşme Başladı';
          });
        }
      };

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      _socketService.emitCall(
        caller: widget.currentUser,
        receiverId: widget.peerUser.uid,
        offer: offer.toMap(),
        callType: widget.callType == CallType.video ? 'video' : 'audio',
      );
    } else {
      // Receiver: Answer incoming offer
      if (widget.incomingOffer != null) {
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(
            widget.incomingOffer!['sdp'],
            widget.incomingOffer!['type'],
          ),
        );

        RTCSessionDescription answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);

        _socketService.emitAnswer(
          callerId: widget.peerUser.uid,
          answer: answer.toMap(),
        );

        setState(() {
          _callStatusText = 'Görüşme Başladı';
        });
      }
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    Helper.setSpeakerphoneOn(_isSpeaker);
  }

  void _toggleMic() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  void _toggleVideo() {
    setState(() {
      _isVideoOff = !_isVideoOff;
    });
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = !_isVideoOff;
    });
  }

  void _switchCamera() {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      Helper.switchCamera(_localStream!.getVideoTracks()[0]);
    }
  }

  void _hangUp({bool notifyPeer = true}) async {
    if (notifyPeer) {
      _socketService.emitEndCall(widget.peerUser.uid);
    }

    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    _localStream = null;

    _remoteStream?.getTracks().forEach((track) => track.stop());
    await _remoteStream?.dispose();
    _remoteStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _hangUp(notifyPeer: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == CallType.video;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Video / Audio View
            if (isVideo) ...[
              // Remote Video Fullscreen
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

              // Local Camera PIP
              Positioned(
                right: 20,
                top: 30,
                width: 110,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ] else ...[
              // Audio Call UI
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 65,
                      backgroundImage: CachedNetworkImageProvider(widget.peerUser.photoUrl),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.peerUser.displayName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _callStatusText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Top Caller Info Banner
            Positioned(
              top: 24,
              left: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerUser.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                  ),
                  Text(
                    _callStatusText,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Action Controls
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Speakerphone / Ahize Toggle
                    IconButton(
                      icon: Icon(
                        _isSpeaker ? Icons.volume_up : Icons.volume_off,
                        color: _isSpeaker ? AppColors.primaryLight : Colors.white,
                        size: 28,
                      ),
                      onPressed: _toggleSpeaker,
                    ),

                    // Mute Audio
                    IconButton(
                      icon: Icon(
                        _isMuted ? Icons.mic_off : Icons.mic,
                        color: _isMuted ? AppColors.callRed : Colors.white,
                        size: 28,
                      ),
                      onPressed: _toggleMic,
                    ),

                    // Toggle Video / Switch Camera
                    if (isVideo) ...[
                      IconButton(
                        icon: Icon(
                          _isVideoOff ? Icons.videocam_off : Icons.videocam,
                          color: _isVideoOff ? AppColors.callRed : Colors.white,
                          size: 28,
                        ),
                        onPressed: _toggleVideo,
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.cameraswitch,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _switchCamera,
                      ),
                    ],

                    // End Call
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.callRed,
                      child: IconButton(
                        icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                        onPressed: () => _hangUp(notifyPeer: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
