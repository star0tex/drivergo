import 'dart:convert';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Theme classes remain the same...
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

class DocumentsReviewPage extends StatefulWidget {
  final String? driverId;

  const DocumentsReviewPage({super.key, this.driverId});

  @override
  State<DocumentsReviewPage> createState() => _DocumentsReviewPageState();
}

class _DocumentsReviewPageState extends State<DocumentsReviewPage> {
  bool isLoading = true;
  bool allDocsApproved = false;
  bool allDocsUploaded = false;
  List<Map<String, dynamic>> uploadedDocuments = [];
  List<String> missingDocuments = [];
  String? errorMessage;
  String? vehicleType;
  final String backendUrl = "https://7668d252ef1d.ngrok-free.app";

  // Required documents per vehicle type
  final Map<String, List<String>> requiredDocsByVehicle = {
    'bike': ['license', 'rc', 'pan', 'aadhaar'],
    'auto': ['license', 'rc', 'pan', 'aadhaar', 'fitnessCertificate'],
    'car': ['license', 'rc', 'pan', 'aadhaar', 'fitnessCertificate', 'permit', 'insurance'],
  };

  // Document display names
  final Map<String, String> docDisplayNames = {
    'license': 'Driving License',
    'aadhaar': 'Aadhaar Card',
    'pan': 'PAN Card',
    'rc': 'Vehicle RC',
    'permit': 'Auto Permit',
    'insurance': 'Insurance',
    'fitnessCertificate': 'Fitness Certificate',
  };

