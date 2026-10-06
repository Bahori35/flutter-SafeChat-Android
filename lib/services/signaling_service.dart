import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_model.dart';
import '../models/user_model.dart';

typedef StreamStateCallback = void Function(MediaStream stream);

class SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  String? currentCallId;
  StreamSubscription? _callSub;

  StreamStateCallback? onAddRemoteStream;

  // Stream incoming calls for user
  Stream<CallModel?> getIncomingCallsStream(String currentUserId) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: currentUserId)
        .where('callStatus', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return CallModel.fromMap(snapshot.docs.first.data());
    });
  }

  // Stream call status changes
  Stream<DocumentSnapshot> getCallStream(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots();
  }

  // Initialize WebRTC media streams
  Future<void> openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo, {
    bool isVideo = true,
  }) async {
    var stream = await navigator.mediaDevices.getUserMedia({
      'video': isVideo ? {'facingMode': 'user'} : false,
      'audio': true,
    });

    localVideo.srcObject = stream;
    localStream = stream;

    remoteVideo.srcObject = await createLocalMediaStream('remote');
  }

  // Make a Call (Caller)
  Future<String> makeCall({
    required UserModel caller,
    required UserModel receiver,
    required CallType callType,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    final callDoc = _firestore.collection('calls').doc();
    currentCallId = callDoc.id;

    peerConnection = await createPeerConnection(configuration);

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        remoteStream = event.streams[0];
      }
    };

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    // ICE Candidates
    var callerCandidatesCollection = callDoc.collection('callerCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidatesCollection.add(candidate.toMap());
    };

    // Create SDP Offer
    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    Map<String, dynamic> roomWithOffer = {
      'callId': callDoc.id,
      'callerId': caller.uid,
      'callerName': caller.displayName,
      'callerPic': caller.photoUrl,
      'receiverId': receiver.uid,
      'receiverName': receiver.displayName,
      'receiverPic': receiver.photoUrl,
      'callType': callType.name,
      'callStatus': CallStatus.ringing.name,
      'timestamp': FieldValue.serverTimestamp(),
      'offer': offer.toMap(),
    };

    await callDoc.set(roomWithOffer);

    // Listen for Answer
    _callSub = callDoc.snapshots().listen((snapshot) async {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        if (peerConnection?.getRemoteDescription() == null && data['answer'] != null) {
          var answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await peerConnection?.setRemoteDescription(answer);
        }
      }
    });

    // Listen for Callee ICE candidates
    callDoc.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          Map<String, dynamic> data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });

    return callDoc.id;
  }

  // Answer Call (Callee)
  Future<void> answerCall({
    required String callId,
    required RTCVideoRenderer localRenderer,
    required RTCVideoRenderer remoteRenderer,
  }) async {
    currentCallId = callId;
    var callDoc = _firestore.collection('calls').doc(callId);
    var callSnapshot = await callDoc.get();

    if (!callSnapshot.exists) return;
    var callData = callSnapshot.data() as Map<String, dynamic>;

    peerConnection = await createPeerConnection(configuration);

    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        remoteStream = event.streams[0];
      }
    };

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    // Collect ICE Candidates for Callee
    var calleeCandidatesCollection = callDoc.collection('calleeCandidates');
    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      calleeCandidatesCollection.add(candidate.toMap());
    };

    // Set Remote Description (Caller Offer)
    var offer = callData['offer'];
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    // Create SDP Answer
    var answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    await callDoc.update({
      'answer': answer.toMap(),
      'callStatus': CallStatus.accepted.name,
    });

    // Listen for Caller ICE Candidates
    callDoc.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  // End or Reject Call
  Future<void> endCall(String? callId) async {
    final id = callId ?? currentCallId;
    if (id != null) {
      await _firestore.collection('calls').doc(id).update({
        'callStatus': CallStatus.ended.name,
      });
    }

    await _callSub?.cancel();
    _callSub = null;

    localStream?.getTracks().forEach((track) => track.stop());
    await localStream?.dispose();
    localStream = null;

    remoteStream?.getTracks().forEach((track) => track.stop());
    await remoteStream?.dispose();
    remoteStream = null;

    await peerConnection?.close();
    peerConnection = null;
    currentCallId = null;
  }
}
