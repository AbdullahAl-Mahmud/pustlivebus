import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  User? _user;
  String? _busId;
  String? _busName;
  String? _error;
  bool _busy = false;
  bool _sharing = false;
  Position? _last;
  StreamSubscription<Position>? _sub;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) _loadBus();
  }

  @override
  void dispose() {
    _stopSharing(updateUi: false);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      _user = cred.user;
      await _loadBus();
    } on FirebaseAuthException catch (e) {
      _error = 'Login failed (${e.code}). Check email and password.';
    } catch (_) {
      _error = 'Login failed. Check your internet connection.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadBus() async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      final idSnap = await FirebaseDatabase.instance
          .ref('drivers/$uid/busId')
          .get();
      final busId = idSnap.value as String?;
      if (busId == null) {
        _error = 'No bus is assigned to this account. Contact the admin.';
      } else {
        final nameSnap = await FirebaseDatabase.instance
            .ref('buses/$busId/name')
            .get();
        _busId = busId;
        _busName = (nameSnap.value as String?) ?? busId;
        _error = null;
      }
    } catch (_) {
      _error =
          'Could not load bus information. Check your internet connection.';
    }
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    await _stopSharing();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _user = null;
      _busId = null;
      _busName = null;
      _error = null;
    });
  }

  Future<bool> _checkLocationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _error = 'GPS (Location) is turned off. Please turn it on.';
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _error = 'Location permission was denied.';
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      _error = 'Location permission is permanently denied. Enable it from App Settings.';
      return false;
    }
    return true;
  }

  Future<void> _publish(DatabaseReference ref, Position p) async {
    _last = p;
    try {
      await ref.set({
        'lat': p.latitude,
        'lng': p.longitude,
        'accuracy': p.accuracy,
        'ts': ServerValue.timestamp,
        'sharing': true,
      });
      _error = null;
    } catch (e) {
      _error = 'Could not send location: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _startSharing() async {
    final busId = _busId;
    if (busId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!await _checkLocationReady()) {
      if (mounted) setState(() => _busy = false);
      return;
    }

    final ref = FirebaseDatabase.instance.ref('live/$busId');
    try {
      await ref.onDisconnect().update({'sharing': false});
    } catch (_) {}

    // প্রথমে একবার বর্তমান location নিয়ে সঙ্গে সঙ্গে পাঠাও
    try {
      final first = await Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        ),
      );
      await _publish(ref, first);
    } catch (_) {
      _error = 'Waiting for GPS fix... Go outside or near a window.';
    }

    await _sub?.cancel();
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'PUST LiveBus',
        notificationText: 'Sharing bus location',
        enableWakeLock: true,
      ),
    );
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) => _publish(ref, p),
      onError: (_) {
        _stopSharing();
        if (mounted) {
          setState(() => _error = 'Location updates failed. Sharing stopped.');
        }
      },
    );

    if (mounted) {
      setState(() {
        _sharing = true;
        _busy = false;
      });
    }
  }

  Future<void> _stopSharing({bool updateUi = true}) async {
    await _sub?.cancel();
    _sub = null;
    final busId = _busId;
    if (_sharing && busId != null) {
      try {
        await FirebaseDatabase.instance.ref('live/$busId').update({
          'sharing': false,
        });
      } catch (_) {}
    }
    _sharing = false;
    if (updateUi && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [
          if (_user != null)
            IconButton(
              tooltip: 'Logout',
              onPressed: _busy ? null : _logout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _user == null ? _loginForm() : _shareView(),
      ),
    );
  }

  Widget _loginForm() {
    return ListView(
      children: [
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
        const SizedBox(height: 12),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('LOGIN'),
        ),
      ],
    );
  }

  Widget _shareView() {
    final p = _last;
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bus: ${_busName ?? '--'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sharing: ${_sharing ? 'ON' : 'OFF'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _sharing
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Latitude: ${p?.latitude.toStringAsFixed(6) ?? '--'}'),
                Text('Longitude: ${p?.longitude.toStringAsFixed(6) ?? '--'}'),
                Text(
                  'Accuracy: ${p == null ? '--' : '${p.accuracy.toStringAsFixed(1)} m'}',
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 8),
        if (_busId != null) ...[
          FilledButton.icon(
            onPressed: (_sharing || _busy) ? null : _startSharing,
            icon: const Icon(Icons.play_arrow),
            label: const Text('START SHARING'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _sharing ? _stopSharing : null,
            icon: const Icon(Icons.stop),
            label: const Text('STOP SHARING'),
          ),
        ] else
          OutlinedButton(onPressed: _loadBus, child: const Text('Reload')),
      ],
    );
  }
}
