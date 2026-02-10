import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:corides/models/ride_model.dart';

class MatchingLogic {
  static const double matchingRadiusMeters = 2000.0; // 2km

  /// Matches a Rider's request against all available Driver offers.
  /// Returns a list of compatible RideModels (offers).
  static List<RideModel> findMatches(RideModel request, List<RideModel> offers) {
    if (request.type != 'request') return [];

    return offers.where((offer) {
      if (offer.type != 'offer' || offer.seatsAvailable <= 0) return false;

      // check if origin is near driver's route
      bool originNear = _isPointNearRoute(request.origin, offer);
      
      // check if destination is near driver's route
      bool destinationNear = _isPointNearRoute(request.destination, offer);

      return originNear && destinationNear;
    }).toList();
  }

  static bool _isPointNearRoute(GeoPoint point, RideModel offer) {
    // Check origin
    double distOrigin = Geolocator.distanceBetween(
      point.latitude, point.longitude,
      offer.origin.latitude, offer.origin.longitude
    );
    if (distOrigin <= matchingRadiusMeters) return true;

    // Check destination
    double distDest = Geolocator.distanceBetween(
      point.latitude, point.longitude,
      offer.destination.latitude, offer.destination.longitude
    );
    if (distDest <= matchingRadiusMeters) return true;

    // Check waypoints
    for (var wp in offer.waypoints) {
      double distWp = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        wp.latitude, wp.longitude
      );
      if (distWp <= matchingRadiusMeters) return true;
    }

    return false;
  }
}
