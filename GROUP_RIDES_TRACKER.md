# Group Rides & Cloud Convoy Feature — Progress Tracker

This document tracks the step-by-step implementation of the SmartKavach Group Rides & Live Convoy Tracking System.

---

## Progress Overview

| Phase | Description | Status | Completion Date |
| :--- | :--- | :--- | :--- |
| **Branch & Blueprint** | Created `feature/group-rides-cloud`, blueprint and tracker | **DONE** | Oct 13, 2026 |
| **Milestone 1** | Convoy Models & Relative Geometry Engine (`convoy_calculator.dart`) | **IN PROGRESS** | — |
| **Milestone 2** | Convoy Map Markers & "Ride Together" Roster Sheet | **QUEUED** | — |
| **Milestone 3** | Realtime Group Ride Service & WhatsApp Invite Generator | **QUEUED** | — |
| **Milestone 4** | Google Sign-In & Cloud User Profile Integration | **QUEUED** | — |
| **Milestone 5** | Group Emergency Mesh Alert (Crash auto-broadcast to all riders) | **QUEUED** | — |

---

## Detailed Task Checklist

### Milestone 1: Convoy Models & Relative Geometry Engine
- [ ] Create `lib/group_ride_model.dart` with `GroupRide`, `RideMember`, `RiderStatus`.
- [ ] Implement `lib/convoy_calculator.dart`:
  - [ ] Geodesic distance calculation via `latlong2`.
  - [ ] Relative position classifier (ahead vs. behind based on heading/bearing).
  - [ ] Convoy sort order along route line.
- [ ] Create unit tests in `test/convoy_calculator_test.dart`.

---

### Milestone 2: Convoy Map Markers & "Ride Together" Sheet
- [ ] Build custom convoy marker widgets for `flutter_map` with avatar and distance badge (`+470m`, `-350m`).
- [ ] Build `lib/group_ride_sheet.dart` bottom sheet matching the reel design:
  - [ ] Member list ordered by convoy position.
  - [ ] Quick Call (`tel:`) and Directions (`geo:` / Google Maps) buttons.
  - [ ] Rider status chips ("Riding", "Refueling", "Tea Break", "Emergency").
  - [ ] WhatsApp Share button.
- [ ] Create widget tests in `test/group_ride_sheet_test.dart`.

---

### Milestone 3: Realtime Group Ride Service & Invite Generator
- [ ] Implement `lib/group_ride_service.dart`:
  - [ ] 4-character ride code generator (e.g. `SK-8492`).
  - [ ] WhatsApp invite text and deep-link generation.
  - [ ] Periodic 3s GPS telemetry sync with offline fallback.
  - [ ] Mock simulation mode for automated testing without live Firebase network calls.
- [ ] Create unit and mock service tests in `test/group_ride_service_test.dart`.

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
