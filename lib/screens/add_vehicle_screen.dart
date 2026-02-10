import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/services/auth_service.dart';

class AddVehicleScreen extends StatefulWidget {
  final VoidCallback? onVehicleAdded;
  
  const AddVehicleScreen({super.key, this.onVehicleAdded});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _regNoController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _capacityController = TextEditingController(text: "4");
  bool _hasAc = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _regNoController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _submitVehicle() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final auth = Provider.of<AuthService>(context, listen: false);
      final firestore = Provider.of<FirestoreService>(context, listen: false);
      
      try {
        final vehicle = VehicleModel(
          regNo: _regNoController.text.trim(),
          model: _modelController.text.trim(),
          year: _yearController.text.trim(),
          hasAc: _hasAc,
          seatingCapacity: int.parse(_capacityController.text.trim()),
        );

        if (auth.user != null) {
          await firestore.addVehicle(auth.user!.uid, vehicle);
          if (widget.onVehicleAdded != null) {
            widget.onVehicleAdded!();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Vehicle added successfully!"),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error adding vehicle: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Enter Details",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text("Register your car or bike to start driving."),
              const SizedBox(height: 32),
              
              TextFormField(
                controller: _regNoController,
                decoration: const InputDecoration(
                  labelText: "Registration Number (e.g. LEC-1234)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.confirmation_number),
                ),
                validator: (v) => v?.isEmpty == true ? "Required" : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: "Vehicle Model (e.g. Honda City)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.directions_car),
                ),
                validator: (v) => v?.isEmpty == true ? "Required" : null,
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _yearController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Year",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      validator: (v) => v?.isEmpty == true ? "Required" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _capacityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Capacity",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.group),
                      ),
                      validator: (v) => v?.isEmpty == true ? "Required" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              SwitchListTile(
                title: const Text("Has AC?"),
                value: _hasAc,
                onChanged: (v) => setState(() => _hasAc = v),
                secondary: const Icon(Icons.ac_unit),
              ),
              
              const SizedBox(height: 32),
              
              ElevatedButton(
                onPressed: _isLoading ? null : _submitVehicle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                  ? const SizedBox(
                      height: 20, 
                      width: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text("Register Vehicle", style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
