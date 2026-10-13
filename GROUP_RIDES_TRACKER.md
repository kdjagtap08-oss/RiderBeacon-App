# Group Rides & Cloud Convoy Feature — Progress Tracker

This document tracks the step-by-step implementation of the SmartKavach Group Rides & Live Convoy Tracking System.

---

## Progress Overview

| Phase | Description | Status | Completion Date |
| :--- | :--- | :--- | :--- |
| **Branch & Blueprint** | Created `feature/group-rides-cloud`, blueprint and tracker | **DONE** | Oct 13, 2026 |
| **Milestone 1** | Convoy Models & Relative Geometry Engine (`convoy_calculator.dart`) | **DONE** | Oct 13, 2026 |
| **Milestone 2** | Convoy Map Markers & "Ride Together" Roster Sheet | **DONE** | Oct 13, 2026 |
| **Milestone 3** | Realtime Group Ride Service & WhatsApp Invite Generator | **DONE** | Oct 13, 2026 |
| **Milestone 4** | Google Sign-In & Cloud User Profile Integration | **QUEUED** | — |
| **Milestone 5** | Group Emergency Mesh Alert (Crash auto-broadcast to all riders) | **QUEUED** | — |

---

## Detailed Task Checklist

### Milestone 1: Convoy Models & Relative Geometry Engine
- [x] Create `lib/group_ride_model.dart` with `GroupRide`, `RideMember`, `RiderStatus`.
- [x] Implement `lib/convoy_calculator.dart`:
  - [x] Geodesic distance calculation via `latlong2`.
  - [x] Relative position classifier (ahead vs. behind based on heading/bearing).
  - [x] Convoy sort order along route line.
- [x] Create unit tests in `test/convoy_calculator_test.dart` (5/5 passing).

---

### Milestone 2: Convoy Map Markers & "Ride Together" Sheet
- [x] Build custom convoy marker widgets for `flutter_map` with avatar and distance badge (`+470m`, `-350m`) in `lib/convoy_rider_marker.dart`.
- [x] Build `lib/group_ride_sheet.dart` bottom sheet matching the reel design:
  - [x] Member list ordered by convoy position.
  - [x] Quick Call (`tel:`) and Directions (`geo:` / Google Maps) buttons.
  - [x] Rider status chips ("Riding", "Refueling", "Tea Break", "Emergency").
  - [x] WhatsApp Share button.
- [x] Create widget tests in `test/group_ride_sheet_test.dart` (7/7 passing).

---

### Milestone 3: Realtime Group Ride Service & Invite Generator
- [x] Implement `lib/group_ride_service.dart`:
  - [x] 4-character ride code generator (e.g. `SK-8492` avoiding ambiguous chars).
  - [x] WhatsApp invite text and deep-link generation with `url_launcher` and `share_plus` fallback.
  - [x] Throttled 3s GPS telemetry sync with emergency zero-throttle bypass.
  - [x] InMemory cloud backend (`GroupRideBackend` abstraction) for offline testing and zero cloud bill.
- [x] Create unit and mock service tests in `test/group_ride_service_test.dart` (9/9 passing).

---

### Milestone 4: Google Auth & Cloud User Profile
- [ ] Add Firebase & Google Sign-In support in `lib/auth_service.dart`.
- [ ] Save user profile, emergency contacts, and incident logs to cloud database schema.
- [ ] Add login / profile header on the app shell.

---

### Milestone 5: Group Emergency Mesh Alert
- [ ] Wire `CrashDetector` alert sequence into active `GroupRide`.
- [ ] When a rider crashes, broadcast `RiderStatus.crashAlert` with coordinates.
- [ ] Listeners in the group trigger full-screen alarm modal and focus map on the fallen rider.
- [ ] Full end-to-end unit & widget test verification.
