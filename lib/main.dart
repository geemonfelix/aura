import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import 'firebase_options.dart';

// -----------------------------------------------------------------
// 1. DATA MODEL
// -----------------------------------------------------------------
class AuraDevice {
  final String id;
  final int auraScore;
  final double? latitude;
  final double? longitude;
  final double? ppm;
  final double? temperature;
  final double? humidity;
  final double? uvIndex;
  final DateTime? lastUpdated;

  AuraDevice({
    required this.id,
    required this.auraScore,
    this.latitude,
    this.longitude,
    this.ppm,
    this.temperature,
    this.humidity,
    this.uvIndex,
    this.lastUpdated,
  });

  factory AuraDevice.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    GeoPoint? location = data['location'] as GeoPoint?;

    final tempValue = data['temperature'];
    final ppmValue = data['air_quality_ppm'];
    final humidityValue = data['humidity'];
    final uvValue = data['uv_index'];

    return AuraDevice(
      id: doc.id,
      auraScore: (data['aura_score'] ?? 0).toInt(),
      latitude: location?.latitude,
      longitude: location?.longitude,
      ppm: ppmValue is num ? ppmValue.toDouble() : null,
      temperature: tempValue is num ? tempValue.toDouble() : null,
      humidity: humidityValue is num ? humidityValue.toDouble() : null,
      uvIndex: uvValue is num ? uvValue.toDouble() : null,
      lastUpdated: (data['timestamp'] is Timestamp)
          ? (data['timestamp'] as Timestamp).toDate()
          : null,
    );
  }
}

// -----------------------------------------------------------------
// 2. MAIN APP SETUP
// -----------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AuraApp());
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA Network',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF1a1a1a),
        colorScheme: const ColorScheme.dark(secondary: Colors.tealAccent),
      ),
      home: const DeviceListScreen(),
    );
  }
}

// -----------------------------------------------------------------
// 3. DEVICE LIST SCREEN (Entry Point)
// -----------------------------------------------------------------
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final Stream<QuerySnapshot> _devicesStream =
      FirebaseFirestore.instance.collection('devices').snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _devicesStream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Text(
                'Something went wrong\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null || snapshot.data!.docs.isEmpty) {
          return const Scaffold(
            body: Center(
                child: Text('No device data available. Waiting for device...')),
          );
        }
        final device = AuraDevice.fromFirestore(snapshot.data!.docs.first);
        return DeviceDashboardScreen(device: device);
      },
    );
  }
}

// -----------------------------------------------------------------
// 4. AURA HISTORY CHART WIDGET
// -----------------------------------------------------------------
class AuraHistoryChart extends StatefulWidget {
  final String deviceId;
  const AuraHistoryChart({super.key, required this.deviceId});

  @override
  State<AuraHistoryChart> createState() => _AuraHistoryChartState();
}

class _AuraHistoryChartState extends State<AuraHistoryChart> {
  Stream<QuerySnapshot> _getHistoryStream() {
    final twentyFourHoursAgo =
        DateTime.now().subtract(const Duration(hours: 24));
    return FirebaseFirestore.instance
        .collection('devices')
        .doc(widget.deviceId)
        .collection('history')
        .where('timestamp', isGreaterThan: twentyFourHoursAgo)
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _getHistoryStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No recent history data.'));
        }

        List<FlSpot> spots = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['timestamp'] as Timestamp).toDate();
          final score = (data['aura_score'] as num).toDouble();
          return FlSpot(timestamp.millisecondsSinceEpoch.toDouble(), score);
        }).toList();

        return LineChart(
          mainData(spots),
        );
      },
    );
  }

  LineChartData mainData(List<FlSpot> spots) {
    final List<Color> gradientColors = [
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.greenAccent,
    ];

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) {
          return const FlLine(color: Colors.white10, strokeWidth: 1);
        },
        getDrawingVerticalLine: (value) {
          return const FlLine(color: Colors.white10, strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1000 * 60 * 60 * 6,
            getTitlesWidget: bottomTitleWidgets,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25,
            getTitlesWidget: leftTitleWidgets,
            reservedSize: 42,
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d)),
      ),
      minX: spots.first.x,
      maxX: spots.last.x,
      minY: 0,
      maxY: 100,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors:
                  gradientColors.map((color) => color.withOpacity(0.3)).toList(),
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
      ],
    );
  }

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white54,
    );
    DateTime date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String text =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget leftTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Colors.white54,
    );
    return Text(value.toInt().toString(),
        style: style, textAlign: TextAlign.left);
  }
}

