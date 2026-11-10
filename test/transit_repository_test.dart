import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/models/transit.dart';
import 'package:pustlivebus/services/catalog_validation.dart';
import 'package:pustlivebus/services/transit_repository.dart';

class MemoryStore implements LocalStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('No storage');
    values[key] = value;
  }
}

void main() {
  final bundled = File('assets/data/offline_catalog.json').readAsStringSync();
  final raw = objectMap(jsonDecode(bundled));
  final instant = DateTime.utc(2026, 10, 30, 20); // Saturday 02:00 in Dhaka.
  Future<TransitRepository> load(MemoryStore store) async {
    final repo = TransitRepository(store: store, clock: () => instant);
    await repo.initialize(bundledJson: bundled);
    addTearDown(repo.dispose);
    return repo;
  }

  void download(TransitRepository repo) {
    repo.setConnection(true);
    for (final path in TransitRepository.catalogPaths) {
      repo.acceptCatalogNode(path, raw[path]);
    }
  }

  test(
    'First launch offline has schedules and routes without Firebase',
    () async {
      final repo = await load(MemoryStore());
      expect(repo.catalog!.buses.length, 8);
      expect(
        repo.catalog!.trips.where((t) => t.dayType == 'holiday').length,
        4,
      );
      expect(repo.catalog!.routes.length, 6);
      expect(repo.isReference, isTrue);
      expect(repo.now.weekday, DateTime.saturday);
      expect(repo.now.hour, 2);
    },
  );
  test(
    'Complete download survives restart and never persists live GPS',
    () async {
      final store = MemoryStore();
      final repo = await load(store);
      download(repo);
      repo.acceptLive({
        'bus04': {
          'lat': 24,
          'lng': 89,
          'ts': instant.millisecondsSinceEpoch,
          'sharing': true,
        },
      });
      expect(repo.locationState('bus04'), LocationState.live);
      await repo.flush();
      final reopened = await load(store);
      expect(reopened.catalog!.trips.length, repo.catalog!.trips.length);
      expect(reopened.isReference, isFalse);
      expect(reopened.connected, isFalse);
      expect(reopened.live, isEmpty);
      expect(reopened.locationState('bus04'), LocationState.offline);
    },
  );
  test('Reminders use Dhaka time and persist across restart', () async {
    var clock = DateTime.utc(2026, 10, 31, 1, 50);
    final store = MemoryStore();
    final repo = TransitRepository(store: store, clock: () => clock);
    await repo.initialize(bundledJson: bundled);
    addTearDown(repo.dispose);
    final trip = repo.catalog!.trips.firstWhere(
      (t) => t.busId == 'bus04' && t.departTime == '08:10',
    );
    expect(repo.addReminder(trip, '2026-10-31'), isNull);
    expect(repo.reminders.single['delivered'], isFalse);
    expect(repo.addReminder(trip, '2026-10-31'), isNotNull);
    clock = DateTime.utc(2026, 10, 31, 2);
    repo.checkReminders();
    expect(repo.reminders.single['delivered'], isTrue);
    await repo.flush();
    final reopened = TransitRepository(store: store, clock: () => clock);
    await reopened.initialize(bundledJson: bundled);
    addTearDown(reopened.dispose);
    expect(
      reopened.reminders.single['departureAt'],
      DateTime.utc(2026, 10, 31, 2, 10).millisecondsSinceEpoch,
    );
    clock = DateTime.utc(2026, 10, 31, 3);
    expect(
      reopened.addReminder(trip, '2026-10-31'),
      contains('already passed'),
    );
  });
  test('Partial download cannot replace a complete local catalogue', () async {
    final repo = await load(MemoryStore());
    final before = repo.catalog;
    repo.setConnection(true);
    repo.acceptCatalogNode('buses', {});
    repo.acceptCatalogNode('routes', {});
    expect(repo.catalog, same(before));
    repo.acceptCatalogNode('stops', {});
    repo.acceptCatalogNode('schedules', {});
    expect(repo.catalog!.buses, isEmpty); // Confirmed deletions stay deleted.
    expect(repo.isReference, isFalse);
  });
  test('Corrupt local JSON falls back to the bundled timetable', () async {
    final store = MemoryStore()
      ..values[TransitRepository.catalogKey] = '{broken';
    final repo = await load(store);
    expect(repo.catalog!.buses.length, 8);
    expect(repo.storageError, isNotNull);
  });
  test('Storage failure does not hide data and is reported', () async {
    final store = MemoryStore()..failWrites = true;
    final repo = await load(store);
    download(repo);
    await repo.flush();
    expect(repo.catalog!.buses.length, 8);
    expect(repo.storageError, contains('Could not save'));
  });
  test(
    'Favourites survive restart and remain separate from reference IDs',
    () async {
      final store = MemoryStore();
      final repo = await load(store);
      repo.toggleFavorite('bus04');
      await repo.flush();
      final reopened = await load(store);
      expect(reopened.isFavorite('bus04'), isTrue);
      download(reopened);
      expect(reopened.isFavorite('bus04'), isFalse);
      reopened.selectReference(true);
      expect(reopened.isFavorite('bus04'), isTrue);
      expect(reopened.locationState('bus04'), LocationState.offline);
    },
  );
  test('Disconnected and old or far-future fixes never claim live', () {
    final now = instant.millisecondsSinceEpoch;
    LiveBus fix(int ts) => LiveBus(24, 89, ts, true, 30, null, null);
    expect(fix(now).state(now, false), LocationState.stale);
    expect(fix(now - 30000).state(now, true), LocationState.stale);
    expect(fix(now + 60000).state(now, true), LocationState.stale);
    expect(fix(now - 1000).state(now, true), LocationState.live);
    expect(LiveBus.parse({'lat': 91, 'lng': 89, 'ts': now}), isNull);
    expect(LiveBus.parse({'lat': 24, 'lng': double.nan, 'ts': now}), isNull);
  });
  test('Bengali digits, English stop aliases and malformed times', () {
    final catalog = TransitCatalog.parse(raw);
    expect(catalog.matchesBus(catalog.buses['bus04']!, '৪'), isTrue);
    expect(catalog.matchesBus(catalog.buses['bus04']!, 'Terminal'), isTrue);
    expect(timeMinutes('০৮:১০'), 490);
    expect(timeMinutes('24:00'), isNull);
    expect(timeMinutes('08:60'), isNull);
    expect(formatTime('00:00'), '12:00 AM');
  });
  test(
    'Holiday defaults and date exceptions are independent of device timezone',
    () {
      final catalog = TransitCatalog.parse({
        ...raw,
        'calendar': {'2026-10-30': 'regular', '2026-10-31': 'holiday'},
      });
      expect(catalog.dayType(DateTime(2026, 10, 30)), 'regular');
      expect(catalog.dayType(DateTime(2026, 10, 31)), 'holiday');
      expect(catalog.dayType(DateTime(2026, 11, 6)), 'holiday');
    },
  );
  test('All reference trips point to existing buses, routes and stops', () {
    final catalog = TransitCatalog.parse(raw);
    expect(catalog.trips.length, objectMap(raw['schedules']).length);
    for (final route in catalog.routes.values) {
      expect(route.stopIds.length, greaterThanOrEqualTo(2));
      for (final stop in route.stopIds) {
        expect(catalog.stops.containsKey(stop), isTrue);
      }
    }
  });
  test(
    'Admin validation rejects missing references and partial coordinates',
    () {
      expect(
        validateCatalogRecord('schedules', {'busId': 'missing'}, raw),
        isNotNull,
      );
      expect(
        validateCatalogRecord('stops', {'nameBn': 'Test', 'lat': 24}, raw),
        isNotNull,
      );
      expect(
        validateCatalogRecord('routes', {
          'nameBn': 'Route',
          'stops': ['campus', 'missing'],
        }, raw),
        isNotNull,
      );
      expect(
        validateCatalogRecord(
          'schedules',
          objectMap(objectMap(raw['schedules']).values.first),
          raw,
        ),
        isNull,
      );
    },
  );
}
