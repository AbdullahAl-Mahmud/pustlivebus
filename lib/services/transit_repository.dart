import 'dart:async';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transit.dart';
import 'arrival_estimator.dart';

abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PreferencesStore implements LocalStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _prefs.getString(key);
  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

/// Owns the public catalogue. Live GPS is deliberately never saved to disk.
class TransitRepository extends ChangeNotifier {
  TransitRepository({required this.store, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  static const catalogKey = 'pust.catalog.v1';
  static const preferencesKey = 'pust.preferences.v1';
  static const arrivalLearningKey = 'pust.arrivalLearning.v1';
  final arrivalLearning = ArrivalLearning();
  static const catalogPaths = [
    'buses',
    'routes',
    'stops',
    'schedules',
    'calendar',
  ];
  final LocalStore store;
  final DateTime Function() clock;
  TransitCatalog? catalog;
  TransitCatalog? bundled;
  TransitCatalog? _downloaded;
  bool connected = false;
  bool firebaseReady = false;
  bool referenceSelected = false;
  bool darkMode = false;
  String source = 'bundle';
  int? savedAt;
  int _offsetMs = 0;
  String? startupError, storageError;
  final Set<String> failedPaths = {};
  final Set<String> _favorites = {};
  final List<Map<String, dynamic>> reminders = [];
  Future<void> Function()? retryOnline;
  final Map<String, dynamic> _pending = {};
  Map<String, LiveBus> live = {};
  final List<StreamSubscription<DatabaseEvent>> _subscriptions = [];
  Future<void> _writes = Future.value();
  Timer? _tick;
  bool _disposed = false;
  int get serverNow => clock().millisecondsSinceEpoch + _offsetMs;
  DateTime get now =>
      dhakaTime(DateTime.fromMillisecondsSinceEpoch(serverNow, isUtc: true));
  bool get isReference => source == 'bundle';
  bool get hasDownloaded => _downloaded != null;
  bool get savedIsOld =>
      savedAt != null &&
      clock().millisecondsSinceEpoch - savedAt! >
          const Duration(days: 7).inMilliseconds;

  Future<void> initialize({String? bundledJson}) async {
    bundled = TransitCatalog.parse(
      objectMap(
        jsonDecode(
          bundledJson ??
              await rootBundle.loadString('assets/data/offline_catalog.json'),
        ),
      ),
    );
    catalog = bundled;
    try {
      final cached = await store.read(catalogKey);
      if (cached != null) {
        try {
          final envelope = objectMap(jsonDecode(cached));
          final saved = objectMap(envelope['catalog']);
          if (envelope['schemaVersion'] == 1 &&
              catalogPaths.take(4).every(saved.containsKey)) {
            _downloaded = TransitCatalog.parse(saved);
            catalog = _downloaded;
            source = 'saved';
            savedAt = (envelope['savedAt'] as num?)?.toInt();
          } else {
            storageError = 'Saved timetable format is outdated. Using the included reference copy.';
          }
        } catch (_) {
          storageError = 'Saved timetable could not be read. Using the included reference copy.';
        }
      }
      final preferences = await store.read(preferencesKey);
      if (preferences != null) {
        final data = objectMap(jsonDecode(preferences));
        _favorites.addAll(
          (data['favorites'] as List? ?? []).whereType<String>(),
        );
        darkMode = data['darkMode'] == true;
        for (final item
            in data['reminders'] is List ? data['reminders'] as List : []) {
          final row = objectMap(item);
          if (row['id'] is String &&
              row['at'] is num &&
              row['departureAt'] is num &&
              row['title'] is String) {
            reminders.add(row);
          }
        }
      }
    } catch (_) {
      storageError = 'Device storage is unavailable. Changes will last for this session only.';
    }
    checkReminders();
    try {
      final saved = await store.read(arrivalLearningKey);
      if (saved != null) arrivalLearning.restore(jsonDecode(saved));
    } catch (_) {
      // A damaged optional estimate profile must not prevent offline startup.
    }
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      checkReminders();
      _notify();
    });
    _notify();
  }

  void attach(FirebaseDatabase database) {
    if (firebaseReady || _disposed) return;
    firebaseReady = true;
    startupError = null;
    void listen(String path, void Function(Object?) accept) {
      _subscriptions.add(
        database
            .ref(path)
            .onValue
            .listen(
              (event) {
                if (_disposed) return;
                failedPaths.remove(path);
                accept(event.snapshot.value);
                _notify();
              },
              onError: (_) {
                failedPaths.add(path);
                _notify();
              },
            ),
      );
    }

    listen('.info/connected', (value) => setConnection(value == true));
    listen('.info/serverTimeOffset', (value) {
      if (value is num) _offsetMs = value.toInt();
    });
    for (final path in catalogPaths) {
      listen(path, (value) => acceptCatalogNode(path, value));
    }
    listen('live', acceptLive);
    _notify();
  }

