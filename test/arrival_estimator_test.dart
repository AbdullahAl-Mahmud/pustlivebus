import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/models/transit.dart';
import 'package:pustlivebus/services/arrival_estimator.dart';
import 'package:pustlivebus/services/transit_repository.dart';

import 'transit_repository_test.dart' show MemoryStore;

Map<String, dynamic> arrivalFixture({
  bool loop = false,
  bool missing = false,
}) => {
  'buses': {
    'bus': {'name': 'Test bus', 'number': 1},
  },
  'stops': {
    'a': {'name': 'Start', 'lat': 24.0, 'lng': 89.0},
    'b': {
      'name': 'Middle',
      if (!missing) ...{'lat': 24.01, 'lng': 89.0},
    },
    'c': {'name': 'Destination', 'lat': 24.02, 'lng': 89.0},
  },
  'routes': {
    'route': {
      'name': 'Test route',
      'stops': loop ? ['a', 'b', 'a'] : ['a', 'b', 'c'],
    },
  },
  'schedules': {
    'trip': {
      'busId': 'bus',
      'routeId': 'route',
      'departTime': '23:55',
      'dayType': 'regular',
    },
  },
};

void main() {
  test('Planning uses ordered legs, refuses missing coordinates and passed occurrences', () {
    final catalog = TransitCatalog.parse(arrivalFixture(loop: true));
    final route = catalog.routes['route']!;
    final roundTrip = estimateArrival(
      catalog: catalog,
      route: route,
      destination: 2,
    )!;
    expect(roundTrip.sketchMeters, greaterThan(2000));
    expect(roundTrip.minutes, greaterThan(7));
    expect(
      estimateArrival(
        catalog: catalog,
        route: route,
        destination: 1,
        from: const RouteProjection(1, .5, 0),
      ),
      isNull,
    );
    final missing = TransitCatalog.parse(arrivalFixture(missing: true));
    expect(
      estimateArrival(
        catalog: missing,
        route: missing.routes['route']!,
        destination: 2,
      ),
      isNull,
    );
  });

  test('Outward/return overlap withholds direction instead of jumping to return leg', () {
    final catalog = TransitCatalog.parse(arrivalFixture(loop: true));
    final route = catalog.routes['route']!;
    expect(projectOnRoute(catalog, route, 24.005, 89), isNull);
    expect(projectOnRoute(catalog, route, 24.005, 89, confirmedLeg: 1)!.leg, 1);
    expect(projectOnRoute(catalog, route, 25, 90), isNull);
  });

  test(
    'Learns median after three journeys; saves durations without trip traces',
    () {
      final catalog = TransitCatalog.parse(arrivalFixture());
      final route = catalog.routes['route']!;
      final learning = ArrivalLearning();
      final start = DateTime.utc(2026).millisecondsSinceEpoch;
      for (var trip = 0; trip < 3; trip++) {
        final base = start + trip * 1000000;
        final steps = 6 + trip * 2;
        for (var step = 0; step <= steps; step++) {
          final timestamp = base + step * 30000;
          final fix = LiveBus(
            24 + .01 * step / steps,
            89,
            timestamp,
            true,
            20,
            'route',
            'trip-$trip',
            10,
          );
          learning.observe('bus', fix, catalog, timestamp, true);
          learning.observe('bus', fix, catalog, timestamp, true);
        }
        if (trip < 2) expect(learning.legMinutes(catalog, route, 0), isNull);
      }
      expect(learning.sampleCount, 3);
      expect(learning.legMinutes(catalog, route, 0), closeTo(4, .5));
      final encoded = jsonEncode(learning.toJson());
      expect(encoded, isNot(contains('trip-')));
      expect(encoded, isNot(contains('capturedAt')));
      final restored = ArrivalLearning()..restore(jsonDecode(encoded));
      expect(
        restored.legMinutes(catalog, route, 0),
        learning.legMinutes(catalog, route, 0),
      );
      final revised = arrivalFixture();
      (revised['stops'] as Map)['b']['lat'] = 24.012;
      final changed = TransitCatalog.parse(revised);
      expect(restored.legMinutes(changed, changed.routes['route']!, 0), isNull);
    },
  );

  test(
    'GPS gaps, stale fixes and repeated origins cannot manufacture samples',
    () {
      final catalog = TransitCatalog.parse(arrivalFixture());
      final learning = ArrivalLearning();
      final start = DateTime.utc(2026).millisecondsSinceEpoch;
      learning.observe(
        'bus',
        LiveBus(24, 89, start, true, 20, 'route', 'one', 10),
        catalog,
        start,
        true,
      );
      learning.observe(
        'bus',
        LiveBus(24.01, 89, start + 240000, true, 20, 'route', 'one', 10),
        catalog,
        start + 240000,
        true,
      );
      expect(learning.sampleCount, 0);
      learning.observe(
        'bus',
        LiveBus(24.02, 89, start + 270000, true, 20, 'route', 'one', 10),
        catalog,
        start + 320000,
        true,
      );
      expect(learning.sampleCount, 0);
      final loop = TransitCatalog.parse(arrivalFixture(loop: true));
      learning.observe(
        'bus',
        LiveBus(24, 89, start, true, 20, 'route', 'loop', 10),
        loop,
        start,
        true,
      );
      expect(
        learning.confirmedLeg(
          'bus',
          LiveBus(24, 89, start, true, 20, 'route', 'loop', 10),
          loop,
          loop.routes['route']!,
        ),
        isNull,
      );
    },
  );

  test(
    'Learned summaries survive offline restart and can be cleared',
    () async {
      final store = MemoryStore();
      final learning = ArrivalLearning()
        ..restore({
          'version': 1,
          'profiles': {
            'public-route': {
              '0': [3, 4, 5],
            },
          },
        });
      store.values[TransitRepository.arrivalLearningKey] = jsonEncode(
        learning.toJson(),
      );
      final repo = TransitRepository(store: store);
      await repo.initialize(bundledJson: jsonEncode(arrivalFixture()));
      expect(repo.arrivalLearning.sampleCount, 3);
      await repo.clearArrivalLearning();
      expect(repo.arrivalLearning.sampleCount, 0);
      expect(
        store.values[TransitRepository.arrivalLearningKey],
        isNot(contains('[3')),
      );
      repo.dispose();
    },
  );
}
