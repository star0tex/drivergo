import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

// Theme Classes (reuse from your dashboard)
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

class DriverRideHistoryPage extends StatefulWidget {
  final String driverId;

  const DriverRideHistoryPage({
    Key? key,
    required this.driverId,
  }) : super(key: key);

  @override
  _DriverRideHistoryPageState createState() => _DriverRideHistoryPageState();
}

class _DriverRideHistoryPageState extends State<DriverRideHistoryPage> {
  final String apiBase = 'https://b23b44ae0c5e.ngrok-free.app';
  
  List<Map<String, dynamic>> rideHistory = [];
  bool isLoading = true;
  String selectedFilter = 'All'; // All, Today, Week, Month
  
  Map<String, dynamic>? summaryStats;

  @override
  void initState() {
    super.initState();
    _fetchRideHistory();
  }

  Future<void> _fetchRideHistory() async {
  setState(() => isLoading = true);
  
  try {
    print('📊 Fetching ride history for driver: ${widget.driverId}');
    
    final response = await http.get(
      Uri.parse('$apiBase/api/driver/ride-history/${widget.driverId}'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw Exception('Request timeout - please check your connection');
      },
    );

    print('📡 Response status: ${response.statusCode}');
    print('📄 Response body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      
      if (data['success']) {
        setState(() {
          rideHistory = List<Map<String, dynamic>>.from(data['rides'] ?? []);
          summaryStats = data['summary'];
          isLoading = false;
        });
        
        print('✅ Fetched ${rideHistory.length} rides');
        print('📈 Summary: Total Rides: ${summaryStats?['totalRides']}');
        print('💰 Total Earnings: ₹${summaryStats?['totalEarnings']}');
        
        // Show success message if rides found
        if (mounted && rideHistory.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Loaded ${rideHistory.length} rides'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to fetch ride history');
      }
    } else if (response.statusCode == 404) {
      throw Exception('Driver not found');
    } else if (response.statusCode == 500) {
      throw Exception('Server error - please try again later');
    } else {
      throw Exception('Failed to load rides (${response.statusCode})');
    }
  } on SocketException {
    setState(() => isLoading = false);
    if (mounted) {
      _showErrorSnackBar('No internet connection');
    }
  } on TimeoutException {
    setState(() => isLoading = false);
    if (mounted) {
      _showErrorSnackBar('Request timeout - please try again');
    }
  } catch (e) {
    print('❌ Error fetching ride history: $e');
    setState(() => isLoading = false);
    
    if (mounted) {
      _showErrorSnackBar('Failed to load rides: ${e.toString()}');
    }
  }
}

// Helper method to show error messages
void _showErrorSnackBar(String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'RETRY',
        textColor: Colors.white,
        onPressed: _fetchRideHistory,
      ),
    ),
  );
}
  List<Map<String, dynamic>> _getFilteredRides() {
  final now = DateTime.now();
  
  switch (selectedFilter) {
    case 'Today':
      return rideHistory.where((ride) {
        try {
          final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
          if (completedAtStr == null) return false;
          
          // Parse and convert to local time
          final rideDate = DateTime.parse(completedAtStr).toLocal();
          
          return rideDate.year == now.year &&
                 rideDate.month == now.month &&
                 rideDate.day == now.day;
        } catch (e) {
          print('⚠️ Error filtering ride: $e');
          return false;
        }
      }).toList();
      
    case 'Week':
      final weekAgo = now.subtract(const Duration(days: 7));
      return rideHistory.where((ride) {
        try {
          final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
          if (completedAtStr == null) return false;
          
          final rideDate = DateTime.parse(completedAtStr).toLocal();
          return rideDate.isAfter(weekAgo);
        } catch (e) {
          return false;
        }
      }).toList();
      
    case 'Month':
      return rideHistory.where((ride) {
        try {
          final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
          if (completedAtStr == null) return false;
          
          final rideDate = DateTime.parse(completedAtStr).toLocal();
          return rideDate.year == now.year && rideDate.month == now.month;
        } catch (e) {
          return false;
        }
      }).toList();
      
    default:
      return rideHistory;
  }
}
  Map<String, dynamic> _calculateFilteredStats(List<Map<String, dynamic>> rides) {
    double totalFares = 0;
    double totalCommission = 0;
    double totalEarnings = 0;
    
    for (var ride in rides) {
      final fare = (ride['fare'] ?? 0).toDouble();
      final commission = (ride['commission'] ?? 0).toDouble();
      final earning = (ride['driverEarning'] ?? 0).toDouble();
      
      totalFares += fare;
      totalCommission += commission;
      totalEarnings += earning;
    }
    
    return {
      'totalRides': rides.length,
      'totalFares': totalFares,
      'totalCommission': totalCommission,
      'totalEarnings': totalEarnings,
    };
  }

  @override
  Widget build(BuildContext context) {
    final filteredRides = _getFilteredRides();
    final stats = _calculateFilteredStats(filteredRides);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 1,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ride History',
          style: AppTextStyles.heading3,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _fetchRideHistory,
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchRideHistory,
              color: AppColors.primary,
              child: CustomScrollView(
                slivers: [
                  // Summary Stats Card
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildSummaryCard(stats),
                    ),
                  ),
                  
                  // Filter Chips
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildFilterChips(),
                    ),
                  ),
                  
                  // Ride Count Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '${filteredRides.length} ${filteredRides.length == 1 ? 'Ride' : 'Rides'}',
                        style: AppTextStyles.body2,
                      ),
                    ),
                  ),
                  
                  // Ride History List
                  filteredRides.isEmpty
                      ? SliverToBoxAdapter(
                          child: _buildEmptyState(),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _buildRideCard(filteredRides[index]);
                            },
                            childCount: filteredRides.length,
                          ),
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> stats) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Total Rides
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_taxi, color: AppColors.onPrimary, size: 24),
              const SizedBox(width: 8),
              Text(
                '${stats['totalRides']} Completed Rides',
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total Fares',
                  '₹${stats['totalFares'].toStringAsFixed(2)}',
                  Icons.payments,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: AppColors.onPrimary.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatItem(
                  'Commission',
                  '₹${stats['totalCommission'].toStringAsFixed(2)}',
                  Icons.percent,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Container(
            height: 1,
            color: AppColors.onPrimary.withOpacity(0.3),
          ),
          
          const SizedBox(height: 16),
          
          // Net Earnings
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_balance_wallet, 
                color: AppColors.onPrimary, 
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Net Earnings: ',
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.onPrimary.withOpacity(0.9),
                ),
              ),
              Text(
                '₹${stats['totalEarnings'].toStringAsFixed(2)}',
                style: AppTextStyles.heading2.copyWith(
                  color: AppColors.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.onPrimary.withOpacity(0.9), size: 20),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onPrimary.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTextStyles.body1.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Today', 'Week', 'Month'];
    
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  selectedFilter = filter;
                });
              },
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.primary,
              labelStyle: AppTextStyles.body2.copyWith(
                color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
  final fare = (ride['fare'] ?? 0).toDouble();
  final commission = (ride['commission'] ?? 0).toDouble();
  final driverEarning = (ride['driverEarning'] ?? 0).toDouble();
  final commissionPercent = (ride['commissionPercentage'] ?? 15).toInt();
  
  // ✅ FIX: Parse UTC time and convert to local timezone
  DateTime dateTime;
  try {
    final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
    if (completedAtStr != null) {
      // Parse as UTC and convert to local
      dateTime = DateTime.parse(completedAtStr).toLocal();
    } else {
      dateTime = DateTime.now();
    }
  } catch (e) {
    print('⚠️ Error parsing date: $e');
    dateTime = DateTime.now();
  }
  
  // ✅ Format in local timezone
  final formattedDate = DateFormat('MMM dd, yyyy').format(dateTime);
  final formattedTime = DateFormat('hh:mm a').format(dateTime);
  
  print('📅 Ride date: $formattedDate $formattedTime (Local)');
  
  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showRideDetails(ride),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Date & Time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today, 
                          size: 14, 
                          color: AppColors.onSurfaceSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(formattedDate, style: AppTextStyles.body2),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, 
                          size: 14, 
                          color: AppColors.onSurfaceSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(formattedTime, style: AppTextStyles.caption),
                      ],
                    ),
                  ],
                ),
                
                // Trip ID
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#${ride['tripId']?.toString().substring(0, 8) ?? 'N/A'}',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Route Info
            Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 30,
                      color: AppColors.divider,
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ride['pickup']?['address'] ?? 'Pickup Location',
                        style: AppTextStyles.body2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        ride['drop']?['address'] ?? 'Drop Location',
                        style: AppTextStyles.body2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Divider(color: AppColors.divider),
            
            const SizedBox(height: 12),
            
            // Fare Breakdown
            Column(
              children: [
                _buildFareRow('Trip Fare', fare, isBold: true),
                const SizedBox(height: 8),
                _buildFareRow(
                  'Commission ($commissionPercent%)',
                  commission,
                  isNegative: true,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your Earning',
                            style: AppTextStyles.body1.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '₹${driverEarning.toStringAsFixed(2)}',
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
  Widget _buildFareRow(
    String label,
    double amount, {
    bool isBold = false,
    bool isNegative = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold ? AppTextStyles.body1 : AppTextStyles.body2,
        ),
        Text(
          '${isNegative ? '-' : ''}₹${amount.toStringAsFixed(2)}',
          style: (isBold ? AppTextStyles.body1 : AppTextStyles.body2).copyWith(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 80,
              color: AppColors.onSurfaceTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No rides found',
              style: AppTextStyles.heading3,
            ),
            const SizedBox(height: 8),
            Text(
              'Your completed rides will appear here',
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showRideDetails(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRideDetailsSheet(ride),
    );
  }

 Widget _buildRideDetailsSheet(Map<String, dynamic> ride) {
  final fare = (ride['fare'] ?? 0).toDouble();
  final commission = (ride['commission'] ?? 0).toDouble();
  final driverEarning = (ride['driverEarning'] ?? 0).toDouble();
  final commissionPercent = (ride['commissionPercentage'] ?? 15).toInt();
  
  // ✅ FIX: Parse and convert to local time
  DateTime dateTime;
  try {
    final completedAtStr = ride['completedAt'] ?? ride['createdAt'];
    dateTime = completedAtStr != null 
        ? DateTime.parse(completedAtStr).toLocal()
        : DateTime.now();
  } catch (e) {
    print('⚠️ Error parsing date in details: $e');
    dateTime = DateTime.now();
  }
  
  final formattedDateTime = DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
  
  return DraggableScrollableSheet(
    initialChildSize: 0.7,
    minChildSize: 0.5,
    maxChildSize: 0.9,
    builder: (context, scrollController) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Title
            Row(
              children: [
                Icon(Icons.receipt_long, color: AppColors.primary),
                const SizedBox(width: 12),
                Text('Ride Details', style: AppTextStyles.heading2),
              ],
            ),
            
            const SizedBox(height: 8),
            Text(formattedDateTime, style: AppTextStyles.body2),
       
              const SizedBox(height: 24),
              
              // Route Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildDetailRow(
                      Icons.location_on,
                      'Pickup',
                      ride['pickup']?['address'] ?? 'N/A',
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      Icons.flag,
                      'Drop',
                      ride['drop']?['address'] ?? 'N/A',
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Fare Breakdown
              Text('Fare Breakdown', style: AppTextStyles.heading3),
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildFareRow('Base Fare', fare, isBold: true),
                    const SizedBox(height: 12),
                    _buildFareRow(
                      'Platform Commission ($commissionPercent%)',
                      commission,
                      isNegative: true,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: 12),
                    Divider(color: AppColors.divider),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Your Earning',
                          style: AppTextStyles.heading3,
                        ),
                        Text(
                          '₹${driverEarning.toStringAsFixed(2)}',
                          style: AppTextStyles.heading2.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Customer Info (if available)
              if (ride['customer'] != null) ...[
                Text('Customer Details', style: AppTextStyles.heading3),
                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: AppColors.primary.withOpacity(0.2),
                        child: Text(
                          (ride['customer']['name'] ?? 'C')[0].toUpperCase(),
                          style: AppTextStyles.heading3.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ride['customer']['name'] ?? 'Customer',
                              style: AppTextStyles.body1,
                            ),
                            if (ride['customer']['phone'] != null)
                              Text(
                                ride['customer']['phone'],
                                style: AppTextStyles.caption,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.onSurfaceSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: 4),
              Text(value, style: AppTextStyles.body1),
            ],
          ),
        ),
      ],
    );
  }
}