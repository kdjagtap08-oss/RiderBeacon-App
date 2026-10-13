import 'package:flutter/material.dart';
import 'incident_log_service.dart';

class IncidentLogSheet extends StatefulWidget {
  const IncidentLogSheet({super.key});

  @override
  State<IncidentLogSheet> createState() => _IncidentLogSheetState();
}

class _IncidentLogSheetState extends State<IncidentLogSheet> {
  List<IncidentRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final list = await IncidentLogService.getAllIncidents();
    if (mounted) {
      setState(() {
        _records = list;
        _loading = false;
      });
    }
  }

  Future<void> _clearRecords() async {
    await IncidentLogService.clearAll();
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141820),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.history, color: Color(0xFFFF6B2C), size: 24),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ride Incident Timeline',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (_records.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white54),
                    tooltip: 'Clear History',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF181D25),
                          title: const Text('Clear Incident Logs?'),
                          content: const Text(
                              'This will erase all recorded events from this device.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Clear',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        _clearRecords();
                      }
                    },
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: _records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          return _buildIncidentCard(_records[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF3DDC97).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF3DDC97),
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Incident Records',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All telemetry logs, crash alerts, and false alarm feedback will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(IncidentRecord record) {
    final (title, icon, badgeColor) = switch (record.type) {
      IncidentType.crashAlert => (
          'Crash Alert Triggered',
          Icons.warning_amber_rounded,
          const Color(0xFFE5323B)
        ),
      IncidentType.cancelledByRider => (
          'Alert Cancelled (Rider Safe)',
          Icons.verified_user_outlined,
          const Color(0xFF3DDC97)
        ),
      IncidentType.sosDispatched => (
          'Emergency SOS Dispatched',
          Icons.emergency_rounded,
          const Color(0xFFE5323B)
        ),
      IncidentType.potholeIgnored => (
          'Road Shock / Pothole Filtered',
          Icons.waves,
          const Color(0xFFF39C12)
        ),
      IncidentType.phoneDropIgnored => (
          'Phone Drop Filtered',
          Icons.phone_android,
          const Color(0xFF3498DB)
        ),
    };

    final timeStr =
        '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}:${record.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C222B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: badgeColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Telematics summary chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _metricChip(
                'Speed',
                '${record.speedKmh.toStringAsFixed(1)} km/h',
                Icons.speed,
              ),
              _metricChip(
                'Impact',
                '${record.maxImpactG.toStringAsFixed(2)}g',
                Icons.compress,
              ),
              _metricChip(
                'Rotation',
                '${record.maxGyroDps.toStringAsFixed(0)}°/s',
                Icons.rotate_right,
              ),
              if (record.mlPrediction != null)
                _metricChip(
                  'ML',
                  '${record.mlPrediction!} (${((record.mlConfidence ?? 1.0) * 100).toStringAsFixed(0)}%)',
                  Icons.psychology_outlined,
                ),
            ],
          ),

          // Rider feedback note if available
          if (record.riderFeedback != null && record.riderFeedback!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.comment_outlined,
                      size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rider Note: ${record.riderFeedback}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Reassurance SMS badge
          if (record.reassuranceSent) ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.sms_outlined, size: 14, color: Color(0xFF3DDC97)),
                SizedBox(width: 4),
                Text(
                  "'I'm Safe' SMS dispatched to contacts",
                  style: TextStyle(color: Color(0xFF3DDC97), fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF242C38),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
