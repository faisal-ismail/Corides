import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class MapService extends ChangeNotifier {
  GoogleMapController? _controller;
  Position? _currentPosition;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  GoogleMapController? get controller => _controller;
  Position? get currentPosition => _currentPosition;
  Set<Marker> get markers => _markers;
  Set<Polyline> get polylines => _polylines;

  void onMapCreated(GoogleMapController controller) {
    _controller = controller;
    notifyListeners();
  }

  Future<void> updateCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _currentPosition = await Geolocator.getCurrentPosition();
    
    if (_controller != null && _currentPosition != null) {
      _controller!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        ),
      );
    }
    notifyListeners();
  }

  void addMarker(String id, LatLng position, String title) {
    _markers.add(
      Marker(
        markerId: MarkerId(id),
        position: position,
        infoWindow: InfoWindow(title: title),
      ),
    );
    notifyListeners();
  }

  void clearMarkers() {
    _markers.clear();
    notifyListeners();
  }

  /// Geocode an address to LatLng coordinates
  /// Returns null if geocoding fails
  Future<LatLng?> geocodeAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        final location = locations.first;
        return LatLng(location.latitude, location.longitude);
      }
    } catch (e) {
      debugPrint('Geocoding error for "$address": $e');
    }
    return null;
  }

  /// Get multiple potential locations for an address
  Future<List<Map<String, dynamic>>> getAddressSuggestions(String address) async {
    try {
      final locations = await locationFromAddress(address);
      List<Map<String, dynamic>> suggestions = [];
      
      for (var loc in locations) {
        try {
          final placemarks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            suggestions.add({
              'address': "${p.name}, ${p.subLocality}, ${p.locality}",
              'latitude': loc.latitude,
              'longitude': loc.longitude,
            });
          }
        } catch (e) {
          suggestions.add({
            'address': address,
            'latitude': loc.latitude,
            'longitude': loc.longitude,
          });
        }
      }
      return suggestions;
    } catch (e) {
      debugPrint('Suggestion error: $e');
    }
    return [];
  }

  /// Draw a route polyline between two points
  void drawRouteBetween(LatLng origin, LatLng destination) {
    _polylines.clear();
    _polylines.add(
      Polyline(
        polylineId: const PolylineId('route'),
        points: [origin, destination],
        color: Colors.blueAccent,
        width: 4,
      ),
    );
    notifyListeners();
  }

  /// Clear all polylines
  void clearPolylines() {
    _polylines.clear();
    notifyListeners();
  }

  /// Reverse geocode LatLng to address string
  Future<String?> getAddressFromLatLng(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        return "${p.name}, ${p.subLocality}, ${p.locality}, ${p.administrativeArea}";
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
    return null;
  }
}
