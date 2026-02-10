import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String? id;
  final String receiverId;
  final String senderId;
  final String title;
  final String body;
  final String type; // 'interest', 'message', 'ride_update'
  final String? referenceId; // e.g. rideId
  final DateTime timestamp;
  final bool isRead;

  NotificationModel({
    this.id,
    required this.receiverId,
    required this.senderId,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'receiver_id': receiverId,
      'sender_id': senderId,
      'title': title,
      'body': body,
      'type': type,
      'reference_id': referenceId,
      'timestamp': Timestamp.fromDate(timestamp),
      'is_read': isRead,
    };
  }

  factory NotificationModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return NotificationModel(
      id: id,
      receiverId: map['receiver_id'] ?? '',
      senderId: map['sender_id'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? 'interest',
      referenceId: map['reference_id'],
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isRead: map['is_read'] ?? false,
    );
  }
}
