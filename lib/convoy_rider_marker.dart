import 'package:flutter/material.dart';
import 'group_ride_model.dart';
import 'convoy_calculator.dart';

const kAccentOrange = Color(0xFFFF6B2C);
const kGoodGreen = Color(0xFF3DDC97);
const kSosRed = Color(0xFFE5323B);
const kRefuelYellow = Color(0xFFF1C40F);

/// A distinctive map marker representing a convoy rider with an avatar bubble,
/// dynamic relative distance badge (+470 m / -350 m), and status indicator.
class ConvoyRiderMarker extends StatelessWidget {
  const ConvoyRiderMarker({
    super.key,
    required this.metric,
    required this.onTap,
  });

  final ConvoyMemberMetric metric;
  final VoidCallback onTap;

  Color _statusColor(RiderStatus status) {
    switch (status) {
      case RiderStatus.riding:
        return const Color(0xFF3498DB);
      case RiderStatus.refueling:
        return kRefuelYellow;
      case RiderStatus.teaBreak:
        return kGoodGreen;
      case RiderStatus.mechanicalIssue:
        return kAccentOrange;
      case RiderStatus.stopped:
        return Colors.white54;
      case RiderStatus.crashAlert:
        return kSosRed;
    }
  }

  IconData _statusIcon(RiderStatus status) {
    switch (status) {
      case RiderStatus.riding:
        return Icons.two_wheeler;
      case RiderStatus.refueling:
        return Icons.local_gas_station;
      case RiderStatus.teaBreak:
        return Icons.coffee;
      case RiderStatus.mechanicalIssue:
        return Icons.build;
      case RiderStatus.stopped:
        return Icons.pause;
      case RiderStatus.crashAlert:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = metric.member;
    final isCrash = member.status == RiderStatus.crashAlert;
    final borderColor = isCrash ? kSosRed : _statusColor(member.status);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row with Avatar Pin and Distance Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Circular Avatar Pin with Status Ring
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF181D25),
                  border: Border.all(
                    color: borderColor,
                    width: isCrash ? 3.5 : 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: borderColor.withValues(alpha: isCrash ? 0.6 : 0.35),
                      blurRadius: isCrash ? 16 : 8,
                      spreadRadius: isCrash ? 2 : 0,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: member.photoUrl != null && member.photoUrl!.isNotEmpty
                      ? Image.network(
                          member.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _buildInitialsAvatar(member),
                        )
                      : _buildInitialsAvatar(member),
                ),
              ),

              const SizedBox(width: 4),

              // Relative Distance Badge (+470 m / -350 m / -1.1 km)
              if (metric.position != RelativePosition.here)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: Text(
                    metric.formattedDistance,
                    style: TextStyle(
                      color: metric.position == RelativePosition.ahead
                          ? const Color(0xFF3DDC97)
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),

          // Status or Crash Banner below pin if not riding normally
          if (member.status != RiderStatus.riding) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_statusIcon(member.status), size: 10, color: Colors.black),
                  const SizedBox(width: 3),
                  Text(
                    member.status == RiderStatus.crashAlert
                        ? 'CRASH!'
                        : member.status.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInitialsAvatar(RideMember member) {
    final initials = member.displayName.isNotEmpty
        ? member.displayName.substring(0, 1).toUpperCase()
        : 'R';

    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
