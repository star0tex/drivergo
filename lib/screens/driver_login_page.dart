import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:drivergoo/screens/documents_review_page.dart';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

// --- MATCHING COLOR PALETTE ---
class AppColors {
  static const Color primary = Color.fromARGB(255, 212, 120, 0);
  static const Color background = Colors.white;
  static const Color onSurface = Colors.black;
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onPrimary = Colors.white;
  static const Color onSurfaceSecondary = Colors.black54;
  static const Color onSurfaceTertiary = Colors.black38;
  static const Color divider = Color(0xFFEEEEEE);
  static const Color success = Color.fromARGB(255, 0, 66, 3);
  static const Color warning = Color(0xFFFFA000);
  static const Color error = Color(0xFFD32F2F);
  static const Color serviceCardBg = Color.fromARGB(255, 238, 216, 189);
}

// --- MATCHING TYPOGRAPHY ---
class AppTextStyles {
  static TextStyle get heading1 => GoogleFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.onSurface,
        letterSpacing: -0.5,
      );

  static TextStyle get heading2 => GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
        letterSpacing: -0.3,
      );

  static TextStyle get heading3 => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      );

  static TextStyle get body1 => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      );

  static TextStyle get body2 => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceSecondary,
      );

  static TextStyle get caption => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.onSurfaceTertiary,
        letterSpacing: 0.5,
      );

  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary,
      );
}

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

  final String backendUrl = "https://7668d252ef1d.ngrok-free.app";

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final driverId = prefs.getString("driverId");
      final vehicleType = prefs.getString("vehicleType") ?? '';
      final isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      final phoneNumber = prefs.getString("phoneNumber") ?? '';

      debugPrint("🔍 Checking existing session...");
      debugPrint("   Driver ID: $driverId");
      debugPrint("   Phone: $phoneNumber");
      debugPrint("   Vehicle Type: '$vehicleType'");
      debugPrint("   Is Logged In: $isLoggedIn");

      if (isLoggedIn && 
          driverId != null && 
          driverId.isNotEmpty && 
          phoneNumber.isNotEmpty) {
        
        debugPrint("✅ Valid local session found - auto-navigating");
        
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        if (vehicleType.isNotEmpty) {
          debugPrint("🚗 Navigating to dashboard with vehicle: '$vehicleType'");
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
          debugPrint("📄 No vehicle type - navigating to document upload");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        }
        return;
      } else {
        debugPrint("❌ No valid session found - showing login screen");
      }
    } catch (e) {
      debugPrint("⚠️ Error checking session: $e");
    } finally {
      if (mounted) {
        setState(() => _isCheckingSession = false);
      }
    }
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint("⚠️ Firebase sign-out error: $e");
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
        
        if (data["firebaseToken"] != null) {
          try {
            await FirebaseAuth.instance.signInWithCustomToken(data["firebaseToken"]);
          } catch (e) {
            debugPrint("❌ Firebase sign-in failed: $e");
          }
        }

        final driverId = data["user"]["_id"];
        final isNewUser = data["newUser"] == true;
        final docsApproved = data["docsApproved"] == true;
        
        String vehicleType = '';
        
        if (data["user"]["vehicleType"] != null) {
          vehicleType = data["user"]["vehicleType"].toString().toLowerCase().trim();
        }

        final prefs = await SharedPreferences.getInstance();
        
        await prefs.setString("driverId", driverId);
        await prefs.setString("phoneNumber", rawPhone);
        await prefs.setString("vehicleType", vehicleType);
        await prefs.setBool("isLoggedIn", true);
        await prefs.setInt("loginTimestamp", DateTime.now().millisecondsSinceEpoch);
        await prefs.setString("lastLoginResponse", jsonEncode(data));

        if (isNewUser) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DriverDocumentUploadPage(driverId: driverId),
            ),
          );
        } else if (docsApproved) {
          if (vehicleType.isEmpty) {
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
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DocumentsReviewPage(driverId: driverId),
            ),
          );
        }
      } else {
        final errorData = jsonDecode(response.body);
        _showMessage(
          errorData['message'] ?? "Login failed. Invalid OTP?",
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      setState(() => _isLoading = false);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppColors.background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text("Verifying...", style: AppTextStyles.body1),
              const SizedBox(height: 8),
              Text("Please wait", style: AppTextStyles.caption),
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
        content: Row(
          children: [
            Icon(
              isError ? Icons.error : Icons.check_circle,
              color: AppColors.onPrimary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Checking session...',
                style: AppTextStyles.body1,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo/Icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.local_taxi,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              Center(
                child: Text(
                  'Driver Login',
                  style: AppTextStyles.heading1.copyWith(fontSize: 28),
                ),
              ),
              
              const SizedBox(height: 8),
              
              Center(
                child: Text(
                  'Welcome back! Please login to continue',
                  style: AppTextStyles.body2,
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 48),
              
              // Phone Number Input
              Text(
                'Mobile Number',
                style: AppTextStyles.heading3.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 12),
              
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.onSurface.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  enabled: !_codeSent && !_isLoading,
                  style: AppTextStyles.body1,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    prefixIcon: Container(
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.phone,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    prefixText: '+91 ',
                    prefixStyle: AppTextStyles.body1.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: '9876543210',
                    hintStyle: AppTextStyles.body2,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    counterText: '',
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // OTP Input (conditional)
              if (_codeSent) ...[
                Text(
                  'Enter OTP',
                  style: AppTextStyles.heading3.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 12),
                
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.onSurface.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _otpController,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !_isLoading,
                    style: AppTextStyles.body1.copyWith(
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(6),
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.lock,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      hintText: '000000',
                      hintStyle: AppTextStyles.body2.copyWith(
                        letterSpacing: 8,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _verifyOTPAndLogin(),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _codeSent = false),
                      icon: const Icon(Icons.edit, size: 18),
                      label: Text(
                        'Change Number',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isLoading ? null : _resendOTP,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        'Resend OTP',
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
              ],
              
              const SizedBox(height: 32),
              
              // Main Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 3,
                    shadowColor: AppColors.primary.withOpacity(0.3),
                  ),
                  onPressed: _isLoading 
                      ? null 
                      : (_codeSent ? _verifyOTPAndLogin : _sendOTP),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.onPrimary,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _codeSent ? Icons.verified_user : Icons.send,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _codeSent ? 'Verify & Login' : 'Send OTP',
                              style: AppTextStyles.button,
                            ),
                          ],
                        ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Info box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter your registered mobile number to receive OTP',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
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