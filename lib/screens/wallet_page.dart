import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class WalletPage extends StatefulWidget {
  final String driverId;

  const WalletPage({Key? key, required this.driverId}) : super(key: key);

  @override
  _WalletPageState createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final String apiBase = 'https://cd4ec7060b0b.ngrok-free.app';
  
  Map<String, dynamic>? walletData;
  List<dynamic> transactions = [];
  List<dynamic> paymentProofs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
    _fetchPaymentProofs();
  }

  Future<void> _fetchWalletData() async {
    setState(() => isLoading = true);
    
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/wallet/${widget.driverId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            walletData = data['wallet'];
            transactions = data['recentTransactions'] ?? [];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching wallet: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchPaymentProofs() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/wallet/payment-proof/${widget.driverId}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            paymentProofs = data['proofs'] ?? [];
          });
        }
      }
    } catch (e) {
      print('Error fetching payment proofs: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          'My Wallet',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fetchWalletData();
              _fetchPaymentProofs();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchWalletData();
                await _fetchPaymentProofs();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWalletCard(),
                    const SizedBox(height: 24),
                    _buildStatsCards(),
                    
                    if (paymentProofs.any((p) => p['status'] == 'pending')) ...[
                      const SizedBox(height: 24),
                      _buildPendingPaymentsSection(),
                    ],
                    
                    const SizedBox(height: 24),
                    Text(
                      'Recent Transactions',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTransactionsList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildWalletCard() {
    final totalEarnings = walletData?['totalEarnings'] ?? 0.0;
    final pendingAmount = walletData?['pendingAmount'] ?? 0.0;
    final hasPendingProof = paymentProofs.any((p) => p['status'] == 'pending');
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Earnings',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Active',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '₹${totalEarnings.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending Commission',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${pendingAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.account_balance_wallet,
                      color: Colors.white70,
                      size: 40,
                    ),
                  ],
                ),
                
                if (pendingAmount > 0) ...[
                  const SizedBox(height: 16),
                  if (hasPendingProof)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pending, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Payment verification pending...',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _initiateUpiPayment(pendingAmount),
                        icon: const Icon(Icons.payment, size: 20),
                        label: Text(
                          'Pay ₹${pendingAmount.toStringAsFixed(2)} via UPI',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1565C0),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: Proper UPI payment that triggers native app picker
  Future<void> _initiateUpiPayment(double amount) async {
    const upiId = '8341132728@mbk';
    const payeeName = 'Platform Commission';
    final amountStr = amount.toStringAsFixed(2);
    final transactionNote = 'Commission Payment - Driver: ${widget.driverId}';
    final transactionRef = 'TXN${DateTime.now().millisecondsSinceEpoch}';

    // ✅ Proper UPI URL format that Android recognizes
    final upiUrl = 'upi://pay?'
        'pa=$upiId&'
        'pn=${Uri.encodeComponent(payeeName)}&'
        'am=$amountStr&'
        'cu=INR&'
        'tn=${Uri.encodeComponent(transactionNote)}&'
        'tr=$transactionRef';

    print('🔥 UPI URL: $upiUrl');

    try {
      final uri = Uri.parse(upiUrl);
      
      // ✅ This will trigger Android's native UPI app chooser
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        print('✅ UPI payment launched - Android will show app picker');
        
        // Wait for user to complete payment and return
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          // Show confirmation dialog
          _showPaymentConfirmationDialog(amount, transactionRef);
        }
      } else {
        print('⚠️ Could not launch UPI payment');
        _showManualPaymentDialog(upiId, amount);
      }
    } catch (e) {
      print('❌ Error launching UPI: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _showManualPaymentDialog(upiId, amount);
    }
  }

  // ✅ NEW: Ask if payment was completed
  void _showPaymentConfirmationDialog(double amount, String transactionRef) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Color(0xFF1565C0)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Payment Status',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Did you complete the payment of ₹${amount.toStringAsFixed(2)}?',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment cancelled')),
              );
            },
            child: Text('No', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showPaymentProofDialog(amount, transactionId: transactionRef);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Yes, I Paid', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ✅ Show payment proof dialog
  void _showPaymentProofDialog(
    double amount, {
    String? transactionId,
  }) {
    final TextEditingController transactionIdController = TextEditingController(
      text: transactionId ?? '',
    );
    String selectedApp = 'gpay';
    File? screenshotFile;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.receipt_long, color: Color(0xFF1565C0)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Submit Payment Proof',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Enter the 12-digit UPI transaction ID from your payment app',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                Text('UPI Transaction ID *', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: transactionIdController,
                  decoration: InputDecoration(
                    hintText: 'e.g., 123456789012',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                ),
                const SizedBox(height: 8),
                
                Text('Payment App Used', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedApp,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'gpay', child: Text('Google Pay')),
                    DropdownMenuItem(value: 'phonepe', child: Text('PhonePe')),
                    DropdownMenuItem(value: 'paytm', child: Text('Paytm')),
                    DropdownMenuItem(value: 'other', child: Text('Other UPI App')),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedApp = value!);
                  },
                ),
                const SizedBox(height: 16),
                
                Text('Screenshot (Optional)', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (screenshotFile != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Screenshot attached', style: GoogleFonts.poppins(fontSize: 12))),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => setDialogState(() => screenshotFile = null),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 80,
                      );
                      if (image != null) {
                        setDialogState(() => screenshotFile = File(image.path));
                      }
                    },
                    icon: const Icon(Icons.upload_file),
                    label: Text('Upload Screenshot', style: GoogleFonts.poppins()),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final txnId = transactionIdController.text.trim();
                if (txnId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter transaction ID')),
                  );
                  return;
                }
                
                if (txnId.length < 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Transaction ID must be at least 8 characters')),
                  );
                  return;
                }
                
                Navigator.pop(context);
                await _submitPaymentProof(amount, txnId, selectedApp, screenshotFile);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text('Submit Proof', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Submit payment proof to backend
  Future<void> _submitPaymentProof(
    double amount,
    String transactionId,
    String paymentApp,
    File? screenshot,
  ) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final uri = Uri.parse('$apiBase/api/wallet/submit-payment-proof');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['driverId'] = widget.driverId;
      request.fields['amount'] = amount.toString();
      request.fields['upiTransactionId'] = transactionId;
      request.fields['paymentApp'] = paymentApp;
      
      if (screenshot != null) {
        request.files.add(await http.MultipartFile.fromPath('screenshot', screenshot.path));
      }
      
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = jsonDecode(responseData);
      
      // Close loading dialog
      Navigator.pop(context);
      
      if (response.statusCode == 200 && data['success']) {
        await _fetchWalletData();
        await _fetchPaymentProofs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Payment proof submitted successfully!\nVerification will be completed within 24 hours.',
                    style: GoogleFonts.poppins(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        throw Exception(data['message'] ?? 'Submission failed');
      }
    } catch (e) {
      // Close loading dialog if still open
      if (Navigator.canPop(context)) Navigator.pop(context);
      
      print('❌ Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPendingPaymentsSection() {
    final pending = paymentProofs.where((p) => p['status'] == 'pending').toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pending Verifications',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...pending.map((proof) {
          final amount = proof['amount'] ?? 0.0;
          final transactionId = proof['upiTransactionId'] ?? '';
          final submittedAt = DateTime.parse(proof['submittedAt']);
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.pending, color: Colors.orange, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment of ₹${amount.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Txn: $transactionId',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Submitted: ${submittedAt.day}/${submittedAt.month}/${submittedAt.year}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Text(
                      'PENDING',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  void _showManualPaymentDialog(String upiId, double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.qr_code, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Pay Manually', style: GoogleFonts.poppins(fontSize: 18)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pay using any UPI app:', style: GoogleFonts.poppins()),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('UPI ID:', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                              const SizedBox(height: 4),
                              Text(upiId, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20, color: Colors.blue),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: upiId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('UPI ID copied to clipboard!')),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Amount:', style: GoogleFonts.poppins(fontSize: 14)),
                        Text('₹${amount.toStringAsFixed(2)}', 
                          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showPaymentProofDialog(amount);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text('I Paid', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalCommission = walletData?['totalCommission'] ?? 0.0;
    final totalEarnings = walletData?['totalEarnings'] ?? 0.0;
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Commission',
            '₹${totalCommission.toStringAsFixed(2)}',
            Icons.payments,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Net Earnings',
            '₹${totalEarnings.toStringAsFixed(2)}',
            Icons.trending_up,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 12),
          Text(title, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (transactions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
              const SizedBox(height: 16),
              Text('No transactions yet', style: GoogleFonts.poppins(color: Colors.grey[500], fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: transactions.map((transaction) {
        final type = transaction['type'];
        final amount = transaction['amount'] ?? 0.0;
        final description = transaction['description'] ?? '';
        final date = DateTime.parse(transaction['createdAt']);
        
        IconData icon;
        Color color;
        String prefix;
        
        if (type == 'credit') {
          icon = Icons.arrow_downward;
          color = Colors.green;
          prefix = '+';
        } else if (type == 'commission') {
          icon = Icons.percent;
          color = Colors.orange;
          prefix = '-';
        } else {
          icon = Icons.arrow_upward;
          color = Colors.red;
          prefix = '-';
        }
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Text(
                '$prefix₹${amount.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}