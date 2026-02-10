import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:corides/services/auth_service.dart';
import 'package:corides/services/firestore_service.dart';
import 'package:corides/models/user_model.dart';

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key});

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool isOtpSent = false;
  String? verificationId;
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 30),
          Text(
            isOtpSent ? "Verify OTP" : "Welcome to CoRides",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isOtpSent ? "Enter the 6-digit code sent to your phone" : "Sign in with your phone number to continue",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          if (!isOtpSent)
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: "+92 300 1234567",
                prefixIcon: const Icon(Icons.phone),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          else
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "123456",
                prefixIcon: const Icon(Icons.lock_clock),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: isLoading ? null : (isOtpSent ? _verifyOtp : _sendOtp),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(isOtpSent ? "Verify & Proceed" : "Send OTP"),
            ),
          ),
        ],
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

    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() => isLoading = true);
    
    try {
      await auth.signInWithPhoneNumber(
        _phoneController.text,
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
            String message = "Authentication failed";
            if (e.code == 'invalid-phone-number') {
              message = "The provided phone number is not valid.";
            } else if (e.code == 'too-many-requests') {
              message = "Too many requests. Try again later.";
            } else if (e.code == 'missing-client-identifier') {
              message = "Configuration error: Check SHA-1/SHA-256 in Firebase Console.";
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? message)));
          }
        },
        onVerificationCompleted: (credential) async {
          // Auto-verify on some Android devices
          try {
            final auth = Provider.of<AuthService>(context, listen: false);
            final firestore = Provider.of<FirestoreService>(context, listen: false);
            final cred = await auth.signInWithCredential(credential);
            
            if (cred.user != null) {
              await _handleUserSignIn(cred.user!, firestore);
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Auto-verification failed: $e")));
            }
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

  Future<void> _handleUserSignIn(User user, FirestoreService firestore) async {
    try {
      // Create user in firestore if not exists
      final existingUser = await firestore.getUser(user.uid);
      if (existingUser == null) {
        await firestore.createUser(UserModel(
          uid: user.uid,
          phoneNumber: user.phoneNumber ?? _phoneController.text,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Profile sync failed: $e")));
      }
    }
  }

  Future<void> _verifyOtp() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final firestore = Provider.of<FirestoreService>(context, listen: false);
    setState(() => isLoading = true);

    try {
      final cred = await auth.confirmOTP(verificationId!, _otpController.text);
      if (cred.user != null) {
        await _handleUserSignIn(cred.user!, firestore);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }
}
