import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'convoy_calculator.dart';
import 'foreground_service_manager.dart';
import 'group_ride_model.dart';

/// Contract for group ride cloud database operations.
abstract class GroupRideBackend {
  Future<void> saveRide(GroupRide ride);
  Future<GroupRide?> fetchRide(String rideCode);
  Future<void> updateMember(String rideCode, RideMember member);
  Future<void> removeMember(String rideCode, String userId);
  Stream<GroupRide?> streamRide(String rideCode);
}

/// In-memory group ride cloud backend for offline simulation and unit testing.
class InMemoryGroupRideBackend implements GroupRideBackend {
  final Map<String, GroupRide> _rides = {};
  final Map<String, StreamController<GroupRide?>> _controllers = {};

  @override
  Future<void> saveRide(GroupRide ride) async {
    _rides[ride.rideCode] = ride;
    _getController(ride.rideCode).add(ride);
  }

  @override
  Future<GroupRide?> fetchRide(String rideCode) async {
    return _rides[rideCode];
  }

  @override
  Future<void> updateMember(String rideCode, RideMember member) async {
    final existing = _rides[rideCode];
    if (existing == null) return;

    final updatedMembers = Map<String, RideMember>.from(existing.members);
    updatedMembers[member.userId] = member;

    final updatedRide = existing.copyWith(members: updatedMembers);
    _rides[rideCode] = updatedRide;
    _getController(rideCode).add(updatedRide);
  }

  @override
  Future<void> removeMember(String rideCode, String userId) async {
    final existing = _rides[rideCode];
    if (existing == null) return;

    final updatedMembers = Map<String, RideMember>.from(existing.members);
    updatedMembers.remove(userId);

    final updatedRide = existing.copyWith(members: updatedMembers);
    _rides[rideCode] = updatedRide;
    _getController(rideCode).add(updatedRide);
  }

  @override
  Stream<GroupRide?> streamRide(String rideCode) {
    return _getController(rideCode).stream;
  }

  StreamController<GroupRide?> _getController(String rideCode) {
    return _controllers.putIfAbsent(
      rideCode,
      () => StreamController<GroupRide?>.broadcast(),
    );
  }

  void dispose() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _rides.clear();
  }
}

/// Service managing group convoy rides, 3-second telemetry streaming,
/// relative geometry calculation, and WhatsApp invites.
class GroupRideService {
  GroupRideService({GroupRideBackend? backend})
      : _backend = backend ?? InMemoryGroupRideBackend();

  final GroupRideBackend _backend;

  GroupRide? _currentRide;
  String? _currentUserId;
  RideMember? _myMember;
  StreamSubscription<GroupRide?>? _rideSubscription;

  final StreamController<GroupRide?> _rideStreamController =
      StreamController<GroupRide?>.broadcast();
  final StreamController<List<ConvoyMemberMetric>> _convoyMetricsController =
      StreamController<List<ConvoyMemberMetric>>.broadcast();

  List<ConvoyMemberMetric> _cachedMetrics = const [];
  DateTime _lastTelemetryUpload = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minTelemetryInterval = Duration(seconds: 3);

  // Getters
  GroupRide? get currentRide => _currentRide;
  String? get currentUserId => _currentUserId;
  RideMember? get myMember => _myMember;
  List<ConvoyMemberMetric> get currentMetrics => _cachedMetrics;
  Stream<GroupRide?> get rideStream => _rideStreamController.stream;
  Stream<List<ConvoyMemberMetric>> get convoyMetricsStream =>
      _convoyMetricsController.stream;

