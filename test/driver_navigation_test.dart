import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/models/transit.dart';
import 'package:pustlivebus/services/driver_navigation.dart';
import 'package:pustlivebus/widgets/driver_navigation_panel.dart';
import 'package:pustlivebus/theme/app_brand.dart';

import 'arrival_estimator_test.dart' show arrivalFixture;

void main() {
  final now = DateTime.utc(2026, 11, 2, 17, 59, 30).millisecondsSinceEpoch;
  final catalog = TransitCatalog.parse(arrivalFixture());
  final fix = LiveBus(24.015, 89, now, true, 20, 'route', 'trip', 10);

  test('Driver navigation identifies next stop and rejects stale/poor-quality direction', () {
    DriverNavigationSnapshot snapshot(LiveBus? value, {int? time}) =>
        DriverNavigationSnapshot.calculate(
          catalog: catalog,
          route: catalog.routes['route']!,
          fix: value,
          now: time ?? now,
        );
    expect(snapshot(fix).nextStopIndex, 2);
    expect(snapshot(fix).fresh, isTrue);
    expect(snapshot(fix, time: now + 30000).nextStopIndex, isNull);
    expect(
      snapshot(LiveBus(24.015, 89, now + 10000, true, 20, 'route', 'trip', 10))
          .fresh,
      isFalse,
    );
    expect(
      snapshot(LiveBus(24.015, 89, now, true, 20, 'route', 'trip', 150)).fresh,
      isFalse,
    );
    expect(
      snapshot(
        LiveBus(24.015, 89, now, true, 20, 'different-route', 'trip', 10),
      ).nextStopIndex,
      isNull,
    );
    expect(snapshot(null).fresh, isFalse);
  });

  test(
    'Driver loop and midnight clocks preserve ambiguity and Bangladesh date',
    () {
      final loop = TransitCatalog.parse(arrivalFixture(loop: true));
      final state = DriverNavigationSnapshot.calculate(
        catalog: loop,
        route: loop.routes['route']!,
        fix: LiveBus(24.005, 89, now, true, 20, 'route', 'trip', 10),
        now: now,
      );
      expect(state.fresh, isTrue);
      expect(state.nextStopIndex, isNull);
      expect(
        driverClock(
          dhakaTime(DateTime.fromMillisecondsSinceEpoch(now, isUtc: true)),
        ),
        '23:59:30',
      );
      expect(driverArrivalClock(now + 120000), contains('2026-11-03'));
    },
  );

  testWidgets(
    'Driver stop list and arrival clock fit a narrow phone and expire with GPS',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var clock = now;
      LiveBus? mapFix;
      var mapFresh = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppBrand.theme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverNavigationPanel(
                catalog: catalog,
                busId: 'bus',
                routeId: 'route',
                fix: fix,
                tracking: true,
                clock: () => clock,
                startedAt: now - 120000,
                mapBuilder: (_, _, _, position, fresh) {
                  mapFix = position;
                  mapFresh = fresh;
                  return const SizedBox(
                    height: 255,
                    child: Text('Driver map surface'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('পরের stop: Destination'), findsOneWidget);
      expect(find.text('Middle → Destination'), findsOneWidget);
      expect(
        find.textContaining('এই দুই stop-এর মাঝে প্রায় 50%'),
        findsOneWidget,
      );
      expect(find.textContaining('সম্ভাব্য arrival:'), findsOneWidget);
      expect(find.textContaining('2026-11-03'), findsWidgets);
      expect(find.text('Trip-এর সময়: 2 মিনিট'), findsOneWidget);
      expect(find.text('1. Start'), findsOneWidget);
      expect(find.text('2. Middle'), findsOneWidget);
      expect(find.text('3. Destination'), findsOneWidget);
      expect(mapFix, isNull);
      await tester.ensureVisible(find.text('Map দেখুন'));
      await tester.tap(find.text('Map দেখুন'));
      await tester.pumpAndSettle();
      expect(mapFix, same(fix));
      expect(mapFresh, isTrue);
      expect(find.text('আমার GPS preview'), findsNothing);
      expect(tester.takeException(), isNull);
      clock += 31000;
      await tester.pump(const Duration(seconds: 1));
      expect(mapFresh, isFalse);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Driver map surface'), findsNothing);
      expect(find.textContaining('সম্ভাব্য arrival:'), findsNothing);
      expect(find.textContaining('শেষ জানা অবস্থান'), findsOneWidget);
      expect(find.textContaining('ছাড়ার পর প্রায়'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Driver preview stays private and empty GPS retains non-map planning',
    (tester) async {
      var previews = 0;
      Future<void> show(LiveBus? position) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverNavigationPanel(
                catalog: catalog,
                busId: 'bus',
                routeId: 'route',
                fix: position,
                tracking: false,
                clock: () => now,
                onLocate: () => previews++,
                mapBuilder: (_, _, _, _, _) => const SizedBox(height: 50),
              ),
            ),
          ),
        ),
      );
      await show(null);
      await tester.pump();
      expect(
        find.textContaining('Tracking বন্ধ · Private preview'),
        findsOneWidget,
      );
      await tester.tap(find.text('আমার GPS preview'));
      expect(previews, 1);
      expect(find.textContaining('Live progress নেই'), findsOneWidget);
      expect(find.text('3. Destination'), findsOneWidget);
      await show(fix);
      await tester.pump();
      expect(find.text('Tracking বন্ধ · Private preview'), findsOneWidget);
      expect(find.textContaining('সম্ভাব্য arrival:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
