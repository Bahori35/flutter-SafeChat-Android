import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }
enum CallStatus { ringing, accepted, rejected, ended, busy, missed }

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
  final int durationSeconds;
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
    this.callStatus = CallStatus.ended,
    this.durationSeconds = 0,
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
      'durationSeconds': durationSeconds,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory CallModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedTimestamp = DateTime.now();
    final rawTs = json['createdAt'] ?? json['created_at'] ?? json['timestamp'];
    if (rawTs != null) {
      if (rawTs is DateTime) {
        parsedTimestamp = rawTs;
      } else if (rawTs is Timestamp) {
        parsedTimestamp = rawTs.toDate();
      } else if (rawTs is String) {
        parsedTimestamp = DateTime.tryParse(rawTs) ?? DateTime.now();
      }
    }

    return CallModel(
      callId: json['id']?.toString() ?? json['callId']?.toString() ?? '',
      callerId: json['callerId']?.toString() ?? json['caller_id']?.toString() ?? '',
      callerName: json['callerName'] ?? json['caller_name'] ?? 'Kullanıcı',
      callerPic: json['callerPic'] ?? json['caller_pic'] ?? '',
      receiverId: json['receiverId']?.toString() ?? json['receiver_id']?.toString() ?? '',
      receiverName: json['receiverName'] ?? json['receiver_name'] ?? 'Kullanıcı',
      receiverPic: json['receiverPic'] ?? json['receiver_pic'] ?? '',
      callType: (json['callType'] ?? json['call_type']) == 'video' ? CallType.video : CallType.audio,
      callStatus: CallStatus.values.firstWhere(
        (e) => e.name == (json['callStatus'] ?? json['call_status']),
        orElse: () => CallStatus.ended,
      ),
      durationSeconds: json['durationSeconds'] ?? json['duration_seconds'] ?? 0,
      timestamp: parsedTimestamp,
    );
  }

  factory CallModel.fromMap(Map<String, dynamic> map) => CallModel.fromJson(map);

  String get formattedDuration {
    if (durationSeconds <= 0) {
      if (callStatus == CallStatus.missed || callStatus == CallStatus.rejected) {
        return 'Cevapsız';
      }
      return '0 sn';
    }
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    if (minutes > 0) {
      return '$minutes dk ${seconds > 0 ? "$seconds sn" : ""}';
    }
    return '$seconds sn';
  }
}
