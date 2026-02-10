
import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String phoneNumber;
  final String name;
  final String gender;
  final String role; // 'rider' | 'driver'
  final double walletBalance;
  final double rating;
  final int totalTrips;
  final DateTime createdAt;
  final List<VehicleModel> vehicles;

  UserModel({
    required this.uid,
    required this.phoneNumber,
    this.name = '',
    this.gender = '',
    this.role = 'rider',
    this.walletBalance = 0.0,
    this.rating = 0.0,
    this.totalTrips = 0,
    required this.createdAt,
    this.vehicles = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'phone_number': phoneNumber,
      'name': name,
      'gender': gender,
      'role': role,
      'wallet_balance': walletBalance,
      'rating': rating,
      'total_trips': totalTrips,
      'created_at': Timestamp.fromDate(createdAt),
      'vehicles': vehicles.map((v) => v.toMap()).toList(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      phoneNumber: map['phone_number'] ?? '',
      name: map['name'] ?? '',
      gender: map['gender'] ?? '',
      role: map['role'] ?? 'rider',
      walletBalance: (map['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      totalTrips: (map['total_trips'] as num?)?.toInt() ?? 0,
      createdAt: (map['created_at'] as Timestamp).toDate(),
      vehicles: (map['vehicles'] as List<dynamic>?)
              ?.map((v) => VehicleModel.fromMap(v))
              .toList() ??
          [],
    );
  }
}

class VehicleModel {
  final String regNo;
  final String model;
  final String year;
  final bool hasAc;
  final int seatingCapacity;

  VehicleModel({
    required this.regNo,
    required this.model,
    required this.year,
    required this.hasAc,
    required this.seatingCapacity,
  });

  Map<String, dynamic> toMap() {
    return {
      'reg_no': regNo,
      'model': model,
      'year': year,
      'has_ac': hasAc,
      'seating_capacity': seatingCapacity,
    };
  }

  factory VehicleModel.fromMap(Map<String, dynamic> map) {
    return VehicleModel(
      regNo: map['reg_no'] ?? '',
      model: map['model'] ?? '',
      year: map['year'] ?? '',
      hasAc: map['has_ac'] ?? false,
      seatingCapacity: map['seating_capacity'] ?? 4,
    );
  }
}