  Future<String?> getToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken(true);
      }
      return null;
    } catch (e) {
      print("❌ Error getting token: $e");
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadVehicleTypeAndFetchDocuments();
  }

  Future<void> _loadVehicleTypeAndFetchDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    vehicleType = prefs.getString('vehicleType')?.toLowerCase();
    
    if (vehicleType == null || vehicleType!.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = "Vehicle type not found. Please complete registration.";
      });
      return;
    }
    
    print("📋 Vehicle Type: $vehicleType");
    _fetchDriverDocuments();
  }

  Future<void> _fetchDriverDocuments() async {
    if (widget.driverId == null) {
      setState(() {
        isLoading = false;
        errorMessage = "Driver ID is missing";
      });
      return;
    }

    try {
      final token = await getToken();
      if (token == null) {
        setState(() {
          isLoading = false;
          errorMessage = "Authentication failed. Please login again.";
        });
        return;
      }

      print("🔍 Fetching documents for driver: ${widget.driverId}");

      final response = await http.get(
        Uri.parse('$backendUrl/api/driver/documents/${widget.driverId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print("📊 Documents API Response: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
            final backendVehicleType = data['vehicleType']?.toString().toLowerCase();
    if (backendVehicleType != null && backendVehicleType.isNotEmpty) {
      vehicleType = backendVehicleType;
      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('vehicleType', vehicleType!);
    }
    
        if (data.containsKey('message') && 
            data['message'].toString().toLowerCase().contains('no documents')) {
          _handleNoDocuments();
          return;
        }
        
        final docs = List<Map<String, dynamic>>.from(data["docs"] ?? []);
        
        if (docs.isEmpty) {
          _handleNoDocuments();
          return;
        }

        _analyzeDocuments(docs);

      } else if (response.statusCode == 404) {
        _handleNoDocuments();
      } else {
        final errorData = json.decode(response.body);
        setState(() {
          isLoading = false;
          errorMessage = errorData['message'] ?? "Failed to fetch documents";
        });
      }
    } catch (e) {
      print("❌ Error fetching documents: $e");
      setState(() {
        isLoading = false;
        errorMessage = "Connection error: $e";
      });
    }
  }

  void _handleNoDocuments() {
    final required = requiredDocsByVehicle[vehicleType] ?? [];
    setState(() {
      uploadedDocuments = [];
      missingDocuments = required;
      allDocsUploaded = false;
      allDocsApproved = false;
      isLoading = false;
      errorMessage = null;
    });
  }

  void _analyzeDocuments(List<Map<String, dynamic>> docs) {
    print("");
    print("=" * 70);
    print("📋 ANALYZING DOCUMENTS");
    print("=" * 70);
    
    final requiredDocs = requiredDocsByVehicle[vehicleType] ?? [];
    print("   Required: $requiredDocs");
    
    final uploadedDocTypes = docs
        .map((doc) => doc['docType']?.toString().toLowerCase())
        .where((type) => type != null)
        .toSet();
    
    print("   Uploaded: $uploadedDocTypes");
    
    final missing = requiredDocs
        .where((docType) => !uploadedDocTypes.contains(docType))
        .toList();
    
    print("   Missing: $missing");
    
    final allApproved = docs.isNotEmpty &&
        docs.every((doc) {
          final status = doc['status']?.toString().toLowerCase();
          return status == 'approved' || status == 'verified';
        });
    
    print("   All Approved: $allApproved");
    print("=" * 70);
    print("");
    
    setState(() {
      uploadedDocuments = docs;
      missingDocuments = missing;
      allDocsUploaded = missing.isEmpty;
      allDocsApproved = allApproved && allDocsUploaded;
      isLoading = false;
      errorMessage = null;
    });
  }

  void _retryFetch() {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    _fetchDriverDocuments();
  }

  void _goToDocumentUpload() async {
    // Save current state before navigating
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('uploadedDocTypes', 
      uploadedDocuments.map((doc) => doc['docType'].toString().toLowerCase()).toList()
    );
    
    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDocumentUploadPage(
          driverId: widget.driverId!,
          uploadedDocTypes: uploadedDocuments
              .map((doc) => doc['docType'].toString().toLowerCase())
              .toList(),
        ),
      ),
    );
    
    // Refresh documents after returning
    if (result == true && mounted) {
      _fetchDriverDocuments();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return AppColors.success;
      case "rejected":
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return Icons.check_circle;
      case "rejected":
        return Icons.cancel;
      default:
        return Icons.hourglass_empty;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case "approved":
      case "verified":
        return "Approved";
      case "rejected":
        return "Rejected";
      default:
        return "Pending Review";
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevent back navigation if not all approved
        if (!allDocsApproved) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please complete document verification to continue'),
              backgroundColor: AppColors.warning,
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            "Documents Review",
            style: AppTextStyles.heading3.copyWith(color: AppColors.onPrimary),
          ),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _retryFetch,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: SafeArea(
          child: isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Loading your documents...",
                        style: AppTextStyles.body1,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await _fetchDriverDocuments();
                  },
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.description,
                                  size: 60,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Document Verification",
                                style: AppTextStyles.heading2,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.directions_car,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      vehicleType?.toUpperCase() ?? 'Unknown',
                                      style: AppTextStyles.body1.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Progress Summary Card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: allDocsApproved
                                  ? [
                                      AppColors.success,
                                      AppColors.success.withOpacity(0.8),
                                    ]
                                  : allDocsUploaded
                                      ? [
                                          AppColors.warning,
                                          AppColors.warning.withOpacity(0.8),
                                        ]
                                      : [
                                          AppColors.error.withOpacity(0.7),
                                          AppColors.error.withOpacity(0.5),
                                        ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: (allDocsApproved
                                        ? AppColors.success
                                        : allDocsUploaded
                                            ? AppColors.warning
                                            : AppColors.error)
                                    .withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    allDocsApproved
                                        ? Icons.verified
                                        : allDocsUploaded
                                            ? Icons.pending_actions
                                            : Icons.warning_amber_rounded,
                                    color: AppColors.onPrimary,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Verification Status",
                                          style: AppTextStyles.caption.copyWith(
                                            color: AppColors.onPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          allDocsApproved
                                              ? "All Documents Approved"
                                              : allDocsUploaded
                                                  ? "Under Review"
                                                  : "Incomplete Documents",
                                          style: AppTextStyles.heading3.copyWith(
                                            color: AppColors.onPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatusMetric(
                                      "Uploaded",
                                      "${uploadedDocuments.length}",
                                      Icons.upload_file,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    _buildStatusMetric(
                                      "Missing",
                                      "${missingDocuments.length}",
                                      Icons.error_outline,
                                    ),
                                    Container(
                                      width: 1,
                                      height: 30,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                    _buildStatusMetric(
                                      "Required",
                                      "${requiredDocsByVehicle[vehicleType]?.length ?? 0}",
                                      Icons.assignment,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Missing Documents Alert
                        if (missingDocuments.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.error,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "Missing Documents (${missingDocuments.length})",
                                        style: AppTextStyles.heading3.copyWith(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Please upload the following documents to complete verification:",
                                  style: AppTextStyles.body2.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...missingDocuments.map((docType) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.circle,
                                          size: 8,
                                          color: AppColors.error,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          docDisplayNames[docType] ?? docType,
                                          style: AppTextStyles.body1.copyWith(
                                            color: AppColors.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _goToDocumentUpload,
                                    icon: const Icon(Icons.upload_file),
                                    label: Text(
                                      "Continue Upload (${missingDocuments.length} remaining)",
                                      style: AppTextStyles.button.copyWith(
                                        color: AppColors.onPrimary,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.error,
                                      foregroundColor: AppColors.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Uploaded Documents Section
                        if (uploadedDocuments.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Uploaded Documents",
                                style: AppTextStyles.heading3,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "${uploadedDocuments.length} docs",
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: uploadedDocuments.length,
                            itemBuilder: (context, index) {
                              final doc = uploadedDocuments[index];
                              final status = doc['status']?.toString() ?? 'pending';
                              final docType = doc['docType']?.toString() ?? 'unknown';
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _getStatusColor(status).withOpacity(0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.onSurface.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getStatusIcon(status),
                                        color: _getStatusColor(status),
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            docDisplayNames[docType.toLowerCase()] ??
                                                docType.toUpperCase(),
                                            style: AppTextStyles.body1,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _getStatusText(status),
                                            style: AppTextStyles.body2.copyWith(
                                              color: _getStatusColor(status),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: _getStatusColor(status),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 32),
                        ],

                        // Action Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: allDocsApproved
                                ? () {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DriverDashboardPage(
                                          driverId: widget.driverId!,
                                          vehicleType: vehicleType ?? 'bike',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            icon: Icon(
                              allDocsApproved
                                  ? Icons.dashboard
                                  : Icons.hourglass_empty,
                              size: 24,
                            ),
                            label: Text(
                              allDocsApproved
                                  ? "Go to Dashboard"
                                  : allDocsUploaded
                                      ? "Waiting for Approval"
                                      : "Complete Document Upload",
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.onPrimary,
                                fontSize: 18,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: allDocsApproved
                                  ? AppColors.success
                                  : AppColors.onSurfaceSecondary,
                              foregroundColor: AppColors.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: allDocsApproved ? 4 : 0,
                            ),
                          ),
                        ),

                        if (!allDocsApproved) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    allDocsUploaded
                                        ? "Your documents are being reviewed. You'll be notified once approved."
                                        : "Upload all required documents to proceed with verification.",
                                    style: AppTextStyles.body2.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatusMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.heading3.copyWith(
            color: Colors.white,
            fontSize: 20,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withOpacity(0.9),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}