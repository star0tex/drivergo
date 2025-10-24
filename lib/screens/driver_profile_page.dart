import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drivergoo/screens/driver_login_page.dart';

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
}

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
        color: AppColors.onSurface,
      );
}

class DriverProfilePage extends StatefulWidget {
  final String driverId;

  const DriverProfilePage({Key? key, required this.driverId}) : super(key: key);

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final String backendUrl = "https://7668d252ef1d.ngrok-free.app";
  
  bool isLoading = true;
  Map<String, dynamic>? driverData;
  List<Map<String, dynamic>> documents = [];
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDriverProfile();
  }

  Future<void> _fetchDriverProfile() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Get Firebase token
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        throw Exception("Authentication failed");
      }

      // Fetch driver profile
      final profileResponse = await http.get(
        Uri.parse('$backendUrl/api/driver/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Fetch documents
      final docsResponse = await http.get(
        Uri.parse('$backendUrl/api/driver/documents/${widget.driverId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (profileResponse.statusCode == 200) {
        final profileData = jsonDecode(profileResponse.body);
        
        List<Map<String, dynamic>> docsList = [];
        if (docsResponse.statusCode == 200) {
          final docsData = jsonDecode(docsResponse.body);
          docsList = List<Map<String, dynamic>>.from(docsData['docs'] ?? []);
        }

        setState(() {
          driverData = profileData['driver'];
          documents = docsList;
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load profile");
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toString();
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'verified':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'verified':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }

  String _getVehicleEmoji(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'bike':
        return '🏍️';
      case 'auto':
        return '🛺';
      case 'car':
        return '🚗';
      default:
        return '🚕';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // App Bar with Profile Header
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.primary,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: AppColors.onPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withOpacity(0.8),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 60),
                          // Profile Photo
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.onPrimary,
                                width: 4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 58,
                              backgroundColor: AppColors.surface,
                              backgroundImage: driverData?['photoUrl'] != null &&
                                      driverData!['photoUrl'].toString().isNotEmpty
                                  ? NetworkImage(driverData!['photoUrl'])
                                  : null,
                              child: driverData?['photoUrl'] == null ||
                                      driverData!['photoUrl'].toString().isEmpty
                                  ? Icon(
                                      Icons.person,
                                      size: 60,
                                      color: AppColors.onSurfaceSecondary,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Name
                          Text(
                            driverData?['name'] ?? 'Driver Name',
                            style: AppTextStyles.heading2.copyWith(
                              color: AppColors.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Rating
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${driverData?['rating'] ?? 5.0}',
                                style: AppTextStyles.body1.copyWith(
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${driverData?['totalTrips'] ?? 0} trips)',
                                style: AppTextStyles.body2.copyWith(
                                  color: AppColors.onPrimary.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: isLoading
                ? const SizedBox()
                : errorMessage != null
                    ? _buildErrorWidget()
                    : _buildProfileContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            'Failed to load profile',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage ?? 'Unknown error',
            style: AppTextStyles.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchDriverProfile,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Personal Information Card
          _buildSectionCard(
            title: 'Personal Information',
            icon: Icons.person_outline,
            children: [
              _buildInfoRow(
                Icons.phone,
                'Phone Number',
                driverData?['phone'] ?? 'Not available',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.email_outlined,
                'Email',
                driverData?['email'] ?? 'Not provided',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.fingerprint,
                'Driver ID',
                widget.driverId,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Vehicle Information Card
          _buildSectionCard(
            title: 'Vehicle Information',
            icon: Icons.directions_car_outlined,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getVehicleEmoji(driverData?['vehicleType'] ?? 'bike'),
                      style: const TextStyle(fontSize: 32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle Type',
                          style: AppTextStyles.caption,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (driverData?['vehicleType'] ?? 'Not specified')
                              .toUpperCase(),
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (driverData?['vehicleType']?.toLowerCase() == 'car') ...[
                const SizedBox(height: 12),
                Divider(color: AppColors.divider),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.route,
                  'Long Distance Trips',
                  driverData?['acceptsLongTrips'] == true ? 'Enabled' : 'Disabled',
                  valueColor: driverData?['acceptsLongTrips'] == true
                      ? AppColors.success
                      : AppColors.onSurfaceSecondary,
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Statistics Card
          _buildSectionCard(
            title: 'Statistics',
            icon: Icons.bar_chart,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatBox(
                      'Total Trips',
                      '${driverData?['totalTrips'] ?? 0}',
                      Icons.local_taxi,
                      AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatBox(
                      'Rating',
                      '${driverData?['rating'] ?? 5.0}',
                      Icons.star,
                      Colors.amber,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Documents Section
          Text(
            'Documents',
            style: AppTextStyles.heading3,
          ),
          const SizedBox(height: 12),

          if (documents.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 48,
                      color: AppColors.onSurfaceTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No documents uploaded',
                      style: AppTextStyles.body2,
                    ),
                  ],
                ),
              ),
            )
          else
            ...documents.map((doc) => _buildDocumentCard(doc)).toList(),

          const SizedBox(height: 24),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 24),
                const SizedBox(width: 12),
                Text(title, style: AppTextStyles.heading3),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.onSurfaceSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.body1.copyWith(
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTextStyles.heading2.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(Map<String, dynamic> doc) {
    final status = doc['status']?.toString() ?? 'pending';
    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getStatusIcon(status),
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc['docType']?.toString().toUpperCase() ?? 'Document',
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 4),
                Text(
                  status.toUpperCase(),
                  style: AppTextStyles.caption.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 16,
            color: AppColors.onSurfaceTertiary,
          ),
        ],
      ),
    );
  }

 void _showLogoutDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(Icons.logout, color: AppColors.error),
          const SizedBox(width: 12),
          Text('Logout', style: AppTextStyles.heading3),
        ],
      ),
      content: Text(
        'Are you sure you want to logout?',
        style: AppTextStyles.body1,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: AppTextStyles.button.copyWith(
              color: AppColors.onSurfaceSecondary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            try {
              // Close the dialog first
              Navigator.pop(context);
              
              // Show loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          "Logging out...",
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              
              // Clear all session data from SharedPreferences
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // This clears everything
              
              print("✅ SharedPreferences cleared");
              
              // Sign out from Firebase
              try {
                await FirebaseAuth.instance.signOut();
                print("✅ Firebase signed out");
              } catch (e) {
                print("⚠️ Firebase sign-out error: $e");
              }
              
              // Small delay to show the loading indicator
              await Future.delayed(const Duration(milliseconds: 500));
              
              // Close loading dialog and navigate to login page
              if (mounted) {
                // Pop the loading dialog
                Navigator.pop(context);
                
                // Navigate to login page and remove all previous routes
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverLoginPage(),
                  ),
                  (route) => false, // Remove all previous routes
                );
                
                print("✅ Navigated to login page");
              }
            } catch (e) {
              print("❌ Logout error: $e");
              
              // Close loading dialog if still open
              if (mounted) {
                Navigator.pop(context);
                
                // Show error message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Logout failed: ${e.toString()}'),
                    backgroundColor: Colors.red[600],
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: AppColors.onPrimary,
          ),
          child: Text(
            'Logout',
            style: AppTextStyles.button.copyWith(
              color: AppColors.onPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}}