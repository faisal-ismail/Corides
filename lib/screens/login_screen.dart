
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/models/user_model.dart';
import 'package:corides/screens/gemini_chat_screen.dart'; // Just in case, but likely back to main.

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool isOtpSent = false;
  String? verificationId;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Text(
                isOtpSent ? "Verify OTP" : "Welcome to CoRides",
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isOtpSent
                    ? "Enter the 6-digit code sent to your phone"
                    : "Sign in with your phone number to continue",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 48),
              if (!isOtpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: "+92 300 1234567",
                    prefixIcon: const Icon(Icons.phone),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: "123456",
                    prefixIcon: const Icon(Icons.lock_clock),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 2,
                  ),
                  onPressed: isLoading ? null : (isOtpSent ? _verifyOtp : _sendOtp),
                  child: isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isOtpSent ? "Verify & Proceed" : "Send OTP",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              if (isOtpSent)
                TextButton(
                  onPressed: () => setState(() => isOtpSent = false),
                  child: const Text("Use a different number"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    if (_phoneController.text.isEmpty || !_phoneController.text.startsWith('+')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter phone number with country code (e.g. +92...)")),
      );
      return;
    }

    setState(() => isLoading = true);
    final auth = Provider.of<AuthService>(context, listen: false);

    try {
      await auth.signInWithPhoneNumber(
        _phoneController.text.trim(),
        onCodeSent: (id, token) {
          if (mounted) {
            setState(() {
              verificationId = id;
              isOtpSent = true;
              isLoading = false;
            });
          }
        },
        onVerificationFailed: (e) {
          if (mounted) {
            setState(() => isLoading = false);
            String message = e.message ?? "Authentication failed";
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }
        },
        onVerificationCompleted: (credential) async {
          // Auto-resolution on Android
          try {
            final userCred = await auth.signInWithCredential(credential);
            if (userCred.user != null) {
              await _handleUserSignIn(userCred.user!);
            }
          } catch (e) {
            // Handle error
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty) return;
    
    setState(() => isLoading = true);
    final auth = Provider.of<AuthService>(context, listen: false);

    try {
      final cred = await auth.confirmOTP(verificationId!, _otpController.text.trim());
      if (cred.user != null) {
        await _handleUserSignIn(cred.user!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _handleUserSignIn(User user) async {
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    try {
      final existingUser = await firestore.getUser(user.uid);
      if (existingUser == null) {
        // User doesn't exist, need to collect details
        if (mounted) {
          final result = await showModalBottomSheet<Map<String, String>>(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            builder: (context) => _SignupDetailsSheet(phoneNumber: user.phoneNumber ?? _phoneController.text),
          );

          if (result != null) {
            await firestore.createUser(UserModel(
              uid: user.uid,
              phoneNumber: user.phoneNumber ?? _phoneController.text,
              name: result['name']!,
              gender: result['gender']!,
              createdAt: DateTime.now(),
            ));
          } else {
            // User cancelled detail entry - sign out? Or just stay signed in without profile?
            // Safer to sign out if they don't complete profile
            await Provider.of<AuthService>(context, listen: false).signOut();
            return; 
          }
        }
      }
      if (mounted) {
        Navigator.pop(context); // Go back to Home/Main
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile sync failed: $e")));
      }
    }
  }
}

class _SignupDetailsSheet extends StatefulWidget {
  final String phoneNumber;
  const _SignupDetailsSheet({required this.phoneNumber});

  @override
  State<_SignupDetailsSheet> createState() => _SignupDetailsSheetState();
}

class _SignupDetailsSheetState extends State<_SignupDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _gender = 'Male';
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Complete Profile", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (v) => v?.isNotEmpty == true ? null : "Name is required",
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(
                labelText: "Gender",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.people),
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text("Male")),
                DropdownMenuItem(value: 'Female', child: Text("Female")),
                DropdownMenuItem(value: 'Other', child: Text("Other")),
              ],
              onChanged: (v) => setState(() => _gender = v!),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSubmitting ? null : () {
                if (_formKey.currentState!.validate()) {
                  Navigator.pop(context, {'name': _nameController.text.trim(), 'gender': _gender});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text("Create Account"),
            ),
          ],
        ),
      ),
    );
  }
}
