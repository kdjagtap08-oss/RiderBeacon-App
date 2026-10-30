import 'package:flutter/material.dart';

const kAccentOrange = Color(0xFFFF6B2C);
const kCardBg = Color(0xFF181D25);
const kGoodGreen = Color(0xFF3DDC97);

/// Categorical labels for post-incident feedback.
enum IncidentReason {
  pothole,
  droppedPhone,
  minorFallSafe,
  otherFalseAlarm,
  dismissed,
}

/// A bottom sheet that appears after the rider cancels a crash alarm,
/// collecting feedback on why the event triggered to improve future detection
/// and optionally sending an "I'm Safe" reassurance text to contacts.
class IncidentFeedbackSheet extends StatelessWidget {
  const IncidentFeedbackSheet({
    super.key,
    required this.onFeedbackSelected,
    required this.onSendReassuranceText,
  });

  final ValueChanged<IncidentReason> onFeedbackSelected;
  final VoidCallback onSendReassuranceText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        color: kCardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kGoodGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    color: kGoodGreen, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Glad you're safe!",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'What caused this trigger?',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),

          // Option 1: Pothole / Speed bump
          _feedbackTile(
            context: context,
            icon: Icons.waves,
            title: 'Deep pothole or speed breaker',
            subtitle: 'Severe road shock without a fall',
            reason: IncidentReason.pothole,
          ),

          // Option 2: Dropped Phone / Mount
          _feedbackTile(
            context: context,
            icon: Icons.phone_android,
            title: 'Phone dropped / Mount slipped',
            subtitle: 'Phone dropped or handled abruptly',
            reason: IncidentReason.droppedPhone,
          ),

          // Option 3: Minor slide, but unhurt
          _feedbackTile(
            context: context,
            icon: Icons.two_wheeler,
            title: 'Minor fall / Dropped bike (Unhurt)',
            subtitle: 'A real drop occurred, but I do not need help',
            reason: IncidentReason.minorFallSafe,
            isImportant: true,
          ),

          // Option 4: Other / Accidental trigger
          _feedbackTile(
            context: context,
            icon: Icons.help_outline,
            title: 'Other false alarm',
            subtitle: 'Stall, rough terrain, or accidental nudge',
            reason: IncidentReason.otherFalseAlarm,
          ),

          const SizedBox(height: 12),

          // Dismiss Button
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onFeedbackSelected(IncidentReason.dismissed);
              },
              child: const Text(
                'Skip & Resume Ride',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feedbackTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required IncidentReason reason,
    bool isImportant = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).pop();
          onFeedbackSelected(reason);

          if (reason == IncidentReason.minorFallSafe) {
            _showReassuranceDialog(context);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isImportant
                ? kAccentOrange.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isImportant
                  ? kAccentOrange.withValues(alpha: 0.4)
                  : Colors.white10,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isImportant ? kAccentOrange : Colors.white70,
                  size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isImportant ? Colors.white : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showReassuranceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: kCardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: kGoodGreen),
            SizedBox(width: 8),
            Text('Notify Contacts?'),
          ],
        ),
        content: const Text(
          "Would you like to send a quick text to your emergency contacts saying:\n\n'I had a minor slide with my bike, but I am completely unhurt and safe!'",
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('No, Not Needed', style: TextStyle(color: Colors.white38)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(c).pop();
              onSendReassuranceText();
            },
            style: FilledButton.styleFrom(backgroundColor: kGoodGreen),
            icon: const Icon(Icons.send, color: Colors.black, size: 16),
            label: const Text("Send 'I'm Safe' SMS",
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
