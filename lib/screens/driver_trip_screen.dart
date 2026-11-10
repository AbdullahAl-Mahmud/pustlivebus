import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/transit.dart';
import '../services/transit_repository.dart';
import '../services/trip_service.dart';
import '../widgets/driver_navigation_panel.dart';

class DriverTripScreen extends StatefulWidget {
  const DriverTripScreen({super.key, required this.repository});
  final TransitRepository repository;
  @override
  State<DriverTripScreen> createState() => _DriverTripScreenState();
}

class _DriverTripScreenState extends State<DriverTripScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  final _database = FirebaseDatabase.instance;
  late final _trips = TripService(_database);
  User? _user;
  String? _busId, _busName, _routeId, _tripId, _message;
  bool _busy = false, _tracking = false, _publishing = false;
  int _generation = 0;
  Position? _last;
  int? _lastSent;
  Map<String, dynamic>? _active;
  List<Map<String, dynamic>> _history = [];
  StreamSubscription<Position>? _gps;
  Timer? _heartbeat;
  bool _refreshing = false;
  StreamSubscription<DatabaseEvent>? _historySub, _activeSub;
  final Map<String, String> _routes = {};
  TransitCatalog? _driverCatalog;
  TransitRepository get repo => widget.repository;

  @override
  void initState() {
    super.initState();
    repo.addListener(_connectionChanged);
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) unawaited(_loadAssignment());
  }

  void _connectionChanged() {
    if (!mounted) return;
    if (!repo.connected && _tracking) {
      _generation++;
      unawaited(_gps?.cancel());
      _gps = null;
      _heartbeat?.cancel();
      _tracking = false;
      _message = 'Connection lost. GPS publishing stopped. Reconnect, close the open trip, then start a new trip.';
    }
    setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _heartbeat?.cancel();
    repo.removeListener(_connectionChanged);
    unawaited(_gps?.cancel());
    unawaited(_historySub?.cancel());
    unawaited(_activeSub?.cancel());
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Enter email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      _user = result.user;
      await _loadAssignment();
    } on FirebaseAuthException catch (e) {
      _message =
          'Sign-in failed (${e.code}). Check your credentials and connection.';
    } catch (_) {
      _message = 'Could not sign in. Please try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadAssignment() async {
    if (_user == null) return;
    try {
      final assignment = await _database.ref('drivers/${_user!.uid}').get();
      if (!mounted) return;
      final driver = objectMap(assignment.value);
      if (driver['active'] == false) {
        throw StateError(
          'This driver account is disabled. Contact the administrator.',
        );
      }
      final busId = driver['busId'];
      if (busId is! String || busId.isEmpty) {
        throw StateError('No bus assigned. Contact your administrator.');
      }
      final values = await Future.wait([
        _database.ref('buses/$busId').get(),
        _database.ref('routes').get(),
        _database.ref('schedules').get(),
        _database.ref('stops').get(),
        _database.ref('calendar').get(),
      ]);
      if (!mounted) return;
      final bus = objectMap(values[0].value);
      if (bus.isEmpty || bus['active'] == false) {
        throw StateError(
          'The assigned bus is unavailable. Contact your administrator.',
        );
      }
      if (_busId != busId) {
        _last = null;
        _lastSent = null;
        _active = null;
        _tripId = null;
      }
      _busId = busId;
      _busName = '${bus['nameBn'] ?? bus['name'] ?? busId}';
      _driverCatalog = TransitCatalog.parse({
        'buses': {busId: bus},
        'routes': values[1].value,
        'schedules': values[2].value,
        'stops': values[3].value,
        'calendar': values[4].value,
      });
      final allowed = objectMap(values[2].value).values
          .map(objectMap)
          .where((s) => s['busId'] == busId && s['active'] != false)
          .map((s) => s['routeId'])
          .whereType<String>()
          .toSet();
      _routes.clear();
      for (final entry in objectMap(values[1].value).entries) {
        final r = objectMap(entry.value);
        if (r['active'] != false && allowed.contains(entry.key)) {
          _routes[entry.key] = '${r['nameBn'] ?? r['name'] ?? entry.key}';
        }
      }
      _routeId = _routes.keys.firstOrNull;
      await _activeSub?.cancel();
      _activeSub = _database
          .ref('activeTrips/$busId')
          .onValue
          .listen(
            (e) {
              if (!mounted) return;
              final row = objectMap(e.snapshot.value);
              setState(() {
                _active = row.isEmpty ? null : row;
                final activeRoute = row['routeId'];
                if (activeRoute is String && _routes.containsKey(activeRoute)) {
                  _routeId = activeRoute;
                }
              });
              if (_tracking && row['tripId'] != _tripId) {
                _generation++;
                unawaited(_gps?.cancel());
                _tracking = false;
                setState(
                  () => _message =
                      'The active trip changed. GPS publishing has stopped.',
                );
              }
            },
            onError: (_) {
              if (mounted) {
                setState(
                  () => _message =
                      'Cannot read trip sessions. Check database permissions.',
                );
              }
            },
          );
      await _historySub?.cancel();
      _historySub = _database
          .ref('trips/$busId')
          .orderByChild('startedAt')
          .limitToLast(20)
          .onValue
          .listen(
            (e) {
              if (!mounted) return;
              final rows = objectMap(e.snapshot.value).entries
                  .map((e) => {...objectMap(e.value), 'id': e.key})
                  .toList();
              rows.sort(
                (a, b) => ((b['startedAt'] as num?) ?? 0).compareTo(
                  (a['startedAt'] as num?) ?? 0,
                ),
              );
              setState(() => _history = rows);
            },
            onError: (_) {
              if (mounted) {
                setState(
                  () => _message = 'Trip history is unavailable. Check database permissions.',
                );
              }
            },
          );
      _message = null;
    } catch (e) {
      _message = e is StateError ? e.message : 'Could not load assignment. Check your connection and database permissions.';
    }
    if (mounted) setState(() {});
  }

  LocationSettings get _settings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 5),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'PUST LiveBus',
            notificationText: 'Bus trip tracking is active',
            enableWakeLock: true,
          ),
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );

  Map<String, Object?> _position(Position p) => {
    'lat': p.latitude,
    'lng': p.longitude,
    'accuracy': p.accuracy,
    'capturedAt': p.timestamp.millisecondsSinceEpoch,
    'speedKmh': p.speed.isFinite && p.speed >= 0 ? p.speed * 3.6 : null,
  };

  Future<Position> _readPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on GPS / Location first.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Allow location access in app or browser settings.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (position.isMocked ||
        !position.accuracy.isFinite ||
        position.accuracy > 100) {
      throw StateError(
        'GPS quality is too low or a mock location was detected. Move outdoors and try again.',
      );
    }
    return position;
  }

  Future<void> _previewLocation() async {
    if (_busy || _tracking || _user == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final position = await _readPosition();
      if (mounted) {
        setState(() {
          _last = position;
          _lastSent = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is StateError ? error.message : 'GPS preview পাওয়া যায়নি। Location permission ও GPS পরীক্ষা করুন।',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  LiveBus? get _driverFix {
    final position = _last;
    if (position == null) return null;
    return LiveBus(
      position.latitude,
      position.longitude,
      position.timestamp.millisecondsSinceEpoch,
      _tracking,
      position.speed.isFinite && position.speed >= 0
          ? position.speed * 3.6
          : null,
      _routeId,
      _tripId,
      position.accuracy,
    );
  }

  Future<void> _start() async {
    if (_busId == null ||
        _routeId == null ||
        !repo.connected ||
        _busy ||
        _active != null) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final first = await _readPosition();
      if (!mounted || generation != _generation || !repo.connected) return;
      _tripId = await _trips
          .start(
            busId: _busId!,
            driverUid: _user!.uid,
            routeId: _routeId!,
            position: _position(first),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation || !repo.connected) return;
      _last = first;
      _lastSent = repo.serverNow;
      _tracking = true;
      _heartbeat = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _refreshPosition(),
      );
      _gps = Geolocator.getPositionStream(locationSettings: _settings).listen(
        _publish,
        onError: (_) {
          _generation++;
          unawaited(_gps?.cancel());
          _tracking = false;
          _heartbeat?.cancel();
          if (mounted) {
            setState(
              () => _message = 'GPS updates failed. Close the open trip before starting again.',
            );
          }
        },
      );
    } catch (e) {
      _message = e is StateError ? e.message : 'Could not start trip. Check GPS, connection and database permissions.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish(Position position) async {
    if (!_tracking || _publishing || !repo.connected || _tripId == null) return;
    if (position.isMocked || position.accuracy > 100) {
      setState(
        () => _message =
            'Waiting for an accurate GPS fix; low-quality update skipped.',
      );
      return;
    }
    _publishing = true;
    final generation = _generation;
    try {
      await _database.ref('live/$_busId').set({
        ..._position(position),
        'driverUid': _user!.uid,
        'tripId': _tripId,
        'routeId': _routeId,
        'sharing': true,
        'ts': ServerValue.timestamp,
      });
      if (mounted && generation == _generation) {
        setState(() {
          _last = position;
          _lastSent = repo.serverNow;
          _message = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Location could not be sent. Last successful update is shown below.',
        );
      }
    } finally {
      _publishing = false;
    }
  }

  Future<void> _refreshPosition() async {
    if (!_tracking || _refreshing || !repo.connected) return;
    _refreshing = true;
    final generation = _generation;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted && generation == _generation) await _publish(p);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _message = 'Waiting for a fresh GPS fix. The last position may become stale.',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _finish() async {
    final trip = _tripId ?? _active?['tripId'] as String?;
    if (trip == null || _busId == null || !repo.connected || _busy) return;
    setState(() => _busy = true);
    _generation++;
    _heartbeat?.cancel();
    await _gps?.cancel();
    _gps = null;
    _tracking = false;
    try {
      await _trips
          .finish(busId: _busId!, tripId: trip)
          .timeout(const Duration(seconds: 15));
      _tripId = null;
      _message = 'Trip ended and history saved.';
    } catch (_) {
      _message = 'Could not confirm trip end. Reconnect and use Close open trip to retry.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_tracking) {
      final end = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End this trip?'),
          content: const Text(
            'The trip will be closed before leaving this screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End & leave'),
            ),
          ],
        ),
      );
      if (end != true) return;
      await _finish();
      if (_tripId != null) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_tracking,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Driver · Trip control'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy ? null : _leave,
        ),
        actions: [
          if (_user != null)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _busy || _tracking || _active != null
                  ? null
                  : () async {
                      await FirebaseAuth.instance.signOut();
                      await _historySub?.cancel();
                      await _activeSub?.cancel();
                      if (mounted) {
                        setState(() {
                          _user = null;
                          _busId = null;
                          _busName = null;
                          _routeId = null;
                          _driverCatalog = null;
                          _last = null;
                          _lastSent = null;
                          _routes.clear();
                          _history = [];
                          _message = null;
                        });
                      }
                    },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (!repo.connected)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'Offline. Trip changes need a confirmed server connection.',
                    ),
                  ),
                ),
              if (_message != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_message!),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              if (_user == null) ...[
                Text(
                  'অনুমোদিত চালকের প্রবেশ',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || !repo.connected ? null : _login,
                  child: const Text('Sign in'),
                ),
              ] else ...[
                Text(
                  _busName ?? 'Loading assigned bus…',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                if (_routes.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(_routeId),
                    initialValue: _routeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assigned route',
                      border: OutlineInputBorder(),
                    ),
                    items: _routes.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _tracking || _busy || _active != null
                        ? null
                        : (value) => setState(() => _routeId = value),
                  ),
                if (_routes.isEmpty)
                  const Text(
                    'No scheduled route is configured for this bus. Contact the administrator.',
                  ),
                const SizedBox(height: 16),
                Text(
                  _tracking ? 'GPS tracking active' : 'GPS tracking stopped',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _tracking ? Colors.green : null,
                  ),
                ),
                if (_last != null)
                  Text(
                    'Speed: ${(_last!.speed < 0 ? 0 : _last!.speed * 3.6).round()} km/h · GPS accuracy: ${_last!.accuracy.round()} m',
                  ),
                if (_lastSent != null)
                  Text(
                    'Last successful publish: ${((repo.serverNow - _lastSent!) / 1000).round().clamp(0, 999999)}s ago',
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start trip'),
                  onPressed:
                      _busId != null &&
                          _routeId != null &&
                          !_tracking &&
                          !_busy &&
                          repo.connected &&
                          _active == null
                      ? _start
                      : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: Text(_tracking ? 'End trip' : 'Close open trip'),
                  onPressed:
                      !_busy &&
                          repo.connected &&
                          (_tripId != null || _active != null)
                      ? _finish
                      : null,
                ),
                if (_active != null && !_tracking)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'A previous trip is still open. Close it before starting another.',
                    ),
                  ),
                TextButton(
                  onPressed: _busy || _tracking ? null : _loadAssignment,
                  child: const Text('Reload assignment'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('Trip history দেখুন'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Trip history · সর্বশেষ ২০টি'),
                        ),
                        body: StreamBuilder<DatabaseEvent>(
                          stream: _database
                              .ref('trips/$_busId')
                              .orderByChild('startedAt')
                              .limitToLast(20)
                              .onValue,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const Center(
                                child: Text(
                                  'History পাওয়া যায়নি। Connection ও permission পরীক্ষা করুন।',
                                ),
                              );
                            }
                            final history = snapshot.hasData
                                ? objectMap(snapshot.data!.snapshot.value)
                                      .values
                                      .map(objectMap)
                                      .toList()
                                      .reversed
                                      .toList()
                                : _history;
                            history.sort(
                              (a, b) => ((b['startedAt'] as num?) ?? 0)
                                  .compareTo((a['startedAt'] as num?) ?? 0),
                            );
                            return ListView(
                              padding: const EdgeInsets.all(18),
                              children: [
                                if (history.isEmpty)
                                  const Text('No trip history available.'),
                                for (final trip in history)
                                  ListTile(
                                    isThreeLine: true,
                                    leading: Icon(
                                      trip['status'] == 'ended'
                                          ? Icons.check_circle_outline
                                          : Icons.pending_outlined,
                                    ),
                                    title: Text(
                                      _routes[trip['routeId']] ??
                                          '${trip['routeId']}',
                                    ),
                                    subtitle: Text(
                                      '${_historyTime(trip['startedAt'])}\n${trip['status'] == 'ended' ? 'Ended: ${_historyTime(trip['endedAt'])}' : 'Open session · GPS may be offline'}',
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                if (_driverCatalog != null && _busId != null)
                  DriverNavigationPanel(
                    catalog: _driverCatalog!,
                    busId: _busId!,
                    routeId: _routeId,
                    fix: _driverFix,
                    tracking: _tracking,
                    clock: () => repo.serverNow,
                    startedAt: (_active?['startedAt'] as num?)?.toInt(),
                    learning: repo.arrivalLearning,
                    onLocate: _busy ? null : _previewLocation,
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  String _historyTime(Object? value) {
    if (value is! num) return 'Awaiting server timestamp';
    final d = dhakaTime(
      DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true),
    );
    return '${dateLabel(d)} ${formatTime('${d.hour}:${d.minute.toString().padLeft(2, '0')}')}';
  }
}
