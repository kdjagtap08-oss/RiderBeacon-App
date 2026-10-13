import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'group_ride_model.dart';
import 'convoy_calculator.dart';

const kAccentOrange = Color(0xFFFF6B2C);
const kCardBg = Color(0xFF181D25);
const kGoodGreen = Color(0xFF3DDC97);
const kSosRed = Color(0xFFE5323B);
const kRefuelYellow = Color(0xFFF1C40F);

/// "Ride Together" Convoy Bottom Sheet matching the reel design.
///
/// Features:
/// "Ride Together" Convoy Bottom Sheet matching the reel design.
///
/// Features:
/// 1. Convoy header with Ride Code & WhatsApp Share button.
/// 2. Ordered member list along convoy line (ahead -> you -> behind).
/// 3. Direct quick actions per rider: 📞 Call and ↗️ Directions / Navigate.
/// 4. Quick status selector: Riding, Refueling, Tea Break, Issue.
class GroupRideSheet extends StatefulWidget {
  const GroupRideSheet({
    super.key,
    required this.ride,
    required this.metrics,
    required this.currentUserId,
    required this.onStatusChanged,
    required this.onShareInvite,
    required this.onNavigateToMember,
    this.onLocateMemberOnMap,
    this.onEditDestination,
    this.convoyMetricsStream,
  });

  final GroupRide ride;
  final List<ConvoyMemberMetric> metrics;
  final String currentUserId;
  final ValueChanged<RiderStatus> onStatusChanged;
  final VoidCallback onShareInvite;
  final ValueChanged<RideMember> onNavigateToMember;
  final ValueChanged<RideMember>? onLocateMemberOnMap;
  final VoidCallback? onEditDestination;
  final Stream<List<ConvoyMemberMetric>>? convoyMetricsStream;

  @override
  State<GroupRideSheet> createState() => _GroupRideSheetState();
}

class _GroupRideSheetState extends State<GroupRideSheet> {
  RiderStatus? _optimisticStatus;

  @override
  Widget build(BuildContext context) {
    if (widget.convoyMetricsStream == null) {
      return _buildContent(context, widget.metrics);
    }

    return StreamBuilder<List<ConvoyMemberMetric>>(
      stream: widget.convoyMetricsStream,
      initialData: widget.metrics,
      builder: (context, snapshot) {
        final currentMetrics = snapshot.data ?? widget.metrics;
        return _buildContent(context, currentMetrics);
      },
    );
  }

