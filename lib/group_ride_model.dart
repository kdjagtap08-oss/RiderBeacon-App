import 'package:latlong2/latlong.dart';

/// Activity status of an individual rider in the convoy.
enum RiderStatus {
  riding,
  refueling,
  teaBreak,
  mechanicalIssue,
  stopped,
  crashAlert, // High-priority emergency trigger across group
}

/// A member participating in a live group ride convoy.
class RideMember {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;
  final LatLng position;
  final double speedKmh;
  final double heading; // 0..360 degrees
  final RiderStatus status;
  final DateTime lastPing;
  final bool isLeader;

  const RideMember({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
    required this.position,
    this.speedKmh = 0.0,
    this.heading = 0.0,
    this.status = RiderStatus.riding,
    required this.lastPing,
    this.isLeader = false,
  });

  bool get isOffline =>
      DateTime.now().difference(lastPing).inSeconds > 30;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'phoneNumber': phoneNumber,
        'lat': position.latitude,
        'lng': position.longitude,
        'speedKmh': speedKmh,
        'heading': heading,
        'status': status.name,
        'lastPing': lastPing.millisecondsSinceEpoch,
        'isLeader': isLeader,
      };

  factory RideMember.fromJson(Map<String, dynamic> json) => RideMember(
        userId: json['userId'] as String? ?? '',
        displayName: json['displayName'] as String? ?? 'Rider',
        photoUrl: json['photoUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        position: LatLng(
          (json['lat'] as num?)?.toDouble() ?? 0.0,
          (json['lng'] as num?)?.toDouble() ?? 0.0,
        ),
        speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0.0,
        heading: (json['heading'] as num?)?.toDouble() ?? 0.0,
        status: RiderStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => RiderStatus.riding,
        ),
        lastPing: DateTime.fromMillisecondsSinceEpoch(
          (json['lastPing'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        isLeader: json['isLeader'] as bool? ?? false,
      );

  RideMember copyWith({
    String? userId,
    String? displayName,
    String? photoUrl,
    String? phoneNumber,
    LatLng? position,
    double? speedKmh,
    double? heading,
    RiderStatus? status,
    DateTime? lastPing,
    bool? isLeader,
  }) =>
      RideMember(
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        position: position ?? this.position,
        speedKmh: speedKmh ?? this.speedKmh,
        heading: heading ?? this.heading,
        status: status ?? this.status,
        lastPing: lastPing ?? this.lastPing,
        isLeader: isLeader ?? this.isLeader,
      );
}

/// An active group ride session.
class GroupRide {
  final String rideCode; // e.g., "SK-8492"
  final String title;
  final String leaderId;
  final String leaderName;
  final DateTime createdAt;
  final bool isActive;
  final String? destinationName;
  final LatLng? destinationLocation;
  final Map<String, RideMember> members;

  const GroupRide({
    required this.rideCode,
    required this.title,
    required this.leaderId,
    required this.leaderName,
    required this.createdAt,
    this.isActive = true,
    this.destinationName,
    this.destinationLocation,
    this.members = const {},
  });

  Map<String, dynamic> toJson() => {
        'rideCode': rideCode,
        'title': title,
        'leaderId': leaderId,
        'leaderName': leaderName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'isActive': isActive,
        'destinationName': destinationName,
        'destinationLat': destinationLocation?.latitude,
        'destinationLng': destinationLocation?.longitude,
        'members': members.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory GroupRide.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as Map<String, dynamic>? ?? {};
    final membersMap = rawMembers.map(
      (k, v) => MapEntry(k, RideMember.fromJson(Map<String, dynamic>.from(v as Map))),
    );

    LatLng? dest;
    if (json['destinationLat'] != null && json['destinationLng'] != null) {
      dest = LatLng(
        (json['destinationLat'] as num).toDouble(),
        (json['destinationLng'] as num).toDouble(),
      );
    }

    return GroupRide(
      rideCode: json['rideCode'] as String? ?? '',
      title: json['title'] as String? ?? 'Group Ride',
      leaderId: json['leaderId'] as String? ?? '',
      leaderName: json['leaderName'] as String? ?? 'Convoy Leader',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isActive: json['isActive'] as bool? ?? true,
      destinationName: json['destinationName'] as String?,
      destinationLocation: dest,
      members: membersMap,
    );
  }
}
