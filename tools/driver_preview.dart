// Local visual QA entrypoint only. Not used by the published application.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pustlivebus/models/transit.dart';
import 'package:pustlivebus/services/arrival_estimator.dart';
import 'package:pustlivebus/theme/app_brand.dart';
import 'package:pustlivebus/widgets/driver_navigation_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = TransitCatalog.parse(
    objectMap(
      jsonDecode(
        await rootBundle.loadString('assets/data/offline_catalog.json'),
      ),
    ),
  );
  final route = catalog.routes['town_reverse']!;
  final now = DateTime.now().millisecondsSinceEpoch;
  LiveBus? position;
  for (var i = 0; i + 1 < route.stopIds.length; i++) {
    final a = catalog.stops[route.stopIds[i]]!,
        b = catalog.stops[route.stopIds[i + 1]]!;
    if (!a.hasCoordinates || !b.hasCoordinates) continue;
    final lat = (a.lat! + b.lat!) / 2, lng = (a.lng! + b.lng!) / 2;
    if (projectOnRoute(catalog, route, lat, lng) != null) {
      position = LiveBus(lat, lng, now, true, 22, route.id, 'local-demo', 12);
      break;
    }
  }
  if (position == null) {
    throw StateError('Choose an unambiguous local demo segment.');
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppBrand.theme(Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('Driver interface · Preview')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const Text('Demo GPS preview · কোনো live bus নয়'),
                DriverNavigationPanel(
                  catalog: catalog,
                  busId: 'bus04',
                  routeId: route.id,
                  fix: position,
                  tracking: true,
                  clock: () => now,
                  startedAt: now - 600000,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
