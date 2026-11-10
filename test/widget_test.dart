import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/main.dart';
import 'package:pustlivebus/widgets/route_timeline.dart';
import 'package:pustlivebus/screens/transit_home.dart';
import 'package:pustlivebus/services/transit_repository.dart';

import 'transit_repository_test.dart' show MemoryStore;

void main() {
  testWidgets('Offline student tabs and details work on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = TransitRepository(
      store: MemoryStore(),
      clock: () => DateTime.utc(2026, 10, 31, 0),
    );
    await repository.initialize(
      bundledJson: File('assets/data/offline_catalog.json').readAsStringSync(),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: TransitHome(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Included offline timetable · Reference copy'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Routes').last);
    await tester.pumpAndSettle();
    expect(find.text('Fixed Routes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ক্যাম্পাস → শহর → ক্যাম্পাস'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('ক্যাম্পাস → শহর → ক্যাম্পাস'));
    await tester.pumpAndSettle();
    expect(find.text('মোজাহিদ ক্লাব'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Board').last);
    await tester.pumpAndSettle();
    expect(find.text('Departure Board'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Offline').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ইন্টারনেট ছাড়াও প্রস্তুত'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ইন্টারনেট ছাড়াও প্রস্তুত'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
  });
  testWidgets('Welcome fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const RoleScreen(),
      ),
    );
    expect(find.text('I am a Student'), findsOneWidget);
    expect(find.text('I am a Driver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Timeline preserves repeated stops on a return route', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteTimeline(stops: ['Campus', 'Terminal', 'Campus']),
        ),
      ),
    );
    expect(find.text('Campus'), findsNWidgets(2));
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
