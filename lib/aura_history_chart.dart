// aura_history_chart.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

class AuraHistoryChart extends StatefulWidget {
  final String deviceId;
  const AuraHistoryChart({super.key, required this.deviceId});

  @override
  State<AuraHistoryChart> createState() => _AuraHistoryChartState();
}

class _AuraHistoryChartState extends State<AuraHistoryChart> {
  // Create a stream that listens for history updates in the last 24 hours
  Stream<QuerySnapshot> _getHistoryStream() {
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));
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

        // Convert Firestore documents to chart data points (FlSpot)
        List<FlSpot> spots = snapshot.data!.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = (data['timestamp'] as Timestamp).toDate();
          final score = (data['aura_score'] as num).toDouble();
          // X-axis: time in milliseconds, Y-axis: aura score
          return FlSpot(timestamp.millisecondsSinceEpoch.toDouble(), score);
        }).toList();

        return LineChart(
          mainData(spots),
        );
      },
    );
  }

  // --- Chart Styling and Configuration ---

  LineChartData mainData(List<FlSpot> spots) {
    // Create a color gradient for the line based on the Aura Score
    final List<Color> gradientColors = [
      _getColorForScore(spots.map((p) => p.y).reduce(min)), // Start color
      _getColorForScore(spots.map((p) => p.y).reduce(max))  // End color
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
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 1000 * 60 * 60 * 6, // Show a label every 6 hours
            getTitlesWidget: bottomTitleWidgets,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25, // Show labels for 0, 25, 50, 75, 100
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
          gradient: LinearGradient(colors: gradientColors),
          barWidth: 5,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: gradientColors.map((color) => color.withOpacity(0.3)).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // --- Helper Widgets for Axis Titles ---

  Widget bottomTitleWidgets(double value, TitleMeta meta) {
    const style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 12,
      color: Colors.white54,
    );
    DateTime date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
    String text;
    // Format time to show as HH:mm (e.g., 14:30)
    text = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

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
    return Text(value.toInt().toString(), style: style, textAlign: TextAlign.left);
  }

  // Helper function to determine color based on score
  Color _getColorForScore(double score) {
    if (score > 75) return Colors.greenAccent;
    if (score > 50) return Colors.yellowAccent;
    if (score > 25) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}