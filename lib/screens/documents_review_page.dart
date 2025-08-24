import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class DocumentsReviewPage extends StatefulWidget {
  final String? driverId;  // <- make optional

  const DocumentsReviewPage({super.key, this.driverId});

  @override
  State<DocumentsReviewPage> createState() => _DocumentsReviewPageState();
}
class _DocumentsReviewPageState extends State<DocumentsReviewPage> {
  late IO.Socket socket;
  List<Map<String, dynamic>> driverDocs = [];
  bool allApproved = false;
  String backendUrl = "http://192.168.1.16:5002";

  @override
  void initState() {
    super.initState();
    _fetchDocs();
    _initSocket();         // ✅ then listen for updates
  }

  Future<void> _fetchDocs() async {
  try {
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    final response = await http.get(
      Uri.parse("$backendUrl/api/driver/documents"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        driverDocs = List<Map<String, dynamic>>.from(data["docs"]);
        allApproved = driverDocs.isNotEmpty &&
            driverDocs.every((doc) => doc["status"] == "approved");
      });
    } else {
      print("❌ Failed to fetch docs: ${response.body}");
    }
  } catch (e) {
    print("❌ Error fetching docs: $e");
  }
}


  void _initSocket() async {
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();

    socket = IO.io(
      backendUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({"Authorization": "Bearer $token"}) // ✅ auth on socket
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print("✅ Connected to socket server");
      socket.emit("driver:register_doc_status", {}); 
      // backend extracts driverId from token
    });

    socket.on("driver:all_docs_status", (data) {
      print("📩 Full docs list: $data");
      setState(() {
        driverDocs = List<Map<String, dynamic>>.from(data["docs"]);
        allApproved = driverDocs.isNotEmpty &&
            driverDocs.every((doc) => doc["status"] == "approved");
      });
    });

    socket.on("driver:doc_status_update", (data) {
      print("📩 Doc status update: $data");
      setState(() {
        final index =
            driverDocs.indexWhere((doc) => doc["id"] == data["docId"]);
        if (index != -1) {
          driverDocs[index]["status"] = data["status"];
        } else {
          driverDocs.add({
            "id": data["docId"],
            "type": data["docType"],
            "side": data["docSide"],
            "status": data["status"],
          });
        }
        allApproved = driverDocs.isNotEmpty &&
            driverDocs.every((d) => d["status"] == "approved");
      });
    });

    socket.onDisconnect((_) {
      print("❌ Socket disconnected");
    });
  }

  @override
  void dispose() {
    socket.disconnect();
    super.dispose();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "approved":
        return Colors.green;
      case "rejected":
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "approved":
        return Icons.check_circle;
      case "rejected":
        return Icons.cancel;
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Documents Review"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: driverDocs.isEmpty
            ? const Center(
                child: Text(
                  "No documents uploaded yet.",
                  style: TextStyle(fontSize: 16),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: driverDocs.length,
                      itemBuilder: (context, index) {
                        final doc = driverDocs[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: Icon(
                              _getStatusIcon(doc["status"]),
                              color: _getStatusColor(doc["status"]),
                            ),
                            title: Text("${doc["type"]} (${doc["side"]})"),
                            subtitle: Text("Status: ${doc["status"]}"),
                          ),
                        );
                      },
                    ),
                  ),
                  if (allApproved)
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(
                            context, "/driverDashboard");
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("Go to Dashboard"),
                    ),
                ],
              ),
      ),
    );
  }
}
