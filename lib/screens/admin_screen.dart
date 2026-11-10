import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/catalog_validation.dart';
import '../services/transit_repository.dart';
import '../services/browser_connection.dart';
import 'driver_roster_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.repository, this.auth});
  final TransitRepository repository;
  final FirebaseAuth? auth;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  FirebaseDatabase get _db => FirebaseDatabase.instance;
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  final Map<String, dynamic> _data = {};
  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  bool _allowed = false, _busy = false;
  String? _message;
  static const _sections = {
    'buses': 'Buses',
    'routes': 'Routes',
    'stops': 'Stops',
    'schedules': 'Schedules',
    'drivers': 'Drivers',
    'calendar': 'Calendar',
  };

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _authorize() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final token = await user
          .getIdTokenResult(true)
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (token.claims?['admin'] != true) {
        setState(
          () => _message =
              'Login সফল হয়েছে, কিন্তু এই account-এ administrator permission নেই। '
              'Project owner-কে এই Firebase account-এ admin: true custom claim সেট করতে হবে।',
        );
        return;
      }
      setState(() {
        _allowed = true;
        _message = null;
      });
      for (final path in _sections.keys) {
        _subs.add(
          _db
              .ref(path)
              .onValue
              .listen(
                (e) {
                  if (mounted && _allowed) {
                    setState(() => _data[path] = objectMap(e.snapshot.value));
                  }
                },
                onError: (_) {
                  if (mounted && _allowed) {
                    setState(
                      () => _message =
                          'Cannot access $path. Check administrator permissions.',
                    );
                  }
                },
              ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not check administrator access. Reconnect and retry.',
        );
      }
    }
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Email ও password দুটোই লিখুন।');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _auth
          .signInWithEmailAndPassword(
            email: _email.text.trim(),
            password: _password.text,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      _password.clear();
      await _authorize();
    } on FirebaseAuthException catch (error) {
      if (mounted) _message = _signInError(error.code);
    } on TimeoutException {
      if (mounted) {
        _message = 'Login-এর উত্তর পেতে বেশি সময় লাগছে। Internet সংযোগ দেখে আবার চেষ্টা করুন।';
      }
    } catch (_) {
      if (mounted) {
        _message = 'Login করা যায়নি। Internet সংযোগ দেখে আবার চেষ্টা করুন।';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    if (_busy) return;
    setState(() {
      _allowed = false;
      _busy = true;
      _message = null;
      _data.clear();
      _password.clear();
    });
    final subscriptions = List.of(_subs);
    _subs.clear();
    try {
      await Future.wait(subscriptions.map((sub) => sub.cancel()));
      await _auth.signOut();
    } catch (_) {
      if (mounted) {
        _message = 'Sign out সম্পূর্ণ হয়নি। Panel বন্ধ আছে; আবার চেষ্টা করুন।';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _signInError(String code) => switch (code) {
    'invalid-email' => 'Email-এর ঠিকানা সঠিকভাবে লিখুন। [invalid-email]',
    'invalid-credential' || 'wrong-password' || 'user-not-found' =>
      'Email অথবা password মেলেনি। এই app-এর Firebase Authentication account ব্যবহার করুন; Google/Gmail-এর password নয়। [$code]',
    'operation-not-allowed' || 'password-does-not-meet-requirements' =>
      'এই project-এ Email/Password login চালু নেই অথবা password policy-তে বাধা পেয়েছে। Project owner-কে Firebase Authentication settings পরীক্ষা করতে হবে। [$code]',
    'user-disabled' => 'এই account বন্ধ করা হয়েছে। Project owner-এর সঙ্গে যোগাযোগ করুন। [user-disabled]',
    'too-many-requests' => 'অনেকবার চেষ্টা হয়েছে। কিছুক্ষণ পরে আবার চেষ্টা করুন। [too-many-requests]',
    'network-request-failed' => 'Login server-এর সঙ্গে যোগাযোগ হচ্ছে না। Internet সংযোগ পরীক্ষা করুন। [network-request-failed]',
    'invalid-api-key' || 'app-not-authorized' || 'unauthorized-domain' =>
      'এই app-এর Firebase configuration বা অনুমোদিত domain পরীক্ষা করতে হবে। [$code]',
    _ => 'Login করা যায়নি। এই error code-টি project owner-কে জানান: [$code]',
  };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) => DefaultTabController(
      length: _sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transport admin'),
          actions: [
            if (_allowed)
              TextButton.icon(
                onPressed: _busy ? null : _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
          ],
          bottom: _allowed
              ? TabBar(
                  isScrollable: true,
                  tabs: _sections.values.map((s) => Tab(text: s)).toList(),
                )
              : null,
        ),
        body: Column(
          children: [
            if (!widget.repository.connected)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Database সংযোগ নেই। তথ্য পরিবর্তন বন্ধ আছে; Internet থাকলে login চেষ্টা করতে পারবেন।',
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_message!),
              ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: _allowed
                  ? TabBarView(children: _sections.keys.map(_section).toList())
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(24),
                          children: [
                            const Text(
                              'Administrator sign-in',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed:
                                  _busy ||
                                      !browserIsOnline ||
                                      !widget.repository.firebaseReady
                                  ? null
                                  : _login,
                              child: const Text('Sign in'),
                            ),
                            const SizedBox(height: 12),
                            const Text('Admin email ও password ব্যবহার করুন।'),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(String kind) {
    final records = objectMap(_data[kind]);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              '${records.length} ${_sections[kind]!.toLowerCase()}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(
                  kind == 'calendar'
                      ? 'Set date override'
                      : 'Add ${_sections[kind]}',
                ),
                onPressed: _busy || !widget.repository.connected
                    ? null
                    : () => kind == 'calendar' ? _editCalendar() : _edit(kind),
              ),
            ),
            const SizedBox(height: 12),
            if (kind == 'drivers')
              OutlinedButton.icon(
                icon: const Icon(Icons.groups_outlined),
                label: const Text('১০ জন driver-এর roster'),
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DriverRosterScreen(
                            repository: widget.repository,
                            onAssign: (row) => _edit('drivers', existing: row),
                          ),
                        ),
                      ),
              ),
            if (kind == 'drivers')
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Text(
                  'Assign existing driver accounts. Account creation and administrator grants are managed by the project owner.',
                ),
              ),
            for (final entry in records.entries)
              Card(
                child: ListTile(
                  title: Text(_recordTitle(kind, entry.key, entry.value)),
                  subtitle: Text(
                    kind == 'calendar'
                        ? '${entry.value}'
                        : objectMap(entry.value)['active'] == false
                        ? 'Archived / disabled'
                        : _recordSubtitle(kind, objectMap(entry.value)),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: _busy || !widget.repository.connected
                      ? null
                      : () => kind == 'calendar'
                            ? _editCalendar(
                                date: entry.key,
                                value: entry.value.toString(),
                              )
                            : _edit(
                                kind,
                                id: entry.key,
                                existing: objectMap(entry.value),
                              ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _name(String table, Object? id) {
    final row = objectMap(objectMap(_data[table])[id]);
    return '${row['nameBn'] ?? row['name'] ?? id ?? '—'}';
  }

  String _recordTitle(String kind, String id, Object? value) {
    final row = objectMap(value);
    if (kind == 'calendar') return id;
    if (kind == 'schedules') {
      return '${formatTime('${row['departTime']}')} · ${_name('buses', row['busId'])}';
    }
    return '${row['nameBn'] ?? row['name'] ?? id}';
  }

  String _recordSubtitle(
    String kind,
    Map<String, dynamic> row,
  ) => switch (kind) {
    'schedules' =>
      '${_name('routes', row['routeId'])}\n${row['dayType']} · ${audienceLabel('${row['audience']}')}',
    'drivers' => _name('buses', row['busId']),
    'routes' =>
      '${row['stops'] is List ? (row['stops'] as List).length : objectMap(row['stops']).length} stops',
    'stops' =>
      row['lat'] == null
          ? 'Coordinates not supplied'
          : '${row['lat']}, ${row['lng']}',
    _ => 'Bus number ${row['number']}',
  };

  Future<void> _edit(
    String kind, {
    String? id,
    Map<String, dynamic>? existing,
  }) async {
    final row = <String, dynamic>{
      ...?(existing),
      'active': existing?['active'] != false,
    };
    final controllers = <String, TextEditingController>{};
    TextEditingController field(String key) => controllers.putIfAbsent(
      key,
      () => TextEditingController(text: '${row[key] ?? ''}'),
    );
    final original = objectMap(existing);
    final sourceStops = row['stops'];
    final stops = sourceStops is List
        ? sourceStops.map((e) => '$e').toList()
        : objectMap(sourceStops).values.map((e) => '$e').toList();
    String? addStop, error;
    row['audience'] ??= 'both';
    row['dayType'] ??= 'regular';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Widget text(String key, String label, {TextInputType? keyboard}) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: field(key),
                  keyboardType: keyboard,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
          Widget select(String key, String label, Map<String, String> options) {
            final value = options.containsKey(row[key])
                ? row[key] as String?
                : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
                items: options.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) => update(() => row[key] = value),
              ),
            );
          }

          Map<String, String> options(String table) => {
            for (final entry in objectMap(_data[table]).entries)
              if (objectMap(entry.value)['active'] != false)
                entry.key: _name(table, entry.key),
          };
          return AlertDialog(
            title: Text('${id == null ? 'Add' : 'Edit'} ${_sections[kind]}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kind == 'drivers' && id == null)
                      text('accountId', 'Existing driver account ID'),
                    if (['buses', 'routes', 'stops'].contains(kind)) ...[
                      text('nameBn', 'বাংলা নাম'),
                      text(
                        kind == 'stops' ? 'nameEn' : 'name',
                        'English name (optional)',
                      ),
                    ],
                    if (kind == 'buses')
                      text(
                        'number',
                        'Bus number',
                        keyboard: TextInputType.number,
                      ),
                    if (kind == 'stops') ...[
                      text(
                        'lat',
                        'Latitude (optional)',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                      text(
                        'lng',
                        'Longitude (optional)',
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                      ),
                    ],
                    if (kind == 'routes') ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Add next stop',
                        ),
                        items: options('stops').entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => addStop = value,
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Append stop'),
                        onPressed: () {
                          if (addStop != null) {
                            update(() => stops.add(addStop!));
                          }
                        },
                      ),
                      const Text(
                        'Use arrows to change order. Add repeated stops for return journeys.',
                      ),
                      for (var i = 0; i < stops.length; i++)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${i + 1}. ${_name('stops', stops[i])}',
                              ),
                            ),
                            IconButton(
                              tooltip: 'Move up',
                              icon: const Icon(Icons.arrow_upward, size: 18),
                              onPressed: i == 0
                                  ? null
                                  : () => update(() {
                                      final stop = stops.removeAt(i);
                                      stops.insert(i - 1, stop);
                                    }),
                            ),
                            IconButton(
                              tooltip: 'Remove stop',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => update(() => stops.removeAt(i)),
                            ),
                          ],
                        ),
                    ],
                    if (kind == 'drivers') text('name', 'Driver name'),
                    if (['schedules', 'drivers'].contains(kind))
                      select('busId', 'Assigned bus', options('buses')),
                    if (kind == 'schedules') ...[
                      select('routeId', 'Route', options('routes')),
                      text(
                        'departTime',
                        'Departure time (24-hour, e.g. 08:10)',
                      ),
                      select('dayType', 'Schedule type', {
                        'regular': 'Regular',
                        'holiday': 'Holiday',
                      }),
                      select('audience', 'Passenger group', {
                        'male': 'ছাত্র / Boys',
                        'female': 'ছাত্রী / Girls',
                        'both': 'সবার জন্য / All',
                      }),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: row['active'] == true,
                      onChanged: (value) => update(() => row['active'] = value),
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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
                  for (final entry in controllers.entries) {
                    row[entry.key] = entry.value.text.trim();
                  }
                  if (kind == 'buses') {
                    row['number'] = int.tryParse('${row['number']}');
                  }
                  if (kind == 'stops') {
                    for (final key in ['lat', 'lng']) {
                      final value = '${row[key] ?? ''}'.trim();
                      row[key] = value.isEmpty
                          ? null
                          : double.tryParse(value) ?? value;
                    }
                  }
                  if (kind == 'routes') row['stops'] = stops;
                  error = validateCatalogRecord(kind, row, _data);
                  if (kind == 'drivers' &&
                      id == null &&
                      !RegExp(r'^[A-Za-z0-9_-]{1,128}$')
                          .hasMatch('${row['accountId'] ?? ''}')) {
                    error = 'Enter the existing driver account ID.';
                  }
                  if (error != null) {
                    update(() {});
                    return;
                  }
                  Navigator.pop(dialogContext, row);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    // Let the closing route finish using its controllers before disposal.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result == null || !mounted) return;
    final key =
        id ??
        (kind == 'drivers'
            ? result.remove('accountId') as String
            : _db.ref(kind).push().key!);
    setState(() => _busy = true);
    try {
      if (!widget.repository.connected) {
        throw StateError('Reconnect before saving.');
      }
      final affected = <String>{};
      if (kind == 'drivers') {
        final current = objectMap((await _db.ref('drivers/$key').get()).value);
        if (current['busId'] is String) affected.add(current['busId']);
        if (original['busId'] is String) affected.add(original['busId']);
        if (result['busId'] is String) affected.add(result['busId']);
      }
      if (kind == 'buses' && result['active'] == false) affected.add(key);
      for (final bus in affected) {
        if ((await _db.ref('activeTrips/$bus').get()).exists) {
          throw StateError(
            'End this bus’s open trip before changing its assignment or availability.',
          );
        }
      }
      await _db.ref('$kind/$key').set(result);
      _message = 'Saved successfully.';
    } catch (e) {
      _message = e is StateError
          ? e.message.toString()
          : 'Save failed. Check connection and administrator permissions.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCalendar({String? date, String? value}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(date ?? '') ?? widget.repository.now,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    final type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Schedule on ${dateLabel(picked)}'),
        children: [
          for (final entry in {
            'regular': 'Regular timetable',
            'holiday': 'Holiday timetable',
            'default': 'Use default weekly calendar',
          }.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Text(entry.value),
            ),
        ],
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!widget.repository.connected) throw StateError('Offline');
      await _db
          .ref('calendar/${dateLabel(picked)}')
          .set(type == 'default' ? null : type);
      _message = 'Calendar updated.';
    } catch (_) {
      _message = 'Calendar update failed. Check connection and permissions.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
