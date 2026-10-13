import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_kavach/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserProfile Model Unit Tests', () {
    test('Serializes to and from JSON accurately', () {
      final now = DateTime.now();
      final profile = UserProfile(
        id: 'u_123',
        displayName: 'Parth Kaushal',
        email: 'parth@example.com',
        photoUrl: 'https://example.com/avatar.jpg',
        phoneNumber: '+919876543210',
        isGuest: false,
        createdAt: now,
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.id, equals('u_123'));
      expect(restored.displayName, equals('Parth Kaushal'));
      expect(restored.email, equals('parth@example.com'));
      expect(restored.photoUrl, equals('https://example.com/avatar.jpg'));
      expect(restored.phoneNumber, equals('+919876543210'));
      expect(restored.isGuest, isFalse);
    });

    test('copyWith updates specified fields only', () {
      final profile = UserProfile(
        id: 'u_1',
        displayName: 'Original Name',
        isGuest: true,
        createdAt: DateTime.now(),
      );

      final updated = profile.copyWith(
        displayName: 'Updated Name',
        phoneNumber: '+919999999999',
      );

      expect(updated.id, equals('u_1'));
      expect(updated.displayName, equals('Updated Name'));
      expect(updated.phoneNumber, equals('+919999999999'));
      expect(updated.isGuest, isTrue);
    });
  });

  group('AuthService Session & Lifecycle Tests', () {
    late SharedPreferences prefs;
    late AuthService authService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      authService = AuthService(prefs: prefs);
    });

    tearDown(() {
      authService.dispose();
    });

    test('init() creates default guest profile when storage is empty', () async {
      final profile = await authService.init();

      expect(profile.isGuest, isTrue);
      expect(profile.displayName, startsWith('Rider #'));
      expect(authService.currentUser, equals(profile));
      expect(authService.isAuthenticated, isTrue);
      expect(authService.isGoogleUser, isFalse);
    });

    test('init() restores cached profile from SharedPreferences', () async {
      // Seed storage
      await prefs.setString(
        'smartkavach_user_profile',
        '{"id":"stored_1","displayName":"Stored Rider","email":"stored@test.com","isGuest":false,"createdAt":1600000000000}',
      );

      final restored = await authService.init();

      expect(restored.id, equals('stored_1'));
      expect(restored.displayName, equals('Stored Rider'));
      expect(restored.email, equals('stored@test.com'));
      expect(restored.isGuest, isFalse);
      expect(authService.isGoogleUser, isTrue);
    });

    test('signInAsGuest sets custom handle and phone number', () async {
      await authService.init();

      final guest = await authService.signInAsGuest(
        customName: 'Thunderbolt',
        phoneNumber: '+919876543210',
      );

      expect(guest.displayName, equals('Thunderbolt'));
      expect(guest.phoneNumber, equals('+919876543210'));
      expect(guest.isGuest, isTrue);
      expect(authService.currentUser?.displayName, equals('Thunderbolt'));
    });

    test('updateProfile modifies active attributes and persists', () async {
      await authService.init();

      final updated = await authService.updateProfile(
        displayName: 'Ghost Rider',
        phoneNumber: '+919112233445',
        photoUrl: 'https://images.com/ghost.png',
      );

      expect(updated.displayName, equals('Ghost Rider'));
      expect(updated.phoneNumber, equals('+919112233445'));
      expect(updated.photoUrl, equals('https://images.com/ghost.png'));

      // Check SharedPreferences persistence
      final raw = prefs.getString('smartkavach_user_profile');
      expect(raw, contains('Ghost Rider'));
    });

    test('signOut resets user to a fresh guest profile', () async {
      await authService.signInAsGuest(customName: 'Rider Alpha');
      expect(authService.currentUser?.displayName, equals('Rider Alpha'));

      final fallbackGuest = await authService.signOut();

      expect(fallbackGuest.isGuest, isTrue);
      expect(fallbackGuest.displayName, startsWith('Rider #'));
      expect(authService.currentUser?.displayName, startsWith('Rider #'));
    });
  });
}
