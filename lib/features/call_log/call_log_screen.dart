import 'package:call_log/call_log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class CallLogScreen extends StatefulWidget {
  const CallLogScreen({super.key});

  @override
  State<CallLogScreen> createState() => _CallLogScreenState();
}

class _CallLogScreenState extends State<CallLogScreen> {
  List<CallLogEntry> _entries = [];

  bool _loading = false;

  String _status =
      'Allow access to load and sync call history to Firebase.';

  Future<void> _loadAndSyncCallHistory() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _status = 'Requesting Call Log permission...';
    });

    try {
      // User explicitly grants Android permission here.
      final permission = await Permission.phone.request();

      if (!permission.isGranted) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _status =
          'Permission denied. No call history was accessed or uploaded.';
        });

        return;
      }

      if (!mounted) return;

      setState(() {
        _status = 'Permission granted. Loading call history...';
      });

      final Iterable<CallLogEntry> result =
      await CallLog.query();

      final entries = result.toList();

      entries.sort(
            (a, b) =>
            (b.timestamp ?? 0).compareTo(a.timestamp ?? 0),
      );

      _entries = entries;

      if (!mounted) return;

      setState(() {
        _status =
        '${entries.length} records loaded. Syncing to Firebase...';
      });

      await _syncToFirebase(entries);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _status =
        '${entries.length} call records loaded and synced to Firebase.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _status = 'Call history error: $e';
      });
    }
  }

  Future<void> _syncToFirebase(
      List<CallLogEntry> entries,
      ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('Firebase user is not available.');
    }

    final firestore = FirebaseFirestore.instance;

    final collection = firestore
        .collection('devices')
        .doc(user.uid)
        .collection('callLogs');

    // Firestore batches have operation limits, so sync
    // in smaller groups.
    const chunkSize = 400;

    for (var start = 0;
    start < entries.length;
    start += chunkSize) {
      final end =
      (start + chunkSize < entries.length)
          ? start + chunkSize
          : entries.length;

      final batch = firestore.batch();

      for (var i = start; i < end; i++) {
        final entry = entries[i];

        final timestamp = entry.timestamp ?? 0;

        final normalizedNumber =
        (entry.number ?? '').replaceAll(
          RegExp(r'[^0-9+]'),
          '',
        );

        // Stable ID prevents duplicates when syncing again.
        final documentId =
        '${timestamp}_${normalizedNumber}_${entry.callType?.name ?? "unknown"}'
            .replaceAll('/', '_')
            .replaceAll(' ', '_');

        final document =
        collection.doc(documentId);

        batch.set(
          document,
          {
            'number': entry.number ?? '',
            'name': entry.name ?? '',
            'type':
            entry.callType?.name ?? 'unknown',

            'timestampMilliseconds':
            timestamp,

            'timestamp': timestamp == 0
                ? null
                : Timestamp.fromMillisecondsSinceEpoch(
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
  }

  String _callType(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return 'Incoming';

      case CallType.outgoing:
        return 'Outgoing';

      case CallType.missed:
        return 'Missed';

      case CallType.rejected:
        return 'Rejected';

      case CallType.blocked:
        return 'Blocked';

      default:
        return 'Unknown';
    }
  }

  IconData _callIcon(CallType? type) {
    switch (type) {
      case CallType.incoming:
        return Icons.call_received;

      case CallType.outgoing:
        return Icons.call_made;

      case CallType.missed:
        return Icons.call_missed;

      case CallType.rejected:
        return Icons.call_end;

      case CallType.blocked:
        return Icons.block;

      default:
        return Icons.phone;
    }
  }

  String _date(CallLogEntry entry) {
    final timestamp = entry.timestamp;

    if (timestamp == null) {
      return 'Unknown time';
    }

    final date =
    DateTime.fromMillisecondsSinceEpoch(
      timestamp,
    ).toLocal();

    final year = date.year;
    final month =
    date.month.toString().padLeft(2, '0');
    final day =
    date.day.toString().padLeft(2, '0');

    final hour =
    date.hour.toString().padLeft(2, '0');
    final minute =
    date.minute.toString().padLeft(2, '0');
    final second =
    date.second.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute:$second';
  }

  String _duration(CallLogEntry entry) {
    final seconds = entry.duration ?? 0;

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    return '${minutes}m ${remainingSeconds}s';
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History Lab'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Call History Permission',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'When you allow Call History access, '
                          'this lab will read this device\'s call '
                          'history and sync those records to your '
                          'Firebase project.',
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _status,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                        _status.contains('synced')
                            ? Colors.green
                            : null,
                      ),
                    ),

                    const SizedBox(height: 16),

                    FilledButton.icon(
                      onPressed: _loading
                          ? null
                          : _loadAndSyncCallHistory,
                      icon: const Icon(
                        Icons.sync,
                      ),
                      label: Text(
                        _loading
                            ? 'Please wait...'
                            : 'Allow & Sync Call History',
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(
                        Icons.settings,
                      ),
                      label: const Text(
                        'App Permission Settings',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: _entries.isEmpty
                ? const Center(
              child: Text(
                'No call history loaded',
              ),
            )
                : ListView.separated(
              itemCount: _entries.length,
              separatorBuilder: (_, _) =>
              const Divider(height: 1),
              itemBuilder:
                  (context, index) {
                final entry =
                _entries[index];

                final number =
                entry.number
                    ?.trim()
                    .isNotEmpty ==
                    true
                    ? entry.number!
                    : 'Unknown number';

                final name =
                entry.name
                    ?.trim()
                    .isNotEmpty ==
                    true
                    ? entry.name!
                    : null;

                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      _callIcon(
                        entry.callType,
                      ),
                    ),
                  ),

                  title: Text(
                    name ?? number,
                  ),

                  subtitle: Text(
                    name == null
                        ? '${_callType(entry.callType)}\n'
                        '${_date(entry)}\n'
                        'Duration: ${_duration(entry)}'
                        : '$number\n'
                        '${_callType(entry.callType)} • ${_date(entry)}\n'
                        'Duration: ${_duration(entry)}',
                  ),

                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}