  /// Generates a human-friendly 4-character code avoiding confusing characters (e.g. 0/O, 1/I).
  static String generateRideCode([math.Random? random]) {
    final rng = random ?? math.Random();
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    return List.generate(4, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Generates WhatsApp share invite message text.
  static String generateInviteText(GroupRide ride) {
    return '🏍️ *Join our SmartKavach Convoy Ride!*\n\n'
        '• *Convoy:* ${ride.title}\n'
        '• *Ride Code:* ${ride.rideCode}\n'
        '• *Live Tracking Link:* https://smartkavach.app/ride/${ride.rideCode}\n\n'
        'Open SmartKavach to view live convoy positions, relative distances, and crash alerts.';
  }

  /// Shares the invite link to WhatsApp, falling back to system share sheet.
  static Future<bool> shareInvite(GroupRide ride) async {
    final text = generateInviteText(ride);
    final encoded = Uri.encodeComponent(text);
    final whatsappUri = Uri.parse('whatsapp://send?text=$encoded');
    final webWaUri = Uri.parse('https://wa.me/?text=$encoded');

    try {
      if (await canLaunchUrl(whatsappUri)) {
        return await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webWaUri)) {
        return await launchUrl(webWaUri, mode: LaunchMode.externalApplication);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            subject: 'Join SmartKavach Convoy: ${ride.title}',
          ),
        );
        return true;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error launching WhatsApp share: $e, falling back to share_plus');
      }
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'Join SmartKavach Convoy: ${ride.title}',
        ),
      );
      return true;
    }
  }

  /// Opens Google Maps navigation directions to the specified target position.
  static Future<bool> openDirectionsTo(LatLng destination) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Creates a new group ride and registers the creator as the convoy leader.
  Future<GroupRide> createRide({
    required String title,
    required String leaderId,
    required String leaderName,
    String? photoUrl,
    String? phoneNumber,
    required LatLng initialPosition,
    double heading = 0.0,
    String? destinationName,
    LatLng? destinationLocation,
  }) async {
    final rideCode = generateRideCode();
    final leader = RideMember(
      userId: leaderId,
      displayName: leaderName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      position: initialPosition,
      heading: heading,
      lastPing: DateTime.now(),
      isLeader: true,
      status: RiderStatus.riding,
    );

    final ride = GroupRide(
      rideCode: rideCode,
      title: title.trim().isEmpty ? 'Group Ride' : title.trim(),
      leaderId: leaderId,
      leaderName: leaderName,
      createdAt: DateTime.now(),
      destinationName: destinationName,
      destinationLocation: destinationLocation,
      members: {leaderId: leader},
    );

    await _backend.saveRide(ride);
    await _attachToRide(ride, leaderId, leader);
    return ride;
  }

  /// Injects simulated convoy bots into the current ride for single-phone testing.
  Future<void> spawnSimulatedBots() async {
    if (_currentRide == null || _myMember == null) return;

    final myLat = _myMember!.position.latitude;
    final myLng = _myMember!.position.longitude;
    final code = _currentRide!.rideCode;

    // Bot 1: Vikram ahead by ~400m
    final bot1 = RideMember(
      userId: 'bot_vikram',
      displayName: 'Vikram (Bot)',
      position: LatLng(myLat + 0.0036, myLng + 0.0025),
      speedKmh: 48.0,
      heading: 45.0,
      status: RiderStatus.riding,
      lastPing: DateTime.now(),
      phoneNumber: '+919876543210',
    );

    // Bot 2: Rohan behind by ~300m, refueling
    final bot2 = RideMember(
      userId: 'bot_rohan',
      displayName: 'Rohan (Bot)',
      position: LatLng(myLat - 0.0028, myLng - 0.0018),
      speedKmh: 0.0,
      heading: 45.0,
      status: RiderStatus.refueling,
      lastPing: DateTime.now(),
      phoneNumber: '+919123456789',
    );

    // Bot 3: Ananya trailing behind by ~800m
    final bot3 = RideMember(
      userId: 'bot_ananya',
      displayName: 'Ananya (Bot)',
      position: LatLng(myLat - 0.0072, myLng - 0.0045),
      speedKmh: 52.0,
      heading: 45.0,
      status: RiderStatus.teaBreak,
      lastPing: DateTime.now(),
      phoneNumber: '+919988776655',
    );

    await _backend.updateMember(code, bot1);
    await _backend.updateMember(code, bot2);
    await _backend.updateMember(code, bot3);
  }

  /// Triggers a simulated crash for a bot rider to test peer crash alert popups.
  Future<void> simulateBotCrash() async {
    if (_currentRide == null) return;
    final code = _currentRide!.rideCode;
    final bot = _currentRide!.members['bot_vikram'];
    if (bot != null) {
      final crashed = bot.copyWith(
        status: RiderStatus.crashAlert,
        lastPing: DateTime.now(),
      );
      await _backend.updateMember(code, crashed);
    }
  }

  /// Joins an existing ride by its 4-character code.
  Future<GroupRide> joinRide({
    required String rideCode,
    required String userId,
    required String displayName,
    String? photoUrl,
    String? phoneNumber,
    required LatLng initialPosition,
    double heading = 0.0,
  }) async {
    final normalizedCode = rideCode.trim().toUpperCase();
    final ride = await _backend.fetchRide(normalizedCode);
    if (ride == null) {
      throw Exception('Ride code "$normalizedCode" was not found.');
    }
    if (!ride.isActive) {
      throw Exception('This ride has already ended.');
    }

    final member = RideMember(
      userId: userId,
      displayName: displayName,
      photoUrl: photoUrl,
      phoneNumber: phoneNumber,
      position: initialPosition,
      heading: heading,
      lastPing: DateTime.now(),
      isLeader: userId == ride.leaderId,
      status: RiderStatus.riding,
    );

    await _backend.updateMember(normalizedCode, member);
    final freshRide = await _backend.fetchRide(normalizedCode) ??
        ride.copyWith(members: {...ride.members, userId: member});

    await _attachToRide(freshRide, userId, member);
    return freshRide;
  }

  /// Leaves the currently active ride.
  Future<void> leaveRide() async {
    final rideCode = _currentRide?.rideCode;
    final userId = _currentUserId;
    await _detachFromRide();
    if (rideCode != null && userId != null) {
      await _backend.removeMember(rideCode, userId);
    }
  }

  /// Updates current rider's status (riding, refueling, teaBreak, mechanicalIssue, crashAlert).
  ///
  /// Note: Crash alerts bypass any 3s throttling and are broadcast immediately.
  Future<void> updateMyStatus(RiderStatus status) async {
    if (_currentRide == null || _myMember == null) return;

    final updated = _myMember!.copyWith(
      status: status,
      lastPing: DateTime.now(),
    );
    _myMember = updated;

    await _backend.updateMember(_currentRide!.rideCode, updated);
  }

  /// Updates current rider's telemetry (position, speed, heading).
  /// Throttled to 3 seconds during normal riding to conserve bandwidth.
  Future<void> updateMyTelemetry({
    required LatLng position,
    double speedKmh = 0.0,
    double heading = 0.0,
    bool force = false,
  }) async {
    if (_currentRide == null || _myMember == null) return;

    final now = DateTime.now();
    if (!force &&
        _myMember!.status != RiderStatus.crashAlert &&
        now.difference(_lastTelemetryUpload) < _minTelemetryInterval) {
      return;
    }

    _lastTelemetryUpload = now;
    final updated = _myMember!.copyWith(
      position: position,
      speedKmh: speedKmh,
      heading: heading,
      lastPing: now,
    );
    _myMember = updated;

    await _backend.updateMember(_currentRide!.rideCode, updated);
  }

  Future<void> _attachToRide(
    GroupRide ride,
    String userId,
    RideMember member,
  ) async {
    await _detachFromRide();

    _currentRide = ride;
    _currentUserId = userId;
    _myMember = member;

    _rideStreamController.add(ride);
    _recalculateMetrics(ride);

    ForegroundServiceManager.updateNotification(
      'Convoy Active • ${ride.members.length} Riders',
    );

    _rideSubscription = _backend.streamRide(ride.rideCode).listen((updatedRide) {
      if (updatedRide != null) {
        _currentRide = updatedRide;
        _rideStreamController.add(updatedRide);
        _recalculateMetrics(updatedRide);

        ForegroundServiceManager.updateNotification(
          'Convoy Active • ${updatedRide.members.length} Riders',
        );
      }
    });
  }

  Future<void> _detachFromRide() async {
    await _rideSubscription?.cancel();
    _rideSubscription = null;
    _currentRide = null;
    _currentUserId = null;
    _myMember = null;
    _cachedMetrics = const [];

    _rideStreamController.add(null);
    _convoyMetricsController.add(const []);

    ForegroundServiceManager.updateNotification('Ride Guard Active');
  }

  void _recalculateMetrics(GroupRide ride) {
    if (_myMember == null || _currentUserId == null) return;

    final metrics = ConvoyCalculator.computeConvoyMetrics(
      myPos: _myMember!.position,
      myHeadingDeg: _myMember!.heading,
      myUserId: _currentUserId!,
      members: ride.members.values.toList(),
    );

    _cachedMetrics = metrics;
    _convoyMetricsController.add(metrics);
  }

  void dispose() {
    _rideSubscription?.cancel();
    _rideStreamController.close();
    _convoyMetricsController.close();
  }
}
