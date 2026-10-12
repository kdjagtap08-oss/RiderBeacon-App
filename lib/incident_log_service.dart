import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum IncidentType {
  crashAlert,
  cancelledByRider,
  sosDispatched,
  potholeIgnored,
  phoneDropIgnored,
}

class IncidentRecord {
  final String id;
  final DateTime timestamp;
  final IncidentType type;
  final double? latitude;
  final double? longitude;
  final double speedKmh;
  final double maxImpactG;
  final double maxGyroDps;
  String? riderFeedback;
  bool reassuranceSent;
  String? mlPrediction;
  double? mlConfidence;

  IncidentRecord({
    required this.id,
    required this.timestamp,
    required this.type,
    this.latitude,
    this.longitude,
    required this.speedKmh,
    required this.maxImpactG,
    required this.maxGyroDps,
    this.riderFeedback,
    this.reassuranceSent = false,
    this.mlPrediction,
    this.mlConfidence,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'latitude': latitude,
        'longitude': longitude,
        'speedKmh': speedKmh,
        'maxImpactG': maxImpactG,
        'maxGyroDps': maxGyroDps,
        'riderFeedback': riderFeedback,
        'reassuranceSent': reassuranceSent,
        'mlPrediction': mlPrediction,
        'mlConfidence': mlConfidence,
      };

  factory IncidentRecord.fromJson(Map<String, dynamic> json) => IncidentRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: IncidentType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => IncidentType.crashAlert,
        ),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0.0,
        maxImpactG: (json['maxImpactG'] as num?)?.toDouble() ?? 0.0,
        maxGyroDps: (json['maxGyroDps'] as num?)?.toDouble() ?? 0.0,
        riderFeedback: json['riderFeedback'] as String?,
        reassuranceSent: json['reassuranceSent'] as bool? ?? false,
        mlPrediction: json['mlPrediction'] as String?,
        mlConfidence: (json['mlConfidence'] as num?)?.toDouble(),
      );
}

class IncidentLogService {
  static const String _kStorageKey = 'smartkavach_incident_logs';

  /// Logs a new incident record to local offline storage.
  static Future<void> logIncident(IncidentRecord incident) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAllIncidents();
    list.insert(0, incident); // Prepend so most recent is first
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_kStorageKey, encoded);
  }

  /// Retrieves all recorded incidents ordered by most recent first.
  static Future<List<IncidentRecord>> getAllIncidents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStorageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded
          .map((item) => IncidentRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Updates rider feedback and reassurance status on the most recent incident.
  static Future<void> updateLatestFeedback(
    String feedback, {
    bool reassuranceSent = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAllIncidents();
    if (list.isEmpty) return;

    list.first.riderFeedback = feedback;
    if (reassuranceSent) {
      list.first.reassuranceSent = true;
    }

    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_kStorageKey, encoded);
  }

  /// Clears all stored telemetry incident records.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStorageKey);
  }
}
