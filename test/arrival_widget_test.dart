import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/screens/driver_roster_screen.dart';
import 'package:pustlivebus/screens/arrival_planner_screen.dart';
import 'package:pustlivebus/services/student_location.dart';
import 'package:pustlivebus/services/transit_repository.dart';
import 'package:pustlivebus/widgets/arrival_card.dart';

import 'arrival_estimator_test.dart' show arrivalFixture;
import 'transit_repository_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'Fixed route planner works offline and future dates ignore current live GPS',
    (tester) async {
      final raw = arrivalFixture();
      final repo = TransitRepository(store: MemoryStore());
      await repo.initialize(bundledJson: jsonEncode(raw));
      await tester.pumpWidget(
        MaterialApp(
          home: ArrivalPlannerScreen(repository: repo, routeId: 'route'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('স্টপের আনুমানিক সময়'), findsOneWidget);
      expect(
        find.textContaining('বাস ছাড়ার পর এই স্টপ পর্যন্ত প্রায়'),
        findsOneWidget,
      );
      repo.setConnection(true);
      for (final path in TransitRepository.catalogPaths) {
        repo.acceptCatalogNode(path, raw[path]);
      }
      repo.acceptLive({
        'bus': {
          'lat': 24.015,
          'lng': 89.0,
          'ts': repo.serverNow,
          'accuracy': 10,
          'sharing': true,
          'speedKmh': 20,
          'routeId': 'route',
          'tripId': 'session',
        },
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArrivalCard(
                repository: repo,
                busId: 'bus',
                date: '2030-01-01',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('সম্ভাব্য সময়:'), findsNothing);
      expect(
        find.textContaining('নির্বাচিত দিনের সময়সূচি'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
  testWidgets(
    'Location is requested only on tap; denial leaves manual stop planning available',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TransitRepository(store: MemoryStore());
      await repo.initialize(bundledJson: jsonEncode(arrivalFixture()));
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArrivalCard(
                repository: repo,
                busId: 'bus',
                dayType: 'regular',
                locate: () async {
                  requests++;
                  throw StateError('Location permission দেওয়া হয়নি।');
                },
              ),
            ),
          ),
        ),
      );
      expect(requests, 0);
      await tester.tap(find.text('আমার অবস্থান ব্যবহার করুন'));
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('Location permission দেওয়া হয়নি।'), findsOneWidget);
      expect(
        find.text('যাত্রা পরিকল্পনা'),
        findsOneWidget,
      );
      expect(find.textContaining('(+1 দিন)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'Fresh driver and student fixes show distance and ETA without saving student GPS',
    (tester) async {
      final store = MemoryStore();
      final repo = TransitRepository(store: store);
      final raw = arrivalFixture();
      await repo.initialize(bundledJson: jsonEncode(raw));
      repo.setConnection(true);
      for (final path in TransitRepository.catalogPaths) {
        repo.acceptCatalogNode(path, raw[path]);
      }
      repo.acceptLive({
        'bus': {
          'lat': 24.015,
          'lng': 89.0,
          'ts': repo.serverNow,
          'accuracy': 10,
          'sharing': true,
          'speedKmh': 20,
          'routeId': 'route',
          'tripId': 'session',
        },
      });
      StudentFix? marker;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ArrivalCard(
                repository: repo,
                busId: 'bus',
                onStudentLocation: (fix) => marker = fix,
                locate: () async => StudentFix(24.0197, 89, 15, DateTime.now()),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('আমার অবস্থান ব্যবহার করুন'));
      await tester.pumpAndSettle();
      expect(find.textContaining('আপনি → নির্বাচিত স্টপ:'), findsOneWidget);
      expect(
        find.textContaining('বাস → আপনার বর্তমান অবস্থান:'),
        findsOneWidget,
      );
      expect(find.textContaining('আনুমানিক '), findsWidgets);
      expect(find.textContaining('সম্ভাব্য সময়:'), findsOneWidget);
      expect(find.text('Middle → Destination'), findsOneWidget);
      expect(
        find.textContaining('এই দুই stop-এর মাঝে প্রায় 50%'),
        findsOneWidget,
      );
      expect(marker, isNotNull);
      await repo.flush();
      expect(jsonEncode(store.values), isNot(contains('24.0197')));
      await tester.tap(find.text('অবস্থান মুছুন'));
      await tester.pumpAndSettle();
      expect(marker, isNull);
      expect(find.textContaining('বাস → আপনার বর্তমান অবস্থান:'), findsNothing);
      repo.setConnection(false);
      await tester.pumpAndSettle();
      expect(find.text('Middle → Destination'), findsNothing);
      expect(find.textContaining('সম্ভাব্য সময়:'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );

  testWidgets(
    'Ten roster slots save a named draft without creating login assignments',
    (tester) async {
      final store = MemoryStore();
      final repo = TransitRepository(store: store);
      await repo.initialize(bundledJson: jsonEncode(arrivalFixture()));
      var assignments = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DriverRosterScreen(
            repository: repo,
            onAssign: (_) async {
              assignments++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/10 জনের তথ্য প্রস্তুত'), findsOneWidget);
      await tester.tap(find.text('তথ্য লিখুন').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'First driver');
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('1/10 জনের তথ্য প্রস্তুত'), findsOneWidget);
      final saved =
          jsonDecode(store.values['pust.admin.driverRoster.v1']!) as Map;
      expect((saved['slots'] as List).length, 10);
      expect(saved['slots'][0]['name'], 'First driver');
      expect(assignments, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      repo.dispose();
    },
  );
}
