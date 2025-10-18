import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DriverLoginPage extends StatefulWidget {
  const DriverLoginPage({super.key});

  @override
  State<DriverLoginPage> createState() => _DriverLoginPageState();
}

class _DriverLoginPageState extends State<DriverLoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _isCheckingSession = true;

  final String backendUrl = "https://e4784d33af60.ngrok-free.app";

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  /// ✅ CHECK IF USER IS ALREADY LOGGED IN (WITHOUT BACKEND VERIFICATION)
  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString("driverId");
      final vehicleType = prefs.getString("vehicleType") ?? '';
      final isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      final phoneNumber = prefs.getString("phoneNumber") ?? '';

      print("🔍 Checking existing session...");
      print("   Driver ID: $driverId");
      print("   Phone: $phoneNumber");
      print("   Vehicle Type: '$vehicleType'");
      print("   Is Logged In: $isLoggedIn");

      // ✅ Simply check if we have the required data
      if (isLoggedIn && 
          driverId != null && 
          driverId.isNotEmpty && 
          phoneNumber.isNotEmpty) {
        
        print("✅ Valid local session found - auto-navigating");
        
        // Small delay to prevent instant navigation (better UX)
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        // Navigate to appropriate screen based on stored data
        if (vehicleType.isNotEmpty) {
          print("🚗 Navigating to dashboard with vehicle: '$vehicleType'");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDashboardPage(
                driverId: driverId,
                vehicleType: vehicleType,
              ),
            ),
          );
        } else {
          print("📄 No vehicle type - navigating to document upload");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        }
        return;
      } else {
        print("❌ No valid session found - showing login screen");
      }
    } catch (e) {
      print("⚠️ Error checking session: $e");
    } finally {
      if (mounted) {
        setState(() => _isCheckingSession = false);
      }
    }
  }

  /// ✅ CLEAR SESSION DATA
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear everything
    
    // Sign out from Firebase
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      print("⚠️ Firebase sign-out error: $e");
    }
  }

  Future<void> _sendOTP() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _codeSent = false;
      _otpController.clear();
    });

    final rawPhone = _phoneController.text.trim();
    if (rawPhone.length != 10) {
      setState(() => _isLoading = false);
      _showMessage("Please enter a valid 10-digit phone number.", isError: true);
      return;
    }

    final String phoneWithCode = "+91$rawPhone";

    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/auth/send-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phoneWithCode}),
      ).timeout(const Duration(seconds: 15));

      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        setState(() => _codeSent = true);
        _showMessage("OTP sent to your phone", isError: false);
        Future.delayed(
          const Duration(milliseconds: 300),
          () => _otpFocus.requestFocus(),
        );
      } else {
        _showMessage("Failed to send OTP. Please try again.", isError: true);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showMessage("Error sending OTP: ${e.toString()}", isError: true);
    }
  }

  Future<void> _verifyOTPAndLogin() async {
    if (_isLoading) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showMessage("Please enter the 6-digit OTP.", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _showLoadingDialog();

    final rawPhone = _phoneController.text.trim();
    final phoneWithCode = "+91$rawPhone";

    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/auth/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "phone": phoneWithCode,
          "otp": otp,
          "role": "driver",
        }),
      ).timeout(const Duration(seconds: 30));

      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        print("═══════════════════════════════════════════");
        print("📋 FULL LOGIN RESPONSE:");
        print(jsonEncode(data));
        print("═══════════════════════════════════════════");
        
        if (data["firebaseToken"] != null) {
          try {
            await FirebaseAuth.instance.signInWithCustomToken(data["firebaseToken"]);
            print("✅ Firebase sign-in successful");
          } catch (e) {
            debugPrint("❌ Firebase sign-in failed: $e");
          }
        }

        final driverId = data["user"]["_id"];
        final isNewUser = data["newUser"] == true;
        final docsApproved = data["docsApproved"] == true;
        
        print("═══════════════════════════════════════════");
        print("📋 EXTRACTING USER DATA:");
        print("   Raw user object: ${data["user"]}");
        print("   user['vehicleType']: ${data["user"]["vehicleType"]}");
        print("   Type of vehicleType: ${data["user"]["vehicleType"]?.runtimeType}");
        print("═══════════════════════════════════════════");
        
        String vehicleType = '';
        
        if (data["user"]["vehicleType"] != null) {
          vehicleType = data["user"]["vehicleType"].toString().toLowerCase().trim();
          print("✅ Vehicle type extracted: '$vehicleType'");
        } else {
          print("⚠️ WARNING: vehicleType is NULL in response!");
        }
        
        print("═══════════════════════════════════════════");
        print("📋 FINAL DRIVER DETAILS:");
        print("   Driver ID: $driverId");
        print("   Vehicle Type: '$vehicleType'");
        print("   Vehicle Type Length: ${vehicleType.length}");
        print("   Is Empty: ${vehicleType.isEmpty}");
        print("   Is New User: $isNewUser");
        print("   Docs Approved: $docsApproved");
        print("═══════════════════════════════════════════");

        // ✅ SAVE SESSION DATA PERSISTENTLY
        final prefs = await SharedPreferences.getInstance();
        
        // Save all required data
        await prefs.setString("driverId", driverId);
        await prefs.setString("phoneNumber", rawPhone);
        await prefs.setString("vehicleType", vehicleType);
        await prefs.setBool("isLoggedIn", true);
        await prefs.setInt("loginTimestamp", DateTime.now().millisecondsSinceEpoch);
        
        // Also save the login response for reference
        await prefs.setString("lastLoginResponse", jsonEncode(data));
        
        // Verify the data was saved
        final savedDriverId = prefs.getString("driverId");
        final savedIsLoggedIn = prefs.getBool("isLoggedIn");
        print("✅ Verification - Saved Driver ID: $savedDriverId");
        print("✅ Verification - Saved isLoggedIn: $savedIsLoggedIn");
        print("✅ Driver session saved successfully.");

        if (isNewUser) {
          print("🆕 New user - navigating to document upload");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        } else if (docsApproved) {
          if (vehicleType.isEmpty) {
            print("⚠️ CRITICAL: Vehicle type is EMPTY for approved driver!");
            _showMessage(
              "Please complete your vehicle registration first.",
              isError: true,
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => DriverDocumentUploadPage(driverId: driverId),
              ),
            );
            return;
          }
          
          print("🚗 Navigating to dashboard with vehicle type: '$vehicleType'");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDashboardPage(
                driverId: driverId,
                vehicleType: vehicleType,
              ),
            ),
          );
        } else {
          print("📄 Existing user with pending docs - navigating to review page");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DocumentsReviewPage(driverId: driverId),
            ),
          );
        }
      } else {
        final errorData = jsonDecode(response.body);
        print("❌ Login failed: ${errorData['message']}");
        _showMessage(
          errorData['message'] ?? "Login failed. Invalid OTP?",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
      print("❌ Exception during login: $e");
      _showMessage("An error occurred: ${e.toString()}", isError: true);
    }
  }

  Future<void> _resendOTP() async {
    _showMessage("Resending OTP...", isError: false);
    await _sendOTP();
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Verifying...", style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner while checking session
    if (_isCheckingSession) {
      return const Scaffold(
        backgroundColor: Color(0xFFF0F4FF),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Checking session...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Driver Login',
                style: TextStyle(
                  fontSize: 26,
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
              const SizedBox(height: 40),
              const Text('Enter your mobile number', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                enabled: !_codeSent && !_isLoading,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  prefixText: '+91 ',
                  hintText: '0000000000',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              if (_codeSent) ...[
                const Text('Enter OTP', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 10),
                TextField(
                  controller: _otpController,
                  focusNode: _otpFocus,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  enabled: !_isLoading,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(6),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    hintText: '6-digit OTP',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _verifyOTPAndLogin(),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _codeSent = false),
                      child: const Text('Change Number'),
                    ),
                    TextButton(
                      onPressed: _isLoading ? null : _resendOTP,
                      child: const Text('Resend OTP'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : (_codeSent ? _verifyOTPAndLogin : _sendOTP),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(_codeSent ? 'Verify & Login' : 'Send OTP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocus.dispose();
    super.dispose();
  }
}