// -----------------------------------------------------------------
// 5. DEVICE DASHBOARD SCREEN (Updated for Responsiveness)
// -----------------------------------------------------------------
class DeviceDashboardScreen extends StatelessWidget {
  final AuraDevice device;
  const DeviceDashboardScreen({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const MapScreen(),
              ));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // --- Live History Chart ---
              SizedBox(
                height: 200,
                child: Card(
                  color: Colors.black.withOpacity(0.2),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: AuraHistoryChart(deviceId: device.id),
                  ),
                ),
              ),

              // --- Main AURA Score ---
              Card(
                color: _getColorForScore(device.auraScore),
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Column(
                      children: [
                        const Text('AURA',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        Text(device.auraScore.toString(),
                            style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 8),
                        Text(
                          device.lastUpdated != null
                              ? 'Last updated: ${DateFormat.jm().format(device.lastUpdated!)}'
                              : 'Last updated: N/A',
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // UPDATED: Replaced GridView with a responsive Wrap widget
              Wrap(
                spacing: 8.0, // Horizontal space between cards
                runSpacing: 8.0, // Vertical space between cards
                alignment: WrapAlignment.center,
                children: [
                  _buildMetricCard('Air Quality (PPM)', device.ppm?.toStringAsFixed(0) ?? 'N/A'),
                  _buildMetricCard('UV Index', device.uvIndex?.toStringAsFixed(1) ?? 'N/A'),
                  _buildMetricCard('Temperature', '${device.temperature?.toStringAsFixed(1) ?? 'N/A'}°C'),
                  _buildMetricCard('Humidity', '${device.humidity?.toStringAsFixed(0) ?? 'N/A'}%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // UPDATED: This widget now defines its own size constraints for responsiveness
  Widget _buildMetricCard(String title, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate width to fit two cards per row, accounting for spacing
        double cardWidth = (constraints.maxWidth / 2) - 4.0;
        // If the screen is very narrow, let the card take the full width
        if (constraints.maxWidth < 360) {
          cardWidth = constraints.maxWidth;
        }

        return SizedBox(
          width: cardWidth,
          child: Card(
            color: const Color(0xFF2a2a2a),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center,),
                  const SizedBox(height: 8),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 32,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Color _getColorForScore(int score) {
    if (score > 75) return Colors.green.shade700;
    if (score > 50) return Colors.yellow.shade800;
    if (score > 25) return Colors.orange.shade800;
    return Colors.red.shade800;
  }
}

// -----------------------------------------------------------------
// 6. MAP SCREEN
// -----------------------------------------------------------------
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final Set<Circle> _heatmapCircles = {};
  final Set<Marker> _markers = {};
  StreamSubscription? _deviceStreamSubscription;

  final CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(10.5276, 76.2144),
    zoom: 12.0,
  );

  @override
  void initState() {
    super.initState();
    _listenForDeviceUpdates();
  }

  @override
  void dispose() {
    _deviceStreamSubscription?.cancel();
    super.dispose();
  }

  void _listenForDeviceUpdates() {
    _deviceStreamSubscription = FirebaseFirestore.instance
        .collection('devices')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;

      List<AuraDevice> devices =
          snapshot.docs.map((doc) => AuraDevice.fromFirestore(doc)).toList();
      _updateMap(devices);
    });
  }

  void _updateMap(List<AuraDevice> devices) {
    Set<Circle> tempCircles = {};
    Set<Marker> tempMarkers = {};

    for (var device in devices) {
      if (device.latitude == null || device.longitude == null) continue;

      final latLng = LatLng(device.latitude!, device.longitude!);

      tempCircles.add(Circle(
        circleId: CircleId(device.id),
        center: latLng,
        radius: 200,
        fillColor: _getColorForScore(device.auraScore).withOpacity(0.5),
        strokeWidth: 1,
        strokeColor: _getColorForScore(device.auraScore),
      ));

      tempMarkers.add(Marker(
        markerId: MarkerId(device.id),
        position: latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            _getMarkerColor(device.auraScore)),
        infoWindow: InfoWindow(
          title: 'AURA Score',
          snippet: device.auraScore.toString(),
        ),
      ));
    }

    setState(() {
      _heatmapCircles.clear();
      _heatmapCircles.addAll(tempCircles);
      _markers.clear();
      _markers.addAll(tempMarkers);
    });

    final validLocationDevices = devices
        .where((d) => d.latitude != null && d.longitude != null)
        .toList();
    if (validLocationDevices.isNotEmpty) {
      _mapController?.animateCamera(CameraUpdate.newLatLng(
        LatLng(validLocationDevices.first.latitude!,
            validLocationDevices.first.longitude!),
      ));
    }
  }

  Color _getColorForScore(int score) {
    if (score > 75) return Colors.green;
    if (score > 50) return Colors.yellow;
    if (score > 25) return Colors.orange;
    return Colors.red;
  }

  double _getMarkerColor(int score) {
    if (score > 75) return BitmapDescriptor.hueGreen;
    if (score > 50) return BitmapDescriptor.hueYellow;
    if (score > 25) return BitmapDescriptor.hueOrange;
    return BitmapDescriptor.hueRed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AURA Heatmap'),
        backgroundColor: Colors.teal,
      ),
      body: GoogleMap(
        initialCameraPosition: _initialCameraPosition,
        onMapCreated: (controller) => _mapController = controller,
        circles: _heatmapCircles,
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}