  void setConnection(bool value) {
    connected = value;
    if (!value) arrivalLearning.resetJourneys();
    if (!value && source == 'online') source = 'saved';
    if (value) _commitCatalog();
    _notify();
  }

  void acceptCatalogNode(String path, Object? value) {
    if (!catalogPaths.contains(path)) return;
    _pending[path] = value;
    _commitCatalog();
  }

  void _commitCatalog() {
    // Never replace a coherent saved catalogue with half of a remote update.
    if (!connected || !catalogPaths.take(4).every(_pending.containsKey)) return;
    final data = <String, dynamic>{'schemaVersion': 1, ..._pending};
    _downloaded = TransitCatalog.parse(data);
    if (!referenceSelected) {
      catalog = _downloaded;
      source = 'online';
    }
    savedAt = clock().millisecondsSinceEpoch;
    _queueWrite(
      catalogKey,
      jsonEncode({'schemaVersion': 1, 'savedAt': savedAt, 'catalog': data}),
    );
    _notify();
  }

  void acceptLive(Object? value) {
    final result = <String, LiveBus>{};
    for (final entry in objectMap(value).entries) {
      final position = LiveBus.parse(entry.value);
      if (position != null) result[entry.key] = position;
    }
    live = result;
    var learned = false;
    if (_downloaded != null) {
      for (final entry in result.entries) {
        learned =
            arrivalLearning.observe(
              entry.key,
              entry.value,
              _downloaded!,
              serverNow,
              connected,
            ) ||
            learned;
      }
    }
    if (learned) {
      _queueWrite(arrivalLearningKey, jsonEncode(arrivalLearning.toJson()));
    }
    _notify();
  }

  Future<void> clearArrivalLearning() async {
    arrivalLearning.clear();
    await _queueWrite(arrivalLearningKey, jsonEncode(arrivalLearning.toJson()));
  }

  void selectReference(bool value) {
    referenceSelected = value;
    catalog = value ? bundled : (_downloaded ?? bundled);
    source = value || _downloaded == null
        ? 'bundle'
        : connected
        ? 'online'
        : 'saved';
    _notify();
  }

  LocationState locationState(String busId) => isReference
      ? LocationState.offline
      : live[busId]?.state(serverNow, connected) ?? LocationState.offline;

  String _favoriteKey(String id) => '${isReference ? 'bundle' : 'cloud'}:$id';
  bool isFavorite(String id) => _favorites.contains(_favoriteKey(id));
  void toggleFavorite(String id) {
    final key = _favoriteKey(id);
    if (!_favorites.add(key)) _favorites.remove(key);
    _savePreferences();
  }

  void setDarkMode(bool value) {
    darkMode = value;
    _savePreferences();
  }

  void _savePreferences() {
    _queueWrite(
      preferencesKey,
      jsonEncode({
        'favorites': _favorites.toList(),
        'darkMode': darkMode,
        'reminders': reminders,
      }),
    );
    _notify();
  }

  String? addReminder(ScheduledTrip trip, String date) {
    final day = DateTime.tryParse(date);
    if (day == null) return 'Choose a valid date.';
    final departure = DateTime.utc(
      day.year,
      day.month,
      day.day,
      trip.minutes ~/ 60,
      trip.minutes % 60,
    ).subtract(const Duration(hours: 6)).millisecondsSinceEpoch;
    if (departure <= serverNow) {
      return 'That scheduled departure has already passed.';
    }
    final id = '${isReference ? 'bundle' : 'cloud'}:$date:${trip.id}';
    if (reminders.any((r) => r['id'] == id)) {
      return 'A reminder is already set for this departure.';
    }
    reminders.add({
      'id': id,
      'at': departure - const Duration(minutes: 10).inMilliseconds,
      'departureAt': departure,
      'title':
          '${catalog!.buses[trip.busId]!.name} · ${formatTime(trip.departTime)}',
      'date': date,
      'delivered': false,
    });
    _savePreferences();
    checkReminders();
    return null;
  }

  void removeReminder(String id) {
    reminders.removeWhere((r) => r['id'] == id);
    _savePreferences();
  }

  void checkReminders() {
    var changed = false;
    for (final reminder in reminders) {
      if (reminder['delivered'] != true &&
          (reminder['at'] as num) <= serverNow) {
        reminder['delivered'] = true;
        reminder['expired'] = (reminder['departureAt'] as num) <= serverNow;
        changed = true;
      }
    }
    if (changed) _savePreferences();
  }

  Future<void> saveForOffline() async {
    final data = _downloaded;
    if (data == null) return;
    await _queueWrite(
      catalogKey,
      jsonEncode({'schemaVersion': 1, 'savedAt': savedAt, 'catalog': data.raw}),
    );
  }

  Future<void> _queueWrite(String key, String value) {
    _writes = _writes.then((_) async {
      try {
        await store.write(key, value);
        storageError = null;
      } catch (_) {
        storageError = 'Could not save to this device. Offline updates may be unavailable after closing the app.';
      }
      _notify();
    });
    return _writes;
  }

  Future<void> flush() => _writes;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tick?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }
}
