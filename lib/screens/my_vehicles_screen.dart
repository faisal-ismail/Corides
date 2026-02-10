
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/screens/add_vehicle_screen.dart';

class MyVehiclesScreen extends StatefulWidget {
  const MyVehiclesScreen({super.key});

  @override
  State<MyVehiclesScreen> createState() => _MyVehiclesScreenState();
}

class _MyVehiclesScreenState extends State<MyVehiclesScreen> {
  // Simple technique to force rebuild future
  late Future<UserModel?> _userFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      final auth = Provider.of<AuthService>(context, listen: false);
      final firestore = Provider.of<FirestoreService>(context, listen: false);
      _userFuture = firestore.getUser(auth.user!.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Access providers
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddVehicleScreen(
                onVehicleAdded: () {
                  // This callback might not be needed if we await the push
                },
              ),
            ),
          );
          _refresh();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<UserModel?>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("User profile not found."));
          }

          final user = snapshot.data!;
          if (user.vehicles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.directions_car_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("No vehicles added yet"),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: user.vehicles.length,
            itemBuilder: (context, index) {
              final vehicle = user.vehicles[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Icon(
                      vehicle.seatingCapacity > 2 ? Icons.directions_car : Icons.two_wheeler,
                      color: Colors.blue[800],
                    ),
                  ),
                  title: Text(vehicle.model, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${vehicle.regNo} (${vehicle.year})"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Remove Vehicle"),
                          content: Text("Are you sure you want to remove ${vehicle.model}?"),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              child: const Text("Remove"),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          await firestore.removeVehicle(auth.user!.uid, vehicle);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Vehicle removed")),
                            );
                            _refresh();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error removing vehicle: $e")),
                            );
                          }
                        }
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
