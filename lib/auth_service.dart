import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User profile representing an authenticated rider or guest session.
class UserProfile {
  final String id;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final String? phoneNumber;
  final bool isGuest;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.email,
    this.photoUrl,
    this.phoneNumber,
    this.isGuest = false,
    required this.createdAt,
  });

  UserProfile copyWith({
    String? id,
    String? displayName,
    String? email,
    String? photoUrl,
    String? phoneNumber,
    bool? isGuest,
    DateTime? createdAt,
  }) =>
      UserProfile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        photoUrl: photoUrl ?? this.photoUrl,
        phoneNumber: phoneNumber ?? this.phoneNumber,
        isGuest: isGuest ?? this.isGuest,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'phoneNumber': phoneNumber,
        'isGuest': isGuest,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String? ?? 'guest_${DateTime.now().millisecondsSinceEpoch}',
        displayName: json['displayName'] as String? ?? 'Rider',
        email: json['email'] as String?,
        photoUrl: json['photoUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
        isGuest: json['isGuest'] as bool? ?? true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
}

/// Authentication and Rider Profile Service.
///
/// Supports Google Sign-In with offline fallback to guest sessions.
/// Persists profile state locally using [SharedPreferences].
class AuthService {
  AuthService({
    SharedPreferences? prefs,
    GoogleSignIn? googleSignIn,
  })  : _googleSignIn = googleSignIn ?? GoogleSignIn.instance {
    _prefs = prefs;
  }

  static const String _storageKey = 'smartkavach_user_profile';

  SharedPreferences? _prefs;
  final GoogleSignIn _googleSignIn;
  bool _googleSignInInitialized = false;

  UserProfile? _currentUser;
  final StreamController<UserProfile?> _userStreamController =
      StreamController<UserProfile?>.broadcast();

  // Getters
  UserProfile? get currentUser => _currentUser;
  Stream<UserProfile?> get userStream => _userStreamController.stream;
  bool get isAuthenticated => _currentUser != null;
  bool get isGoogleUser => _currentUser != null && !_currentUser!.isGuest;

  /// Initializes storage and loads cached profile or creates a guest session.
  Future<UserProfile> init() async {
    _prefs ??= await SharedPreferences.getInstance();

    final rawJson = _prefs?.getString(_storageKey);
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final map = jsonDecode(rawJson) as Map<String, dynamic>;
        final profile = UserProfile.fromJson(map);
        _currentUser = profile;
        _userStreamController.add(profile);
        return profile;
      } catch (e) {
        if (kDebugMode) {
          print('Failed to deserialize stored profile: $e');
        }
      }
    }

    // Default: seamless guest rider session
    final defaultGuest = createDefaultGuest();
    await _saveProfile(defaultGuest);
    return defaultGuest;
  }

  /// Creates a default guest rider profile with random handle.
  static UserProfile createDefaultGuest() {
    final rand = math.Random().nextInt(9000) + 1000;
    final id = 'guest_$rand';
    return UserProfile(
      id: id,
      displayName: 'Rider #$rand',
      isGuest: true,
      createdAt: DateTime.now(),
    );
  }

  /// Interactive Google Sign-In.
  Future<UserProfile> signInWithGoogle() async {
    _prefs ??= await SharedPreferences.getInstance();

    try {
      if (!_googleSignInInitialized) {
        await _googleSignIn.initialize();
        _googleSignInInitialized = true;
      }

      final account = await _googleSignIn.authenticate();
      final profile = UserProfile(
        id: account.id,
        displayName: account.displayName?.trim().isNotEmpty == true
            ? account.displayName!
            : account.email.split('@').first,
        email: account.email,
        photoUrl: account.photoUrl,
        phoneNumber: _currentUser?.phoneNumber, // Preserve existing phone if set
        isGuest: false,
        createdAt: DateTime.now(),
      );

      await _saveProfile(profile);
      return profile;
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In failed or cancelled: $e');
      }
      rethrow;
    }
  }

  /// Explicitly switches or sets up a guest rider profile.
  Future<UserProfile> signInAsGuest({
    String? customName,
    String? phoneNumber,
  }) async {
    _prefs ??= await SharedPreferences.getInstance();

    final rand = math.Random().nextInt(9000) + 1000;
    final profile = UserProfile(
      id: 'guest_$rand',
      displayName: customName?.trim().isNotEmpty == true
          ? customName!.trim()
          : 'Rider #$rand',
      phoneNumber: phoneNumber?.trim(),
      isGuest: true,
      createdAt: DateTime.now(),
    );

    await _saveProfile(profile);
    return profile;
  }

  /// Updates current user profile attributes (name, phone number, photo).
  Future<UserProfile> updateProfile({
    String? displayName,
    String? phoneNumber,
    String? photoUrl,
  }) async {
    if (_currentUser == null) {
      throw StateError('No active user profile to update.');
    }

    final updated = _currentUser!.copyWith(
      displayName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : _currentUser!.displayName,
      phoneNumber: phoneNumber != null ? phoneNumber.trim() : _currentUser!.phoneNumber,
      photoUrl: photoUrl ?? _currentUser!.photoUrl,
    );

    await _saveProfile(updated);
    return updated;
  }

  /// Signs out of Google session and falls back to a fresh guest session.
  Future<UserProfile> signOut() async {
    try {
      if (!_currentUser!.isGuest) {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during Google signOut: $e');
      }
    }

    final guest = createDefaultGuest();
    await _saveProfile(guest);
    return guest;
  }

  Future<void> _saveProfile(UserProfile profile) async {
    _currentUser = profile;
    _userStreamController.add(profile);
    await _prefs?.setString(_storageKey, jsonEncode(profile.toJson()));
  }

  void dispose() {
    _userStreamController.close();
  }
}
