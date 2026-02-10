import 'package:cloud_firestore/cloud_firestore.dart';

class RideModel {
  final String? id;
  final String creatorId;
  final String type; // 'request' | 'offer'
  final GeoPoint origin;
  final String originAddress;
  final GeoPoint destination;
  final String destinationAddress;
  final List<GeoPoint> waypoints;
  final DateTime departureTime;
  final String status; // 'pending', 'matched', 'ongoing', 'completed', 'cancelled'
  final double negotiatedPrice;
  final int seatsAvailable;

  RideModel({
    this.id,
    required this.creatorId,
    required this.type,
    required this.origin,
    required this.originAddress,
    required this.destination,
    required this.destinationAddress,
    this.waypoints = const [],
    required this.departureTime,
    this.status = 'pending',
    required this.negotiatedPrice,
    this.seatsAvailable = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'creator_id': creatorId,
      'type': type,
      'origin': origin,
      'origin_address': originAddress,
      'destination': destination,
      'destination_address': destinationAddress,
      'waypoints': waypoints,
      'departure_time': Timestamp.fromDate(departureTime),
      'status': status,
      'negotiated_price': negotiatedPrice,
      'seats_available': seatsAvailable,
    };
  }

  factory RideModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return RideModel(
      id: id,
      creatorId: map['creator_id'],
      type: map['type'],
      origin: map['origin'],
      originAddress: map['origin_address'],
      destination: map['destination'],
      destinationAddress: map['destination_address'],
      waypoints: List<GeoPoint>.from(map['waypoints'] ?? []),
      departureTime: (map['departure_time'] as Timestamp).toDate(),
      status: map['status'],
      negotiatedPrice: (map['negotiated_price'] as num).toDouble(),
      seatsAvailable: map['seats_available'] ?? 1,
    );
  }
}
