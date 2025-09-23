import 'dart:convert';
import 'package:drivergoo/screens/driver_dashboard_page.dart';
import 'package:drivergoo/screens/driver_details_page.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

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
  final String backendUrl = "http://192.168.1.28:5002";

  Future<String?> getToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken();
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
        
        // Check if the response contains a "message" about no documents
        if (data.containsKey('message') && data['message'].toString().toLowerCase().contains('no documents')) {
          setState(() {
            documents = [];
            isApproved = false;
            isLoading = false;
            errorMessage = "No documents uploaded yet. Please complete document upload.";
          });
          return;
        }
        
        // ✅ FIX: Check if response has "docs" array or if it's empty
        final docs = List<Map<String, dynamic>>.from(data["docs"] ?? []);
        
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

        // Debug: Print each document's status
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
        // Handle other error responses that might contain the "no documents" message
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
    switch (status?.toLowerCase()) {
      case "approved":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status?.toLowerCase()) {
      case "approved":
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
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.blueAccent))
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      "Documents Review",
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                    ),

                    const SizedBox(height: 20),

                    // Error message if any
                    if (errorMessage != null)
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  color: Colors.orange[800],
                                  size: 40,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  errorMessage!,
                                  style: TextStyle(
                                    color: Colors.orange[800],
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _retryFetch,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                      child: const Text("Retry", style: TextStyle(color: Colors.white)),
                                    ),
                                    ElevatedButton(
                                      onPressed: _goToDocumentUpload,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      child: const Text("Upload Documents", style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),

                    if (errorMessage == null && documents.isNotEmpty) ...[
                      // Driver status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Status:",
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black.withOpacity(0.7),
                            ),
                          ),
                          Chip(
                            label: Text(
                              isApproved ? "Approved" : "Pending Review",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor:
                                isApproved ? Colors.green : Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Documents section
                      Text(
                        "Uploaded Documents",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Expanded(
                        child: ListView.builder(
                          itemCount: documents.length,
                          itemBuilder: (context, index) {
                            final doc = documents[index];
                            final status = doc['status']?.toString() ?? 'pending';
                            
                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 3,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ListTile(
                                leading: Icon(
                                  _getStatusIcon(status),
                                  color: _getStatusColor(status),
                                  size: 32,
                                ),
                                title: Text(
                                  doc['docType']?.toString().toUpperCase() ?? "Unknown Document",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  _getStatusText(status),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                trailing: Icon(
                                  Icons.description,
                                  color: Colors.blue.shade300,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Action button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isApproved
                              ? () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DriverDashboardPage(
                                        driverId: widget.driverId!,
                                        vehicleType: '', // You might want to pass this from backend
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isApproved ? Colors.green : Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            isApproved ? "Go to Dashboard" : "Waiting for Approval",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}