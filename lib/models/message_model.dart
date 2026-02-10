import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String? id;
  final String userId; // Still used for AI chat logs
  final String? senderId;
  final String? receiverId;
  final String? rideId;
  final DateTime timestamp;
  final bool isUserMessage;
  final String content;
  final String role; // 'rider' | 'driver'
  final Map<String, dynamic>? intentExtracted;

  MessageModel({
    this.id,
    required this.userId,
    this.senderId,
    this.receiverId,
    this.rideId,
    required this.timestamp,
    required this.isUserMessage,
    required this.content,
    this.role = 'rider',
    this.intentExtracted,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'ride_id': rideId,
      'timestamp': Timestamp.fromDate(timestamp),
      'is_user_message': isUserMessage,
      'content': content,
      'role': role,
      'intent_extracted': intentExtracted,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return MessageModel(
      id: id,
      userId: map['user_id'] ?? '',
      senderId: map['sender_id'],
      receiverId: map['receiver_id'],
      rideId: map['ride_id'],
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isUserMessage: map['is_user_message'] ?? true,
      content: map['content'] ?? '',
      role: map['role'] ?? 'rider',
      intentExtracted: map['intent_extracted'] != null
          ? Map<String, dynamic>.from(map['intent_extracted'])
          : null,
    );
  }
}
