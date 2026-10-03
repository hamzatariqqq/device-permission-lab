import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../contacts/contacts_screen.dart';
import '../call_log/call_log_screen.dart';



class LocationScreen extends StatefulWidget {
  const LocationScreen({super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  StreamSubscription<Position>? _positionSubscription;

  Position? _position;
  LocationPermission? _permission;

  bool _serviceEnabled = false;
  bool _sharing = false;
  bool _loading = true;
  bool _firebaseReady = false;

  String? _uid;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        final result = await FirebaseAuth.instance.signInAnonymously();
        user = result.user;
      }

      _uid = user?.uid;
      _firebaseReady = _uid != null;

      _serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      _permission =
      await Geolocator.checkPermission();

      if (!mounted) return;

      setState(() {
        _loading = false;
        _statusMessage = 'Ready';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _statusMessage = 'Initialization error: $e';
      });
    }
  }

  Future<bool> _prepareLocation() async {
    _serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!_serviceEnabled) {
      if (mounted) {
        setState(() {
          _statusMessage =
          'Location/GPS is OFF. Please enable it.';
        });
      }

      await Geolocator.openLocationSettings();
      return false;
    }

    var permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission =
      await Geolocator.requestPermission();
    }

    _permission = permission;

    if (permission == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _statusMessage =
          'Location permission was denied.';
        });
      }
      return false;
    }

    if (permission ==
        LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _statusMessage =
          'Location permission is permanently denied. Open App Settings.';
        });
      }
      return false;
    }

    return true;
  }

  Future<void> _startLocationSharing() async {
    if (_sharing || _loading) return;

    if (!_firebaseReady || _uid == null) {
      setState(() {
        _statusMessage =
        'Firebase is not ready.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage =
      'Checking location permission...';
    });

    final ready = await _prepareLocation();

    if (!ready) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _statusMessage =
          'Getting current GPS position...';
        });
      }

      // IMPORTANT:
      // Get the first location immediately instead of waiting
      // for the position stream.
      final firstPosition =
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      _position = firstPosition;

      await _uploadLocation(
        firstPosition,
        sharing: true,
      );

      if (!mounted) return;

      setState(() {
        _sharing = true;
        _loading = false;
        _statusMessage =
        'Location acquired and uploaded. Background sharing is active.';
      });

      await _startContinuousStream();
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _sharing = false;
        _statusMessage =
        'GPS timed out after 30 seconds. Make sure Location is ON and try again near a window/outside.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _sharing = false;
        _statusMessage =
        'Could not get location: $e';
      });
    }
  }

  Future<void> _startContinuousStream() async {
    await _positionSubscription?.cancel();

    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration:
      const Duration(seconds: 10),
      foregroundNotificationConfig:
      const ForegroundNotificationConfig(
        notificationTitle:
        'Device Permission Lab',
        notificationText:
        'Location sharing is active',
        notificationChannelName:
        'Background Location',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: settings,
        ).listen(
              (position) async {
            _position = position;

            if (mounted) {
              setState(() {
                _sharing = true;
                _statusMessage =
                'Location updated and uploaded.';
              });
            }

            await _uploadLocation(
              position,
              sharing: true,
            );
          },
          onError: (Object error) {
            if (!mounted) return;

            setState(() {
              _statusMessage =
              'Location stream error: $error';
            });
          },
        );
  }

  Future<void> _uploadLocation(
      Position position, {
        required bool sharing,
      }) async {
    if (_uid == null) return;

    await FirebaseFirestore.instance
        .collection('devices')
        .doc(_uid)
        .set(
      {
        'deviceId': _uid,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'sharing': sharing,
        'locationTimestamp':
        Timestamp.fromDate(
          position.timestamp,
        ),
        'serverTimestamp':
        FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _stopLocationSharing() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    if (_uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('devices')
            .doc(_uid)
            .set(
          {
            'sharing': false,
            'serverTimestamp':
            FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      _sharing = false;
      _statusMessage =
      'Location sharing stopped.';
    });
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  String get _permissionText {
    switch (_permission) {
      case LocationPermission.always:
        return 'Allowed always';

      case LocationPermission.whileInUse:
        return 'Allowed while using app';

      case LocationPermission.denied:
        return 'Denied';

      case LocationPermission.deniedForever:
        return 'Permanently denied';

      default:
        return 'Unknown';
    }
  }

  Widget _card(
      String title,
      String value,
      IconData icon,
      ) {
    return Card(
      child: Padding(
        padding:
        const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location Lab'),
        actions: [
          IconButton(
            tooltip: 'Contacts Lab',
            icon: const Icon(Icons.contacts),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ContactsScreen(),
                ),
              );
            },
          ),

          IconButton(
            tooltip: 'Call History Lab',
            icon: const Icon(Icons.call),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CallLogScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding:
          const EdgeInsets.all(20),
          children: [
            Text(
              'Device Permission Lab',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(
                fontWeight:
                FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            _card(
              'Sharing Status',
              _sharing
                  ? 'ACTIVE'
                  : 'STOPPED',
              _sharing
                  ? Icons.location_on
                  : Icons.location_off,
            ),

            _card(
              'Firebase',
              _firebaseReady
                  ? 'CONNECTED'
                  : 'CONNECTING...',
              Icons.cloud_done,
            ),

            _card(
              'Permission',
              _permissionText,
              Icons.security,
            ),

            _card(
              'Location Services',
              _serviceEnabled
                  ? 'Enabled'
                  : 'Disabled',
              Icons.gps_fixed,
            ),

            _card(
              'Latitude',
              _position?.latitude
                  .toStringAsFixed(6) ??
                  '—',
              Icons.my_location,
            ),

            _card(
              'Longitude',
              _position?.longitude
                  .toStringAsFixed(6) ??
                  '—',
              Icons.explore,
            ),

            _card(
              'Accuracy',
              _position == null
                  ? '—'
                  : '${_position!.accuracy.toStringAsFixed(1)} meters',
              Icons.adjust,
            ),

            _card(
              'Last Update',
              _position?.timestamp
                  .toLocal()
                  .toString() ??
                  '—',
              Icons.schedule,
            ),

            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding:
                const EdgeInsets.all(16),
                child: Text(
                  _statusMessage,
                ),
              ),
            ),

            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed:
              (_loading || _sharing)
                  ? null
                  : _startLocationSharing,
              icon: const Icon(
                Icons.play_arrow,
              ),
              label: Text(
                _loading
                    ? 'Please wait...'
                    : 'Start Location Sharing',
              ),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed:
              _sharing
                  ? _stopLocationSharing
                  : null,
              icon:
              const Icon(Icons.stop),
              label: const Text(
                'Stop Location Sharing',
              ),
            ),

            if (_permission ==
                LocationPermission
                    .deniedForever)
              TextButton.icon(
                onPressed:
                _openAppSettings,
                icon: const Icon(
                  Icons.settings,
                ),
                label: const Text(
                  'Open App Settings',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}