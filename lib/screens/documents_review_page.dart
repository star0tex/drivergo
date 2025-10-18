import 'dart:convert';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

// ✅ ADD THEME CLASSES
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
  bool isApproved = false;
  List<Map<String, dynamic>> documents = [];
  String? errorMessage;
  String? vehicleType;
  final String backendUrl = "https://e4784d33af60.ngrok-free.app";

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

      print("🔍 Documents API Response: ${response.statusCode}");
      print("🔍 Documents API Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data.containsKey('message') && data['message'].toString().toLowerCase().contains('no documents')) {
          setState(() {
            documents = [];
            isApproved = false;
            isLoading = false;
            errorMessage = "No documents uploaded yet. Please complete document upload.";
          });
          return;
        }
        
        final docs = List<Map<String, dynamic>>.from(data["docs"] ?? []);
        
        // ✅ Get vehicle type from response
        vehicleType = data["vehicleType"]?.toString();
        
        print("📊 Found ${docs.length} documents");
        
        if (docs.isEmpty) {
          setState(() {
            documents = [];
            isApproved = false;
            isLoading = false;
            errorMessage = "No documents uploaded yet. Please complete document upload.";
          });
          return;
        }

        for (var doc in docs) {
          print("📄 Document: ${doc['docType']} - Status: ${doc['status']}");
        }

        setState(() {
          documents = docs;
          
          isApproved = docs.isNotEmpty &&
            docs.every((doc) {
              final status = doc['status']?.toString().toLowerCase();
              return status == 'approved' || status == 'verified';
            });

          isLoading = false;
          errorMessage = null;
        });

        print("✅ All approved: $isApproved");

      } else if (response.statusCode == 401) {
        setState(() {
          isLoading = false;
          errorMessage = "Authentication failed. Please login again.";
        });
      } else if (response.statusCode == 404) {
        setState(() {
          documents = [];
          isApproved = false;
          isLoading = false;
          errorMessage = "No documents found. Please upload your documents first.";
        });
      } else {
        final errorData = json.decode(response.body);
        final errorMsg = errorData['message'] ?? "Failed to fetch documents";
        
        setState(() {
          isLoading = false;
          errorMessage = errorMsg;
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

  void _retryFetch() {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    _fetchDriverDocuments();
  }

  void _goToDocumentUpload() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DriverDocumentUploadPage(driverId: widget.driverId!),
      ),
    );
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
    return Scaffold(
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
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Icon & Title
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
                          Text(
                            "Review your uploaded documents",
                            style: AppTextStyles.body2,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Error message if any
                    if (errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.warning.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.warning,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              errorMessage!,
                              style: AppTextStyles.body1.copyWith(
                                color: AppColors.warning,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _retryFetch,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(
                                      "Retry",
                                      style: AppTextStyles.button,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: BorderSide(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _goToDocumentUpload,
                                    icon: const Icon(Icons.upload_file),
                                    label: Text(
                                      "Upload",
                                      style: AppTextStyles.button.copyWith(
                                        color: AppColors.onPrimary,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: AppColors.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    if (errorMessage == null && documents.isNotEmpty) ...[
                      // Status Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isApproved
                                ? [
                                    AppColors.success,
                                    AppColors.success.withOpacity(0.8),
                                  ]
                                : [
                                    AppColors.warning,
                                    AppColors.warning.withOpacity(0.8),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (isApproved
                                      ? AppColors.success
                                      : AppColors.warning)
                                  .withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isApproved
                                  ? Icons.verified
                                  : Icons.pending_actions,
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
                                    isApproved
                                        ? "All Documents Approved"
                                        : "Under Review",
                                    style: AppTextStyles.heading3.copyWith(
                                      color: AppColors.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Documents section
                      Text(
                        "Uploaded Documents (${documents.length})",
                        style: AppTextStyles.heading3,
                      ),
                      const SizedBox(height: 16),

                      // Documents list
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: documents.length,
                        itemBuilder: (context, index) {
                          final doc = documents[index];
                          final status = doc['status']?.toString() ?? 'pending';
                          
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
                                        doc['docType']
                                                ?.toString()
                                                .toUpperCase() ??
                                            "Unknown Document",
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
                                  Icons.arrow_forward_ios,
                                  color: AppColors.onSurfaceTertiary,
                                  size: 16,
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 32),

                      // Action button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isApproved
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
                            isApproved
                                ? Icons.dashboard
                                : Icons.hourglass_empty,
                            size: 24,
                          ),
                          label: Text(
                            isApproved
                                ? "Go to Dashboard"
                                : "Waiting for Approval",
                            style: AppTextStyles.button.copyWith(
                              color: AppColors.onPrimary,
                              fontSize: 18,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isApproved
                                ? AppColors.success
                                : AppColors.onSurfaceSecondary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: isApproved ? 4 : 0,
                          ),
                        ),
                      ),

                      if (!isApproved) ...[
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
                                  "Your documents are being reviewed. You'll be notified once approved.",
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
                  ],
                ),
              ),
      ),
    );
  }
}