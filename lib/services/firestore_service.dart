import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/models/ride_model.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/models/notification_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // User Operations
  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUser(String uid) async {
    var doc = await _db.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(doc.data()!);
    }
    return null;
  }

  // Ride Operations
  Future<void> createRide(RideModel ride) async {
    await _db.collection('rides').add(ride.toMap());
  }

  Stream<List<RideModel>> getActiveRides() {
    return _db
        .collection('rides')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList());
  }

  // Message Operations
  Future<void> saveMessage(MessageModel message) async {
    await _db.collection('messages').add(message.toMap());
  }

  Stream<List<MessageModel>> getUserMessages(String userId, {String? role}) {
    Query query = _db.collection('messages').where('user_id', isEqualTo: userId);
    if (role != null) {
      query = query.where('role', isEqualTo: role);
    }
    return query
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => MessageModel.fromMap(doc.data() as Map<String, dynamic>)).toList());
  }

  Stream<List<MessageModel>> getPeerChatMessages(String userId, String otherId, String rideId) {
    // This is a simple query. For production, more complex composite indexes might be needed.
    return _db.collection('messages')
        .where('ride_id', isEqualTo: rideId)
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs
              .map((doc) => MessageModel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .where((m) => 
                (m.senderId == userId && m.receiverId == otherId) || 
                (m.senderId == otherId && m.receiverId == userId))
              .toList();
          messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return messages;
        });
  }

  Future<void> sendPeerMessage(MessageModel message) async {
    await _db.collection('messages').add(message.toMap());
  }

  Future<List<MessageModel>> getMessagesOnce(String userId) async {
    final snapshot = await _db
        .collection('messages')
        .where('user_id', isEqualTo: userId)
        .orderBy('timestamp', descending: false)
        .get();
    return snapshot.docs.map((doc) => MessageModel.fromMap(doc.data())).toList();
  }

  Stream<List<RideModel>> getUserRides(String userId) {
    return _db
        .collection('rides')
        .where('creator_id', isEqualTo: userId)
        .orderBy('departure_time', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList());
  }

  Future<void> addVehicle(String uid, VehicleModel vehicle) async {
    await _db.collection('users').doc(uid).update({
      'vehicles': FieldValue.arrayUnion([vehicle.toMap()])
    });
  }

  Future<void> removeVehicle(String uid, VehicleModel vehicle) async {
    await _db.collection('users').doc(uid).update({
      'vehicles': FieldValue.arrayRemove([vehicle.toMap()])
    });
  }

  Future<void> deleteRide(String rideId) async {
    await _db.collection('rides').doc(rideId).delete();
  }

  Future<List<RideModel>> searchRides({required String type, String status = 'pending', String? excludeUserId}) async {
    try {
      // Layer 1: Advanced Firestore Query (Preferred, efficient)
      Query query = _db
          .collection('rides')
          .where('type', isEqualTo: type)
          .where('status', isEqualTo: status);
      
      if (excludeUserId != null) {
        query = query.where('creator_id', isNotEqualTo: excludeUserId);
      }

      final snapshot = await query.orderBy('creator_id').orderBy('departure_time', descending: false).get();
      return snapshot.docs.map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
    } catch (e) {
      debugPrint('Advanced search failed (likely missing index), trying Layer 2: $e');
      try {
        // Layer 2: Basic Firestore Query + In-Memory Processing
        // Only filters by type/status (requires single-field indexes only)
        final snapshot = await _db
            .collection('rides')
            .where('type', isEqualTo: type)
            .where('status', isEqualTo: status)
            .get();
        
        var results = snapshot.docs.map((doc) => RideModel.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList();
        
        // Manual filter
        if (excludeUserId != null) {
          final beforeCount = results.length;
          results = results.where((r) => r.creatorId != excludeUserId).toList();
          debugPrint('Filtered out user own rides. Total before: $beforeCount, After: ${results.length}');
        }
        
        // Manual sort
        results.sort((a, b) => a.departureTime.compareTo(b.departureTime));
        
        return results;
      } catch (e2) {
        debugPrint('Layer 2 search failed too: $e2');
        return [];
      }
    }
  }

  // Notification Operations
  Future<void> createNotification(NotificationModel notification) async {
    await _db.collection('notifications').add(notification.toMap());
  }

  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _db.collection('notifications')
        .where('receiver_id', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({'is_read': true});
  }
}
