# SmartKavach — Group Rides & Cloud Convoy Feature Blueprint

## 1. Executive Summary & Value Proposition

The **Group Rides & Live Convoy Tracking System** expands SmartKavach from an individual safety tracker into a connected motorcycle touring and convoy safety suite.

Motorcyclists riding in groups often experience:
1. **Convoy Separation**: Trailing riders losing sight of the leader at highway interchanges, traffic signals, or fuel stops.
2. **Delayed Emergency Response**: A trailing rider crashes or breaks down, but the front riders don't notice for several kilometers.
3. **Communication Friction**: Calling while riding with gloves is hazardous.

This feature solves these challenges with:
- **Google Sign-In**: Instant, zero-password rider identification with name and avatar.
- **1-Click Share to WhatsApp**: Leader creates a ride (e.g. `SK-8492`) and sends a clean invite link via WhatsApp/SMS.
- **Live Convoy Map Layer**: Members rendered on OpenStreetMap (`FlutterMap`) with relative distances (`+470 m` ahead, `-350 m` behind) and status tags (Riding, Refueling, Stopped).
- **Group Emergency Mesh Alert**: If any member's `CrashDetector` confirms a crash, **all connected riders instantly receive a high-priority emergency alarm**, turning that rider's pin red with a 1-tap "Navigate to Rider" button.
- **100% Free Cloud Infrastructure**: Utilizes Firebase Auth (free tier) and Firebase Realtime Database (RTDB) where bandwidth charging is negligible for compact GPS payloads, preventing document write limits from ever exhausting.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CONVOY TELEMETRY FLOW                           │
└────────────────────────────────────────────────────────────────────────┘

 👤 RIDER 1 (Leader)                               👤 RIDER 2 (Member)
    │                                                 │
    ├─► GPS Telemetry (every 3s)                      ├─► GPS Telemetry (every 3s)
    │                                                 │
    ▼                                                 ▼
┌─────────────────────────────────────────────────────────┐
│       FIREBASE REALTIME DATABASE (Free Tier)            │
│  /groupRides/{rideCode}/liveRiders/{userId}             │
│  { lat, lng, speed, heading, status, lastPing }         │
└───────────────────────────┬─────────────────────────────┘
                            │
              Realtime WebSocket Broadcast
                            │
    ┌───────────────────────┴───────────────────────┐
    ▼                                               ▼
📱 RIDER 1 APP                                  📱 RIDER 2 APP
 • Shows Rider 2: "-350 m behind"                • Shows Rider 1: "+350 m ahead"
 • Quick Action: Call / Navigate                 • Quick Action: Call / Navigate
 • Crash Alert listener active                   • Crash Alert listener active
```

---

## 2. Cloud Database Architecture & Schema

### Free-Tier Cost Model Analysis
- **Cloud Firestore**: Charged per document write (50,000/day free). A convoy of 5 riders pinging every 3s = 6,000 writes/hour $\to$ exhausts free quota in ~8 hours.
- **Firebase Realtime Database (RTDB)**: Charged on stored data (1 GB free) and egress bandwidth (10 GB/month free). 
  - Each GPS packet: ~120 bytes.
  - 5 riders $\times$ 1,200 pings/hr $\times$ 120 bytes = **~720 KB per hour**.
  - **Verdict**: 100% free even for hundreds of hours of monthly group rides.

### Data Schema
```json
{
  "users": {
    "{userId}": {
      "displayName": "Parth Kaushal",
      "email": "rider@example.com",
      "photoUrl": "https://...",
      "emergencyContacts": ["+919876543210"],
      "createdAt": 1728830000000
    }
  },
  "groupRides": {
    "{rideCode}": {
      "meta": {
        "title": "Lonavala Highway Convoy",
        "leaderId": "{userId}",
        "leaderName": "Parth Kaushal",
        "status": "active",
        "createdAt": 1728830000000,
        "destination": {
          "name": "Tiger Point, Lonavala",
          "lat": 18.7500,
          "lng": 73.4000
        }
      },
      "liveRiders": {
        "{userId}": {
          "displayName": "Parth Kaushal",
          "photoUrl": "https://...",
          "lat": 18.5204,
          "lng": 73.8567,
          "speed": 64.2,
          "heading": 145.0,
          "status": "riding",
          "phone": "+919876543210",
          "lastPing": 1728830025000
        }
      }
    }
  },
  "cloudIncidents": {
    "{userId}": {
      "{incidentId}": {
        "timestamp": 1728830025000,
        "type": "crashAlert",
        "speedKmh": 65.0,
        "maxImpactG": 4.1,
        "maxGyroDps": 280.0,
        "mlPrediction": "Severe Motorcycle Crash",
        "riderFeedback": "Minor fall (unhurt)"
      }
    }
  }
}
```

---

## 3. Phased Implementation Roadmap

### Milestone 1: Models & Group Convoy Computation Engine (`lib/group_ride_model.dart` & `lib/convoy_calculator.dart`)
- Define `GroupRide`, `RideMember`, `RiderStatus` models with serialization and offline fallback.
- Build pure math relative distance & order engine:
  - Geodesic distance calculation along rider heading.
  - Direction classifier: determine if a member is ahead (`+470 m`) or behind (`-350 m`).
  - Unit tests in `test/convoy_calculator_test.dart`.

### Milestone 2: Group Convoy Map UI & Order Sheet (`lib/group_ride_sheet.dart` & map markers)
- Interactive convoy marker on OpenStreetMap with avatar circular border and distance chips.
- "Ride Together" bottom sheet matching the reel design:
  - Ordered member list (relative distances, call button, navigate button).
  - Quick status picker: "Riding", "Refueling", "Tea Break", "Mechanical Issue".
  - Share ride button (WhatsApp intent & system share).
- Widget tests in `test/group_ride_sheet_test.dart`.

### Milestone 3: Realtime Cloud Synchronization Service (`lib/group_ride_service.dart`)
- Hybrid cloud engine:
  - Supports mock/local simulation mode for testing without requiring live Firebase credentials on day 1.
  - Supports Firebase Realtime Database live sync for production deployment.
  - Throttled 3-second background GPS ping tied to `ForegroundServiceManager`.
- 4-digit code generator and WhatsApp invite link generator (`https://smartkavach.app/ride/{code}`).

### Milestone 4: Google Authentication & Cloud Sync (`lib/auth_service.dart`)
- User session manager: Guest / Offline mode + Google Account Sign-In.
- Cloud sync for user's emergency contacts and offline incident logs.

### Milestone 5: Group Crash Mesh Alert Integration
- Connect `CrashDetector` alert sequence to the active `GroupRide`:
  - When member crashes, broadcast `status: "CRASH_ALERT"` with live coordinates.
  - Other group members hear loud emergency audio tone and see immediate red popup with distance and direct navigation.
- Full end-to-end unit and widget test verification.
