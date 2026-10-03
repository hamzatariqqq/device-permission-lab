import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];

  bool _loading = false;
  bool _permissionGranted = false;

  String _status = 'Contacts permission not requested yet.';

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _status = 'Requesting contacts permission...';
    });

    try {
      final permissionStatus =
      await FlutterContacts.permissions.request(
        PermissionType.read,
      );

      if (permissionStatus != PermissionStatus.granted &&
          permissionStatus != PermissionStatus.limited) {
        if (!mounted) return;

        setState(() {
          _loading = false;
          _permissionGranted = false;
          _status =
          'Contacts permission denied. No contacts were accessed.';
        });

        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
        },
      );

      if (!mounted) return;

      setState(() {
        _contacts = contacts;
        _permissionGranted = true;
        _loading = false;
        _status = '${contacts.length} contacts loaded.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _status = 'Contacts error: $e';
      });
    }
  }

  String _displayName(Contact contact) {
    final name = contact.displayName?.trim();

    if (name == null || name.isEmpty) {
      return 'Unnamed Contact';
    }

    return name;
  }

  String _phoneNumbers(Contact contact) {
    if (contact.phones.isEmpty) {
      return 'No phone number';
    }

    return contact.phones
        .map((phone) => phone.number)
        .where((number) => number.isNotEmpty)
        .join(', ');
  }

  Future<void> _openSettings() async {
    await FlutterContacts.permissions.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts Lab'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Contacts Permission',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This lab reads contacts only after you explicitly '
                          'allow Android Contacts permission.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _status,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                        _permissionGranted ? Colors.green : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _loadContacts,
                      icon: const Icon(Icons.contacts),
                      label: Text(
                        _loading
                            ? 'Loading...'
                            : 'Allow & Load Contacts',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings),
                      label: const Text('App Permission Settings'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _contacts.isEmpty
                ? const Center(
              child: Text('No contacts loaded'),
            )
                : ListView.separated(
              itemCount: _contacts.length,
              separatorBuilder: (_, _) =>
              const Divider(height: 1),
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                final name = _displayName(contact);

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      name[0].toUpperCase(),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    _phoneNumbers(contact),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}