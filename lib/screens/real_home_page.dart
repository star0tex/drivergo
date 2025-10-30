import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

const String apiBase = 'https://b23b44ae0c5e.ngrok-free.app';

// --- COLOR PALETTE ---
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

// --- TYPOGRAPHY ---
class AppTextStyles {
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
}

class RideHistoryPage extends StatefulWidget {
  const RideHistoryPage({super.key});

  @override
  State<RideHistoryPage> createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allRides = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _customerId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCustomerIdAndFetchHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomerIdAndFetchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customerId = prefs.getString('customerId') ?? '';
      
      if (_customerId.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'User not logged in';
        });
        return;
      }

      await _fetchRideHistory();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading user data: $e';
      });
    }
  }

  Future<void> _fetchRideHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final url = Uri.parse('$apiBase/api/ride-history/$_customerId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data is List) {
          setState(() {
            _allRides = List<Map<String, dynamic>>.from(data);
            _isLoading = false;
          });
        } else if (data is Map && data.containsKey('rides')) {
          setState(() {
            _allRides = List<Map<String, dynamic>>.from(data['rides']);
            _isLoading = false;
          });
        } else {
          setState(() {
            _allRides = [];
            _isLoading = false;
          });
        }
        
        debugPrint('✅ Fetched ${_allRides.length} rides');
      } else if (response.statusCode == 404) {
        setState(() {
          _allRides = [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load ride history';
        });
      }
    } catch (e) {
      debugPrint('❌ Error fetching ride history: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error: $e';
      });
    }
  }

  List<Map<String, dynamic>> _filterRidesByType(String type) {
    if (type == 'city') {
      return _allRides.where((ride) {
        final vehicleType = ride['vehicleType']?.toString().toLowerCase() ?? '';
        return vehicleType == 'bike' || 
               vehicleType == 'auto' || 
               vehicleType == 'car' ||
               vehicleType == 'premium' ||
               vehicleType == 'xl';
      }).toList();
    } else if (type == 'intercity') {
      return _allRides.where((ride) {
        final vehicleType = ride['vehicleType']?.toString().toLowerCase() ?? '';
        return vehicleType == 'intercity' || vehicleType == 'cartrip';
      }).toList();
    } else if (type == 'parcel') {
      return _allRides.where((ride) {
        final vehicleType = ride['vehicleType']?.toString().toLowerCase() ?? '';
        return vehicleType == 'parcel';
      }).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Ride History', style: AppTextStyles.heading3.copyWith(color: Colors.white)),
        backgroundColor: AppColors.primary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: AppTextStyles.body1.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          unselectedLabelStyle: AppTextStyles.body2.copyWith(color: Colors.white70),
          tabs: const [
            Tab(text: 'City Ride'),
            Tab(text: 'Intercity'),
            Tab(text: 'Parcel'),
          ],
        ),
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _fetchRideHistory,
                  color: AppColors.primary,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      RideHistoryList(rides: _filterRidesByType('city'), type: 'city'),
                      RideHistoryList(rides: _filterRidesByType('intercity'), type: 'intercity'),
                      RideHistoryList(rides: _filterRidesByType('parcel'), type: 'parcel'),
                    ],
                  ),
                ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text('Loading ride history...', style: AppTextStyles.body2),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: AppTextStyles.heading3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              style: AppTextStyles.body2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchRideHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RideHistoryList extends StatelessWidget {
  final List<Map<String, dynamic>> rides;
  final String type;

  const RideHistoryList({
    super.key,
    required this.rides,
    required this.type,
  });

  String _formatDate(String? dateString) {
    try {
      if (dateString == null || dateString.isEmpty) return 'N/A';
      final date = DateTime.parse(dateString);
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (e) {
      return dateString ?? 'N/A';
    }
  }

  String _getVehicleIcon(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'bike':
        return '🏍️';
      case 'auto':
        return '🛺';
      case 'car':
        return '🚗';
      case 'premium':
        return '🚙';
      case 'xl':
        return '🚐';
      case 'parcel':
        return '📦';
      case 'intercity':
      case 'cartrip':
        return '🚗';
      default:
        return '🚕';
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return AppColors.onSurfaceSecondary;
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'ongoing':
        return AppColors.warning;
      default:
        return AppColors.onSurfaceSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (rides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  type == 'city' 
                      ? Icons.directions_car 
                      : type == 'parcel'
                          ? Icons.local_shipping
                          : Icons.map,
                  size: 64,
                  color: AppColors.onSurfaceTertiary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'No ${type == 'city' ? 'City Rides' : type == 'parcel' ? 'Parcels' : 'Intercity Trips'} Yet',
                style: AppTextStyles.heading3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your ride history will appear here',
                style: AppTextStyles.body2,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rides.length,
      itemBuilder: (context, index) {
        final ride = rides[index];
        return _RideHistoryCard(
          ride: ride,
          formatDate: _formatDate,
          getVehicleIcon: _getVehicleIcon,
          getStatusColor: _getStatusColor,
        );
      },
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final String Function(String?) formatDate;
  final String Function(String) getVehicleIcon;
  final Color Function(String?) getStatusColor;

  const _RideHistoryCard({
    required this.ride,
    required this.formatDate,
    required this.getVehicleIcon,
    required this.getStatusColor,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = ride['pickupLocation'] ?? ride['pickup']?['address'] ?? 'Unknown';
    final drop = ride['dropLocation'] ?? ride['drop']?['address'] ?? 'Unknown';
    final vehicleType = ride['vehicleType'] ?? 'N/A';
    final fare = ride['fare']?.toString() ?? '0';
    final dateTime = ride['dateTime'] ?? ride['createdAt'] ?? ride['timestamp'];
    final status = ride['status'] ?? 'Completed';
    final driverName = ride['driver']?['name'] ?? ride['driverName'] ?? 'N/A';
    final vehicleNumber = ride['driver']?['vehicleNumber'] ?? ride['vehicleNumber'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
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
          // Header with vehicle type and status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      getVehicleIcon(vehicleType),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      vehicleType.toUpperCase(),
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: getStatusColor(status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: getStatusColor(status)),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: AppTextStyles.caption.copyWith(
                      color: getStatusColor(status),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Trip details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pickup and Drop
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                        Container(
                          width: 2,
                          height: 40,
                          color: AppColors.divider,
                        ),
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
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
                            pickup,
                            style: AppTextStyles.body1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            drop,
                            style: AppTextStyles.body1.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 16),

                // Date, Fare, Driver info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.onSurfaceTertiary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  formatDate(dateTime),
                                  style: AppTextStyles.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.person, size: 14, color: AppColors.onSurfaceTertiary),
                              const SizedBox(width: 6),
                              Text(
                                driverName,
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.directions_car, size: 14, color: AppColors.onSurfaceTertiary),
                              const SizedBox(width: 6),
                              Text(
                                vehicleNumber,
                                style: AppTextStyles.caption,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.success),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'FARE',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹$fare',
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
        ],
      ),
    );
  }
}