import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/gemini_service.dart';
import 'package:corides/services/map_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/models/ride_model.dart';
import 'package:corides/models/notification_model.dart';
import 'package:corides/models/message_model.dart';
import 'package:corides/screens/login_screen.dart';
import 'package:corides/screens/add_vehicle_screen.dart';
import 'package:corides/screens/my_vehicles_screen.dart';
import 'package:corides/screens/gemini_chat_screen.dart';
import 'package:corides/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => FirestoreService()),
        ChangeNotifierProvider(create: (_) => MapService()),
        Provider(create: (_) => GeminiService(AppConstants.geminiApiKey)),
      ],
      child: const CoRidesApp(),
    ),
  );
}

class CoRidesApp extends StatelessWidget {
  const CoRidesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CoRides',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const CoRidesHome(),
    );
  }
}

class CoRidesHome extends StatefulWidget {
  const CoRidesHome({super.key});

  @override
  State<CoRidesHome> createState() => _CoRidesHomeState();
}

class _CoRidesHomeState extends State<CoRidesHome> {
  bool isDriverMode = false;
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MapService>().updateCurrentLocation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      bottomNavigationBar: _buildBottomNavBar(),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeTab(),
          _buildMessagesTab(),
          _buildHistoryTab(),
          _buildSchedulesTab(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text("CoRides", style: TextStyle(fontWeight: FontWeight.bold)),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        _buildNotificationIcon(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNotificationIcon() {
    return Consumer2<AuthService, FirestoreService>(
      builder: (context, auth, firestore, _) {
        if (!auth.isAuthenticated) return const IconButton(icon: Icon(Icons.notifications_none), onPressed: null);

        return StreamBuilder<List<NotificationModel>>(
          stream: firestore.getUserNotifications(auth.user!.uid),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data?.where((n) => !n.isRead).length ?? 0;
            
            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded, size: 28),
                  onPressed: () => _showNotifications(context, snapshot.data ?? []),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        unreadCount > 9 ? "9+" : unreadCount.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
              ],
            );
          },
        );
      },
    );
  }

  void _showNotifications(BuildContext context, List<NotificationModel> notifications) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text("Notifications", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: notifications.isEmpty 
                ? const Center(child: Text("You're all caught up!"))
                : ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final n = notifications[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: n.isRead ? Colors.grey[100] : Colors.blue[50],
                          child: Icon(
                            n.type == 'interest' ? Icons.favorite_rounded : Icons.notifications,
                            color: n.isRead ? Colors.grey : Colors.blue,
                          ),
                        ),
                        title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.body),
                            const SizedBox(height: 4),
                            Text(n.timestamp.toString().split('.')[0], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                        onTap: () async {
                          if (!n.isRead && n.id != null) {
                            await context.read<FirestoreService>().markNotificationAsRead(n.id!);
                          }
                          // Handle navigation if needed (e.g. to a ride detail or message)
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

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Stats Card
          Consumer2<AuthService, FirestoreService>(
            builder: (context, auth, firestore, _) {
              if (!auth.isAuthenticated) return const SizedBox.shrink();

              return FutureBuilder<UserModel?>(
                future: firestore.getUser(auth.user!.uid),
                builder: (context, snapshot) {
                  final user = snapshot.data;
                  if (user == null) return const SizedBox.shrink();

                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4285F4), Color(0xFF9171E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Welcome, ${user.name.isNotEmpty ? user.name : (user.phoneNumber.isNotEmpty ? user.phoneNumber : 'User')}!",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.logout, color: Colors.white),
                                onPressed: () async {
                                  await auth.signOut();
                                },
                                tooltip: "Logout",
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statItem(Icons.directions_car, "${user.totalTrips}", "Trips"),
                            _statItem(Icons.star, user.rating.toStringAsFixed(1), "Rating"),
                            _statItem(Icons.account_balance_wallet, "\$${user.walletBalance.toStringAsFixed(0)}", "Wallet"),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withValues(alpha: 0.3), thickness: 1),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Passenger",
                              style: TextStyle(
                                color: !isDriverMode ? Colors.white : Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: !isDriverMode ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: isDriverMode,
                                onChanged: (value) async {
                                  if (value) {
                                    await _handleDriverSwitch();
                                  } else {
                                    setState(() => isDriverMode = false);
                                  }
                                },
                                activeThumbColor: Colors.white,
                                activeTrackColor: Colors.white.withValues(alpha: 0.3),
                                inactiveThumbColor: Colors.white,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                            Text(
                              "Driver",
                              style: TextStyle(
                                color: isDriverMode ? Colors.white : Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: isDriverMode ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          _buildInteractionPanel(),
          const SizedBox(height: 24),
          _buildMapCard(),
          const SizedBox(height: 100), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Consumer<MapService>(
      builder: (context, mapService, _) {
        return Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(target: LatLng(33.6844, 73.0479), zoom: 14),
                onMapCreated: mapService.onMapCreated,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: mapService.markers,
                polylines: mapService.polylines,
              ),
              Positioned(
                top: 15,
                right: 15,
                child: FloatingActionButton.small(
                  onPressed: mapService.updateCurrentLocation,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Colors.blueAccent),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Colors.white.withValues(alpha: 0.8),
                  child: const Row(
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text("Your Current Location", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
      ],
    );
  }


  Widget _buildMessagesTab() {
    return Consumer2<AuthService, FirestoreService>(
      builder: (context, auth, firestore, child) {
        if (!auth.isAuthenticated) {
          return const Center(child: Text("Sign in to see messages"));
        }
        return StreamBuilder<List<MessageModel>>(
          stream: firestore.getUserMessages(auth.user!.uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final messages = snapshot.data!;
            if (messages.isEmpty) return const Center(child: Text("No messages yet"));
            
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return ListTile(
                  leading: Icon(msg.isUserMessage ? Icons.person_outline : Icons.auto_awesome, 
                             color: msg.isUserMessage ? Colors.blue : Colors.purple),
                  title: Text(msg.content),
                  subtitle: Text(msg.timestamp.toString().split('.')[0]),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return const Center(child: Text("History Screen Coming Soon"));
  }

  Widget _buildSchedulesTab() {
    return Consumer2<AuthService, FirestoreService>(
      builder: (context, auth, firestore, child) {
        if (!auth.isAuthenticated) return const Center(child: Text("Sign in to see schedules"));
        
        return StreamBuilder<List<RideModel>>(
          stream: firestore.getUserRides(auth.user!.uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final rides = snapshot.data!;
            if (rides.isEmpty) return const Center(child: Text("No scheduled rides yet"));
            
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 16),
              itemCount: rides.length,
              itemBuilder: (context, index) {
                final ride = rides[index];
                return Card(
                  elevation: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ride.type == 'offer' ? Colors.green[100] : Colors.blue[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ride.type.toUpperCase(),
                                style: TextStyle(
                                  color: ride.type == 'offer' ? Colors.green[900] : Colors.blue[900],
                                  fontSize: 12, fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Text("\$${ride.negotiatedPrice.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.map_outlined, color: Colors.blueAccent),
                                  onPressed: () => _showRouteDialog(context, ride),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text("Delete Schedule"),
                                        content: const Text("Are you sure you want to cancel this ride?"),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && ride.id != null) {
                                      await firestore.deleteRide(ride.id!);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ride cancelled")));
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ridePoint(Icons.circle_outlined, Colors.blue, ride.originAddress),
                        const Padding(
                          padding: EdgeInsets.only(left: 11),
                          child: SizedBox(height: 10, child: VerticalDivider(thickness: 1, width: 2)),
                        ),
                        _ridePoint(Icons.location_on, Colors.red, ride.destinationAddress),
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(ride.departureTime.toString().split('.')[0]),
                            const Spacer(),
                            const Icon(Icons.event_seat, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text("${ride.seatsAvailable} seats"),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showRouteDialog(BuildContext context, RideModel ride) {
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF9171E5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Route Preview', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng((ride.origin.latitude + ride.destination.latitude) / 2, (ride.origin.longitude + ride.destination.longitude) / 2),
                      zoom: 12,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('origin'),
                        position: LatLng(ride.origin.latitude, ride.origin.longitude),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                        infoWindow: InfoWindow(title: 'Origin', snippet: ride.originAddress),
                      ),
                      Marker(
                        markerId: const MarkerId('destination'),
                        position: LatLng(ride.destination.latitude, ride.destination.longitude),
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: InfoWindow(title: 'Destination', snippet: ride.destinationAddress),
                      ),
                    },
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: [LatLng(ride.origin.latitude, ride.origin.longitude), LatLng(ride.destination.latitude, ride.destination.longitude)],
                        color: Colors.blueAccent,
                        width: 4,
                      ),
                    },
                    onMapCreated: (controller) {
                      final bounds = LatLngBounds(
                        southwest: LatLng(
                          ride.origin.latitude < ride.destination.latitude ? ride.origin.latitude : ride.destination.latitude,
                          ride.origin.longitude < ride.destination.longitude ? ride.origin.longitude : ride.destination.longitude,
                        ),
                        northeast: LatLng(
                          ride.origin.latitude > ride.destination.latitude ? ride.origin.latitude : ride.destination.latitude,
                          ride.origin.longitude > ride.destination.longitude ? ride.origin.longitude : ride.destination.longitude,
                        ),
                      );
                      Future.delayed(const Duration(milliseconds: 100), () => controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80)));
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

  Widget _ridePoint(IconData icon, Color color, String address) {
    return Row(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(address, style: const TextStyle(fontSize: 15))),
      ],
    );
  }

  Widget _buildMapView() {
    return Consumer<MapService>(
      builder: (context, mapService, child) {
        return GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(33.6844, 73.0479),
            zoom: 13,
          ),
          onMapCreated: (controller) {
            mapService.onMapCreated(controller);
            mapService.updateCurrentLocation();
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          markers: mapService.markers,
          polylines: mapService.polylines,
        );
      },
    );
  }

  Future<void> _handleDriverSwitch() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);

    if (!auth.isAuthenticated) {
      _showLoginScreen();
      return;
    }

    final user = await firestore.getUser(auth.user!.uid);
    if (user != null && user.vehicles.isNotEmpty) {
      setState(() => isDriverMode = true);
    } else {
      _showAddVehicleDialog();
    }
  }

  void _showAddVehicleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Become a Driver"),
        content: const Text("You must register a vehicle to switch to driver mode."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => AddVehicleScreen(onVehicleAdded: () => setState(() => isDriverMode = true))));
            },
            child: const Text("Add Vehicle"),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Consumer2<AuthService, FirestoreService>(
        builder: (context, auth, firestore, child) {
          if (!auth.isAuthenticated) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 60, color: Colors.grey),
                const SizedBox(height: 16),
                const Text("Sign in to see your profile"),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _showLoginScreen, child: const Text("Sign In")),
              ],
            );
          }

          return FutureBuilder<UserModel?>(
            future: firestore.getUser(auth.user!.uid),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return Column(
                children: [
                  UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: Colors.blueAccent),
                    accountName: Text(user?.name.isNotEmpty == true ? user!.name : "User"),
                    accountEmail: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(user?.phoneNumber ?? ""),
                        Text("Balance: \$${user?.walletBalance ?? 0.0}"),
                      ],
                    ),
                    currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.blueAccent)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.directions_car),
                    title: const Text("My Vehicles"),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MyVehiclesScreen()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.wallet),
                    title: const Text("Wallet"),
                    subtitle: Text("\$${user?.walletBalance ?? 0.0}"),
                    onTap: () {},
                  ),
                  const Spacer(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: const Text("Logout"),
                    onTap: () async {
                      await auth.signOut();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey[600],
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline_rounded), label: "Messages"),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: "History"),
          BottomNavigationBarItem(icon: Icon(Icons.event_note_rounded), label: "Schedules"),
        ],
      ),
    );
  }

  Widget _buildInteractionPanel() {
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _showGeminiChatScreen,
                  child: AbsorbPointer(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: isDriverMode ? "To where you are offering rides?" : "Where would you like to go?",
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.blueAccent),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _showGeminiChatScreen,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF4285F4), Color(0xFF9171E5), Color(0xFFF4AFBA)],
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              "Connecting people through smart, AI ride sharing.",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blueAccent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF4285F4), Color(0xFF9171E5), Color(0xFFF4AFBA)],
                ).createShader(bounds),
                child: const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                "Powered by Gemini 3",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  void _showLoginScreen() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
  }

  void _showGeminiChatScreen() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final mapService = Provider.of<MapService>(context, listen: false);
    
    if (!auth.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please sign in to use AI assistant")));
      return;
    }

    String? currentAddress;
    if (mapService.currentPosition != null) {
      currentAddress = await mapService.getAddressFromLatLng(
        LatLng(mapService.currentPosition!.latitude, mapService.currentPosition!.longitude),
      );
    }
    
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (context) => GeminiChatScreen(
      isDriverMode: isDriverMode,
      currentLocationAddress: currentAddress,
    )));
  }
}