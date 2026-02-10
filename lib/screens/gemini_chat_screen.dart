import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' hide Content, Tool;
import 'package:url_launcher/url_launcher.dart';
import 'package:corides/models/ride_model.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/map_service.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:corides/models/notification_model.dart';
import 'package:corides/screens/peers_chat_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeminiChatScreen extends StatefulWidget {
  final bool isDriverMode;
  final String? currentLocationAddress;
  const GeminiChatScreen({super.key, this.isDriverMode = false, this.currentLocationAddress});

  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  RideModel? _pendingRide;
  LatLng? _originCoords;
  LatLng? _destinationCoords;
  bool _isGeocodingRoute = false;
  LlmProvider? _provider;
  int _lastSavedIndex = 0;
  bool _isLoadingHistory = true;
  List<RideModel> _matchingRides = [];
  bool _isSearchingRides = false;
  final Map<String, UserModel> _userCache = {};

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    
    if (!auth.isAuthenticated) {
      setState(() => _isLoadingHistory = false);
      return;
    }

    List<ChatMessage> history = [];
    try {
      // 1. Load historical messages from Firestore
      final historicalMessages = await firestore.getMessagesOnce(auth.user!.uid);
      
      // 2. Map MessageModel to ChatMessage
      history = historicalMessages.map((m) => ChatMessage(
        text: m.content,
        origin: m.isUserMessage ? MessageOrigin.user : MessageOrigin.llm,
        attachments: const [],
      )).toList();

      _lastSavedIndex = history.length;
    } catch (e) {
      debugPrint("Error loading chat history: $e");
    }

    final currentTime = DateTime.now().toString();
    
    // 3. Create the provider (always with full model config)
    _provider = FirebaseProvider(
      model: FirebaseAI.googleAI().generativeModel(
        model: 'gemini-3-flash-preview',
        systemInstruction: Content.system('You are a helpful ride booking assistant for CoRides. Current time is $currentTime. '
            '${widget.currentLocationAddress != null ? "The user\'s CURRENT LOCATION is: ${widget.currentLocationAddress}. Use this as the default starting point (Origin) if the user doesn\'t specify one." : ""} '
            'Currently, the user is in ${widget.isDriverMode ? "DRIVER" : "PASSENGER"} mode. '
            'If the user is a PASSENGER and wants to see available rides, use find_matching_rides(type: "offer") to show them active offers from drivers. '
            'If the user is a DRIVER and wants to find passengers, use find_matching_rides(type: "request") to show them active requests from passengers. '
            'Before confirming a ride, if an address is vague, use get_location_suggestions to verify it. '
            'Once you have all the details (Origin, Destination, Time, Price, Seats, and Type), use prepare_ride_summary to show the confirmation card. '
            'Details needed: Origin address, Destination address, Departure Time (ISO format), Negotiated Price, Seats Available, and Type (request/offer). ALWAYS ask for missing info one by one.'),
        tools: [
          Tool.functionDeclarations([
            FunctionDeclaration(
              'prepare_ride_summary',
              'Shows a summary card of the ride details for the user to confirm.',
              parameters: {
                'origin_address': Schema.string(description: 'The starting address'),
                'destination_address': Schema.string(description: 'The destination address'),
                'departure_time': Schema.string(description: 'ISO 8601 format date-time string'),
                'negotiated_price': Schema.number(description: 'Total price for the ride'),
                'seats_available': Schema.integer(description: 'Number of seats available'),
                'type': Schema.enumString(description: 'Either "request" or "offer"', enumValues: ['request', 'offer']),
              },
            ),
            FunctionDeclaration(
              'find_matching_rides',
              'Searches for active rides in the database. Use this when a user wants to browse available rides or find matches. Passengers should search for "offer" (drivers providing rides). Drivers should search for "request" (passengers needing rides).',
              parameters: {
                'type': Schema.enumString(description: 'Search for "offer" as a passenger, or "request" as a driver.', enumValues: ['offer', 'request']),
              },
            ),
            FunctionDeclaration(
              'get_location_suggestions',
              'Verifies an address and returns GPS coordinates or multiple name suggestions if ambiguous.',
              parameters: {
                'address': Schema.string(description: 'The address or place name to verify'),
              },
            ),
          ]),
        ],
      ),
      history: history,
      onFunctionCall: _handleFunctionCall,
    );

    // 4. Add listener to persist NEW messages
    _provider!.addListener(_onChatUpdated);

    if (mounted) {
      setState(() => _isLoadingHistory = false);
    }
  }

  void _onChatUpdated() {
    if (_provider == null) return;
    
    final currentHistory = _provider!.history.toList();
    if (currentHistory.length > _lastSavedIndex) {
      for (int i = _lastSavedIndex; i < currentHistory.length; i++) {
        final msg = currentHistory[i];
        // Only save if it has text (ignore tool calls/empty responses)
        if (msg.text?.isNotEmpty ?? false) {
          _persistMessage(msg);
        }
      }
      _lastSavedIndex = currentHistory.length;
    }
  }

  Future<void> _persistMessage(ChatMessage msg) async {
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    if (!auth.isAuthenticated) return;

    try {
      await firestore.saveMessage(MessageModel(
        userId: auth.user!.uid,
        timestamp: DateTime.now(),
        isUserMessage: msg.origin == MessageOrigin.user,
        content: msg.text ?? '',
      ));
    } catch (e) {
      debugPrint("Error persisting message: $e");
    }
  }

  Future<Map<String, Object?>?> _handleFunctionCall(FunctionCall call) async {
    final firestore = context.read<FirestoreService>();
    final mapService = context.read<MapService>();

    if (call.name == 'prepare_ride_summary') {
      final args = call.args;
      final originAddr = args['origin_address'] as String;
      final destAddr = args['destination_address'] as String;
      
      setState(() {
        _pendingRide = RideModel(
          creatorId: context.read<AuthService>().user?.uid ?? '',
          type: args['type'] as String,
          origin: const GeoPoint(0, 0),
          originAddress: originAddr,
          destination: const GeoPoint(0, 0),
          destinationAddress: destAddr,
          departureTime: DateTime.parse(args['departure_time'] as String),
          negotiatedPrice: (args['negotiated_price'] as num).toDouble(),
          seatsAvailable: (args['seats_available'] as num).toInt(),
        );
        _isGeocodingRoute = true;
      });
      
      _geocodeRoute(originAddr, destAddr);
      return {'status': 'summary_shown'};
    } else if (call.name == 'find_matching_rides') {
      final type = call.args['type'] as String;
      final auth = context.read<AuthService>();
      setState(() => _isSearchingRides = true);
      
      final results = await firestore.searchRides(
        type: type, 
        excludeUserId: auth.user?.uid
      );
      
      setState(() {
        _matchingRides = results;
        _isSearchingRides = false;
      });
      return {'count': results.length, 'status': 'results_shown_in_ui'};
    } else if (call.name == 'get_location_suggestions') {
      final address = call.args['address'] as String;
      final suggestions = await mapService.getAddressSuggestions(address);
      return {'suggestions': suggestions, 'count': suggestions.length};
    }
    return null;
  }

  @override
  void dispose() {
    _provider?.removeListener(_onChatUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Assistant'),
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF4285F4), Color(0xFF9171E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _isLoadingHistory 
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                LlmChatView(provider: _provider!),
                if (_pendingRide != null) _buildConfirmationOverlay(),
                if (_matchingRides.isNotEmpty || _isSearchingRides) _buildMatchingRidesOverlay(),
              ],
            ),
    );
  }

  Widget _buildConfirmationOverlay() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Card(
        margin: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Confirm Ride Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Divider(height: 30),
                _detailRow(Icons.my_location, 'From', _pendingRide!.originAddress),
                _detailRow(Icons.location_on, 'To', _pendingRide!.destinationAddress),
                _detailRow(Icons.access_time, 'Time', _pendingRide!.departureTime.toString().split('.')[0]),
                _detailRow(Icons.attach_money, 'Price', '\$${_pendingRide!.negotiatedPrice}'),
                _detailRow(Icons.event_seat, 'Seats', '${_pendingRide!.seatsAvailable}'),
                const SizedBox(height: 16),
                // Coordinates Row
                if (_originCoords != null && _destinationCoords != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.gps_fixed, size: 16, color: Colors.blueAccent),
                            const SizedBox(width: 8),
                            const Text('GPS Coordinates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Origin: ${_originCoords!.latitude.toStringAsFixed(6)}, ${_originCoords!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Destination: ${_destinationCoords!.latitude.toStringAsFixed(6)}, ${_destinationCoords!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Map View Button
                if (_originCoords != null && _destinationCoords != null)
                  OutlinedButton.icon(
                    onPressed: () => _showRouteDialog(context),
                    icon: const Icon(Icons.map),
                    label: const Text('Map View'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blueAccent,
                      side: const BorderSide(color: Colors.blueAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                const SizedBox(height: 20),
                // Map Preview
                if (_isGeocodingRoute)
                  const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_originCoords != null && _destinationCoords != null)
                  _buildMapPreview()
                else
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('Unable to load map preview', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _pendingRide = null;
                        _originCoords = null;
                        _destinationCoords = null;
                        _isGeocodingRoute = false;
                      }),
                      child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _confirmRide,
                      child: const Text('Confirm'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    final bounds = LatLngBounds(
      southwest: LatLng(
        _originCoords!.latitude < _destinationCoords!.latitude ? _originCoords!.latitude : _destinationCoords!.latitude,
        _originCoords!.longitude < _destinationCoords!.longitude ? _originCoords!.longitude : _destinationCoords!.longitude,
      ),
      northeast: LatLng(
        _originCoords!.latitude > _destinationCoords!.latitude ? _originCoords!.latitude : _destinationCoords!.latitude,
        _originCoords!.longitude > _destinationCoords!.longitude ? _originCoords!.longitude : _destinationCoords!.longitude,
      ),
    );

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      clipBehavior: Clip.antiAlias,
      child: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(
            (_originCoords!.latitude + _destinationCoords!.latitude) / 2,
            (_originCoords!.longitude + _destinationCoords!.longitude) / 2,
          ),
          zoom: 12,
        ),
        markers: {
          Marker(
            markerId: const MarkerId('origin'),
            position: _originCoords!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: const InfoWindow(title: 'Origin'),
          ),
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationCoords!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ),
        },
        polylines: {
          Polyline(
            polylineId: const PolylineId('route'),
            points: [_originCoords!, _destinationCoords!],
            color: Colors.blueAccent,
            width: 4,
          ),
        },
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
        mapToolbarEnabled: false,
        onMapCreated: (controller) {
          Future.delayed(const Duration(milliseconds: 100), () {
            controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
          });
        },
      ),
    );
  }

  Future<void> _geocodeRoute(String originAddr, String destAddr) async {
    final mapService = context.read<MapService>();
    
    final origin = await mapService.geocodeAddress(originAddr);
    final destination = await mapService.geocodeAddress(destAddr);
    
    if (mounted) {
      setState(() {
        _originCoords = origin;
        _destinationCoords = destination;
        _isGeocodingRoute = false;
        
        // Update the pending ride with actual coordinates
        if (origin != null && destination != null && _pendingRide != null) {
          _pendingRide = RideModel(
            creatorId: _pendingRide!.creatorId,
            type: _pendingRide!.type,
            origin: GeoPoint(origin.latitude, origin.longitude),
            originAddress: _pendingRide!.originAddress,
            destination: GeoPoint(destination.latitude, destination.longitude),
            destinationAddress: _pendingRide!.destinationAddress,
            departureTime: _pendingRide!.departureTime,
            negotiatedPrice: _pendingRide!.negotiatedPrice,
            seatsAvailable: _pendingRide!.seatsAvailable,
          );
        }
      });
    }
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Future<void> _confirmRide() async {
    if (_pendingRide == null) return;

    try {
      await context.read<FirestoreService>().createRide(_pendingRide!);
      if (mounted) {
        setState(() {
          _pendingRide = null;
          _originCoords = null;
          _destinationCoords = null;
          _isGeocodingRoute = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ride confirmed and scheduled!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showRouteDialog(BuildContext context) {
    if (_originCoords == null || _destinationCoords == null) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF9171E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Route Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Map
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        (_originCoords!.latitude + _destinationCoords!.latitude) / 2,
                        (_originCoords!.longitude + _destinationCoords!.longitude) / 2,
                      ),
                      zoom: 12,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('origin'),
                        position: _originCoords!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                        infoWindow: InfoWindow(title: 'Origin', snippet: _pendingRide!.originAddress),
                      ),
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: _destinationCoords!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: InfoWindow(title: 'Destination', snippet: _pendingRide!.destinationAddress),
                      ),
                    },
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: [_originCoords!, _destinationCoords!],
                        color: Colors.blueAccent,
                        width: 4,
                      ),
                    },
                    onMapCreated: (controller) {
                      final bounds = LatLngBounds(
                        southwest: LatLng(
                          _originCoords!.latitude < _destinationCoords!.latitude ? _originCoords!.latitude : _destinationCoords!.latitude,
                          _originCoords!.longitude < _destinationCoords!.longitude ? _originCoords!.longitude : _destinationCoords!.longitude,
                        ),
                        northeast: LatLng(
                          _originCoords!.latitude > _destinationCoords!.latitude ? _originCoords!.latitude : _destinationCoords!.latitude,
                          _originCoords!.longitude > _destinationCoords!.longitude ? _originCoords!.longitude : _destinationCoords!.longitude,
                        ),
                      );
                      Future.delayed(const Duration(milliseconds: 100), () {
                        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildMatchingRidesOverlay() {
    return Container(
      color: Colors.black54,
      alignment: Alignment.bottomCenter,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Matching Rides Found (${_matchingRides.length})', 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _matchingRides = [])),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isSearchingRides 
                ? const Center(child: CircularProgressIndicator())
                : _matchingRides.isEmpty 
                  ? const Center(child: Text('No matching rides found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _matchingRides.length,
                      itemBuilder: (context, index) {
                        final ride = _matchingRides[index];
                        return FutureBuilder<UserModel?>(
                          future: _userCache.containsKey(ride.creatorId) 
                            ? Future.value(_userCache[ride.creatorId]) 
                            : context.read<FirestoreService>().getUser(ride.creatorId),
                          builder: (context, userSnapshot) {
                            final user = userSnapshot.data;
                            if (user != null && !_userCache.containsKey(ride.creatorId)) {
                              _userCache[ride.creatorId] = user;
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 2,
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: ride.type == 'offer' ? Colors.green[50] : Colors.blue[50],
                                  child: Icon(ride.type == 'offer' ? Icons.drive_eta : Icons.person_search, 
                                    color: ride.type == 'offer' ? Colors.green : Colors.blue),
                                ),
                                title: Text(user?.name ?? 'Loading...', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Row(
                                  children: [
                                    const Icon(Icons.star, size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text(user?.rating.toStringAsFixed(1) ?? '0.0', style: const TextStyle(fontSize: 12)),
                                    const SizedBox(width: 8),
                                    Text('• ${ride.seatsAvailable} seats', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                trailing: Text('\$${ride.negotiatedPrice.toStringAsFixed(0)}', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _detailRow(Icons.location_on_outlined, 'From', ride.originAddress),
                                        _detailRow(Icons.flag_outlined, 'To', ride.destinationAddress),
                                        _detailRow(Icons.access_time, 'Time', ride.departureTime.toString().split('.')[0]),
                                        _detailRow(Icons.attach_money, 'Price', '\$${ride.negotiatedPrice.toStringAsFixed(2)}'),
                                        _detailRow(Icons.info_outline, 'Type', ride.type.toUpperCase()),
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () => _makePhoneCall(user?.phoneNumber ?? ''),
                                              icon: const Icon(Icons.phone, color: Colors.green, size: 18),
                                              label: const Text('Call', style: TextStyle(color: Colors.green, fontSize: 13)),
                                            ),
                                            TextButton.icon(
                                              onPressed: () {
                                                if (user != null) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => PeersChatScreen(
                                                        otherUser: user,
                                                        ride: ride,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              icon: const Icon(Icons.message_outlined, color: Colors.blueAccent, size: 18),
                                              label: const Text('Chat', style: TextStyle(color: Colors.blueAccent, fontSize: 13)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () async {
                                                final auth = context.read<AuthService>();
                                                final firestore = context.read<FirestoreService>();
                                                
                                                if (auth.isAuthenticated) {
                                                  final userId = auth.user!.uid;
                                                  final userName = auth.user?.displayName ?? 'A user';
                                                  
                                                  // Create Interest Notification
                                                  await firestore.createNotification(NotificationModel(
                                                    receiverId: ride.creatorId,
                                                    senderId: userId,
                                                    title: "Someone is interested!",
                                                    body: "$userName is interested in your ride from ${ride.originAddress.split(',')[0]} to ${ride.destinationAddress.split(',')[0]}.",
                                                    type: 'interest',
                                                    referenceId: ride.id,
                                                    timestamp: DateTime.now(),
                                                  ));

                                                  if (mounted) {
                                                    // Send message to AI
                                                    _provider?.sendMessageStream("I'm interested in the ride from ${ride.originAddress} to ${ride.destinationAddress} for \$${ride.negotiatedPrice}.");
                                                    
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text("Interest shared! Notification sent to the creator. Check your notifications later!")),
                                                    );
                                                  }
                                                }
                                                if (mounted) setState(() => _matchingRides = []);
                                              },
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                              child: const Text('Interested', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}