  Widget _buildContent(BuildContext context, List<ConvoyMemberMetric> activeMetrics) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141820),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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

          // Header: "Ride Together" + Share Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.groups, color: kAccentOrange, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.ride.title.isNotEmpty ? widget.ride.title : 'Ride Together',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Code: ${widget.ride.rideCode} • ${activeMetrics.length} Riders in Convoy',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onShareInvite,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366), // WhatsApp green
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.share, size: 14),
                  label: const Text(
                    'Invite',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Destination Info & Edit Bar
          if (widget.ride.destinationName != null || widget.onEditDestination != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withValues(alpha: 0.04),
              child: Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Color(0xFF3DDC97)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.ride.destinationName != null && widget.ride.destinationName!.isNotEmpty
                          ? 'Destination: ${widget.ride.destinationName}'
                          : 'No destination set',
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onEditDestination != null)
                    InkWell(
                      onTap: widget.onEditDestination,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              widget.ride.destinationName != null ? Icons.edit_location_alt : Icons.add_location_alt,
                              size: 14,
                              color: kAccentOrange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.ride.destinationName != null ? 'Edit' : 'Set',
                              style: const TextStyle(fontSize: 11, color: kAccentOrange, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
          ],

          // Quick My Status Selector Bar
          _buildMyStatusSelector(activeMetrics),

          const Divider(color: Colors.white12, height: 1),

          // Member List ordered along Convoy Line
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: activeMetrics.length,
              separatorBuilder: (_, _) => _buildDottedConnector(),
              itemBuilder: (context, index) {
                final metric = activeMetrics[index];
                return _buildMemberTile(context, metric);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyStatusSelector(List<ConvoyMemberMetric> activeMetrics) {
    final myMetric = activeMetrics.firstWhere(
      (m) => m.member.userId == widget.currentUserId,
      orElse: () => activeMetrics.first,
    );
    final currentStatus = _optimisticStatus ?? myMetric.member.status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white.withValues(alpha: 0.02),
      child: Row(
        children: [
          const Text(
            'My Status:',
            style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusChip(RiderStatus.riding, 'Riding', Icons.two_wheeler, currentStatus),
                  _statusChip(RiderStatus.refueling, 'Refueling', Icons.local_gas_station, currentStatus),
                  _statusChip(RiderStatus.teaBreak, 'Tea Break', Icons.coffee, currentStatus),
                  _statusChip(RiderStatus.mechanicalIssue, 'Issue', Icons.build, currentStatus),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
    RiderStatus status,
    String label,
    IconData icon,
    RiderStatus activeStatus,
  ) {
    final isSelected = status == activeStatus;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(
          icon,
          size: 14,
          color: isSelected ? Colors.black : Colors.white70,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.black : Colors.white70,
          ),
        ),
        selected: isSelected,
        selectedColor: kGoodGreen,
        backgroundColor: const Color(0xFF1E2530),
        onSelected: (_) {
          setState(() => _optimisticStatus = status);
          widget.onStatusChanged(status);
        },
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildDottedConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 35),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 2,
          height: 14,
          color: Colors.white12,
        ),
      ),
    );
  }

  Widget _buildMemberTile(BuildContext context, ConvoyMemberMetric metric) {
    final member = metric.member;
    final isMe = member.userId == widget.currentUserId;
    final isCrash = member.status == RiderStatus.crashAlert;

    final statusColor = switch (member.status) {
      RiderStatus.riding => Colors.white54,
      RiderStatus.refueling => kRefuelYellow,
      RiderStatus.teaBreak => kGoodGreen,
      RiderStatus.mechanicalIssue => kAccentOrange,
      RiderStatus.stopped => Colors.white38,
      RiderStatus.crashAlert => kSosRed,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCrash
            ? kSosRed.withValues(alpha: 0.15)
            : isMe
                ? Colors.white.withValues(alpha: 0.05)
                : const Color(0xFF1C222B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCrash
              ? kSosRed
              : isMe
                  ? kAccentOrange.withValues(alpha: 0.4)
                  : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          // Avatar with Status Dot
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white12,
                child: member.photoUrl != null && member.photoUrl!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          member.photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _avatarLetter(member),
                        ),
                      )
                    : _avatarLetter(member),
              ),
              if (member.isLeader)
                const Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 7,
                    backgroundColor: Color(0xFF141820),
                    child: Icon(Icons.star, size: 10, color: kRefuelYellow),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 12),

          // Name and Relative Distance / Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isMe ? '${member.displayName} (You)' : member.displayName,
                        style: TextStyle(
                          color: isCrash ? kSosRed : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCrash) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kSosRed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CRASH!',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      metric.formattedDistance,
                      style: TextStyle(
                        color: metric.position == RelativePosition.ahead
                            ? kGoodGreen
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (member.status != RiderStatus.riding) ...[
                      const Text(' • ', style: TextStyle(color: Colors.white38)),
                      Text(
                        member.status.name,
                        style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (member.speedKmh > 5.0) ...[
                      const Text(' • ', style: TextStyle(color: Colors.white38)),
                      Text(
                        '${member.speedKmh.toStringAsFixed(0)} km/h',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Action Buttons: Call, Show on Map & Turn-by-Turn Directions
          if (!isMe) ...[
            if (member.phoneNumber != null && member.phoneNumber!.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.call, size: 20, color: kGoodGreen),
                tooltip: 'Call ${member.displayName}',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  FlutterPhoneDirectCaller.callNumber(member.phoneNumber!);
                },
              ),
            if (widget.onLocateMemberOnMap != null)
              IconButton(
                icon: const Icon(Icons.my_location, size: 20, color: Color(0xFF3498DB)),
                tooltip: 'Locate ${member.displayName} on Map',
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onLocateMemberOnMap!(member),
              ),
            IconButton(
              icon: const Icon(Icons.navigation, size: 20, color: kAccentOrange),
              tooltip: 'Directions to ${member.displayName}',
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onNavigateToMember(member),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarLetter(RideMember member) {
    final letter = member.displayName.isNotEmpty
        ? member.displayName.substring(0, 1).toUpperCase()
        : 'R';
    return Text(
      letter,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }
}
