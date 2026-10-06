import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }
enum CallStatus { ringing, accepted, rejected, ended, busy }

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerPic;
  final String receiverId;
  final String receiverName;
  final String receiverPic;
  final CallType callType;
  final CallStatus callStatus;
  final DateTime timestamp;

  CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerPic,
    required this.receiverId,
    required this.receiverName,
    required this.receiverPic,
    required this.callType,
    this.callStatus = CallStatus.ringing,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerPic': callerPic,
      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverPic': receiverPic,
      'callType': callType.name,
      'callStatus': callStatus.name,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['callId'] ?? '',
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerPic: map['callerPic'] ?? '',
      receiverId: map['receiverId'] ?? '',
      receiverName: map['receiverName'] ?? '',
      receiverPic: map['receiverPic'] ?? '',
      callType: CallType.values.firstWhere(
        (e) => e.name == map['callType'],
        orElse: () => CallType.video,
      ),
      callStatus: CallStatus.values.firstWhere(
        (e) => e.name == map['callStatus'],
        orElse: () => CallStatus.ringing,
      ),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
