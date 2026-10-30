import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'auth_service.dart';
import 'group_ride_service.dart';
import 'convoy_route_service.dart';

const kAccentOrange = Color(0xFFFF6B2C);
const kCardBg = Color(0xFF181D25);

/// Modal dialog allowing a rider to either Create a new convoy or Join by a 4-digit code.
class ConvoyJoinDialog extends StatefulWidget {
  const ConvoyJoinDialog({
    super.key,
    required this.authService,
    required this.groupRideService,
    required this.currentLocation,
  });

  final AuthService authService;
  final GroupRideService groupRideService;
  final LatLng currentLocation;

  @override
  State<ConvoyJoinDialog> createState() => _ConvoyJoinDialogState();
}

class _ConvoyJoinDialogState extends State<ConvoyJoinDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController(text: 'Sunday Morning Convoy');
  final _destinationController = TextEditingController(text: 'Hilltop Cafe');
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  bool _addSimulatedBots = true; // Auto-checked so user can test alone with 1 phone!

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _destinationController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateRide() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Please enter a convoy name.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = widget.authService.currentUser ??
          await widget.authService.init();

      final destName = _destinationController.text.trim();
      LatLng? destLocation;
      if (destName.isNotEmpty) {
        destLocation = await ConvoyRouteService.geocodeAddress(
          destName,
          nearLocation: widget.currentLocation,
        );
      }

      await widget.groupRideService.createRide(
        title: title,
        leaderId: user.id,
        leaderName: user.displayName,
        photoUrl: user.photoUrl,
        phoneNumber: user.phoneNumber,
        initialPosition: widget.currentLocation,
        destinationName: destName.isEmpty ? null : destName,
        destinationLocation: destLocation,
      );

      if (_addSimulatedBots) {
        await widget.groupRideService.spawnSimulatedBots();
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _handleJoinRide() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _errorMessage = 'Please enter a valid 4-character ride code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = widget.authService.currentUser ??
          await widget.authService.init();

      await widget.groupRideService.joinRide(
        rideCode: code,
        userId: user.id,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        phoneNumber: user.phoneNumber,
        initialPosition: widget.currentLocation,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Colors.white12),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.groups, color: kAccentOrange, size: 26),
                const SizedBox(width: 10),
                const Text(
                  'Ride Together',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: kAccentOrange,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Join Convoy'),
                  Tab(text: 'Create New'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_tabController.index == 0)
              _buildJoinTab()
            else
              _buildCreateTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 4,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            hintText: 'CODE (e.g. 5821)',
            hintStyle: const TextStyle(
              fontSize: 14,
              letterSpacing: 1,
              color: Colors.white38,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kAccentOrange,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _handleJoinRide,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Join Convoy', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Convoy Name',
            labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _destinationController,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Destination (e.g. Hilltop Cafe / Lonavala)',
            labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
            prefixIcon: const Icon(Icons.flag_rounded, color: Color(0xFFE5323B), size: 18),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => setState(() => _addSimulatedBots = !_addSimulatedBots),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Checkbox(
                  value: _addSimulatedBots,
                  onChanged: (v) => setState(() => _addSimulatedBots = v ?? true),
                  activeColor: kAccentOrange,
                  visualDensity: VisualDensity.compact,
                ),
                const Expanded(
                  child: Text(
                    'Add 3 simulated bots (test solo on 1 phone)',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kAccentOrange,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _isLoading ? null : _handleCreateRide,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Start Convoy', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
