import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/transit_repository.dart';

/// Ten planning slots, not ten fictitious Authentication accounts.
class DriverRosterScreen extends StatefulWidget {
  const DriverRosterScreen({
    super.key,
    required this.repository,
    required this.onAssign,
  });
  final TransitRepository repository;
  final Future<void> Function(Map<String, dynamic>) onAssign;
  @override
  State<DriverRosterScreen> createState() => _DriverRosterScreenState();
}

class _DriverRosterScreenState extends State<DriverRosterScreen> {
  static const storageKey = 'pust.admin.driverRoster.v1';
  final _slots = List.generate(10, (_) => <String, dynamic>{});
  bool _loading = true, _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.repository.store.read(storageKey);
      if (saved != null) {
        final root = objectMap(jsonDecode(saved));
        if (root['version'] == 1 && root['slots'] is List) {
          final rows = root['slots'] as List;
          for (var i = 0; i < rows.length && i < 10; i++) {
            _slots[i] = objectMap(rows[i]);
          }
        }
      }
    } catch (_) {
      _message = 'আগের roster পড়া যায়নি। এই পাতার খসড়া নতুন করে শুরু হয়েছে।';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _edit(int index) async {
    final name = TextEditingController(text: '${_slots[index]['name'] ?? ''}');
    final uid = TextEditingController(text: '${_slots[index]['uid'] ?? ''}');
    var bus = _slots[index]['busId'] as String?;
    final buses = widget.repository.catalog!.buses;
    if (!buses.containsKey(bus)) bus = null;
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('Driver slot ${index + 1}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Driver-এর নাম',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: bus ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'পরিকল্পিত বাস',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Standby / এখনও নির্ধারিত নয়'),
                      ),
                      for (final item in buses.values)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        bus = value?.isEmpty == true ? null : value,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: uid,
                    decoration: const InputDecoration(
                      labelText: 'Firebase User UID (পরে দিতে পারবেন)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'UID ও বাস প্রস্তুত হলে Drivers-এ assignment করুন।',
                  ),
                  if (error != null) Text(error!),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = uid.text.trim();
                if (value.isNotEmpty &&
                    !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
                  update(
                    () => error =
                        'সঠিক Firebase User UID লিখুন অথবা ফাঁকা রাখুন।',
                  );
                  return;
                }
                if (value.isNotEmpty &&
                    _slots.asMap().entries.any(
                      (entry) =>
                          entry.key != index && entry.value['uid'] == value,
                    )) {
                  update(() => error = 'এই UID অন্য slot-এ আছে।');
                  return;
                }
                Navigator.pop(dialogContext, <String, dynamic>{
                  'name': name.text.trim(),
                  'uid': value,
                  'busId': bus,
                });
              },
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    uid.dispose();
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    final next = [..._slots];
    next[index] = result;
    try {
      await widget.repository.store.write(
        storageKey,
        jsonEncode({'version': 1, 'slots': next}),
      );
      if (mounted) {
        setState(() {
          _slots[index] = result;
          _message = 'খসড়া এই ডিভাইসে save হয়েছে।';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Save হয়নি। Device storage পরীক্ষা করে আবার চেষ্টা করুন।',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('১০ জন driver-এর roster')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    '${_slots.where((s) => '${s['name'] ?? ''}'.isNotEmpty).length}/10 জনের তথ্য প্রস্তুত',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Draft roster · এই ডিভাইসে সংরক্ষিত'),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_message!),
                    ),
                  if (_saving) const LinearProgressIndicator(),
                  for (var i = 0; i < 10; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. ${'${_slots[i]['name'] ?? ''}'.isEmpty ? 'Driver-এর তথ্য বাকি' : _slots[i]['name']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget
                                      .repository
                                      .catalog!
                                      .buses[_slots[i]['busId']]
                                      ?.name ??
                                  'Standby / বাস নির্ধারিত নয়',
                            ),
                            Text(
                              '${_slots[i]['uid'] ?? ''}'.isEmpty
                                  ? 'Login account যুক্ত হয়নি'
                                  : 'UID খসড়ায় আছে; assignment যাচাই বাকি',
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: _saving ? null : () => _edit(i),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('তথ্য লিখুন'),
                                ),
                                if ('${_slots[i]['uid'] ?? ''}'.isNotEmpty &&
                                    '${_slots[i]['name'] ?? ''}'.isNotEmpty &&
                                    _slots[i]['busId'] != null)
                                  OutlinedButton(
                                    onPressed: _saving
                                        ? null
                                        : () => widget.onAssign({
                                            'name': _slots[i]['name'],
                                            'accountId': _slots[i]['uid'],
                                            'busId': _slots[i]['busId'],
                                            'active': true,
                                          }),
                                    child: const Text('Online assignment করুন'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
  );
}
