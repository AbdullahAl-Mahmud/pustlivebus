import 'dart:async';

import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/arrival_estimator.dart';
import '../services/driver_navigation.dart';
import '../services/student_location.dart' show metersLabel;
import 'driver_route_map.dart';
import 'stop_journey.dart';

typedef DriverMapBuilder = Widget Function(
  BuildContext,
  TransitCatalog,
  FixedRoute,
  LiveBus?,
  bool,
);

class DriverNavigationPanel extends StatefulWidget {
  const DriverNavigationPanel({
    super.key,
    required this.catalog,
    required this.busId,
    required this.routeId,
    required this.fix,
    required this.tracking,
    required this.clock,
    this.startedAt,
    this.learning,
    this.onLocate,
    this.mapBuilder,
  });
  final TransitCatalog catalog;
  final String busId;
  final String? routeId;
  final LiveBus? fix;
  final bool tracking;
  final int Function() clock;
  final int? startedAt;
  final ArrivalLearning? learning;
  final VoidCallback? onLocate;
  final DriverMapBuilder? mapBuilder;
  @override
  State<DriverNavigationPanel> createState() => _DriverNavigationPanelState();
}

class _DriverNavigationPanelState extends State<DriverNavigationPanel> {
  Timer? _tick;
  final _mapUpdates = ValueNotifier<int>(0);
  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _mapUpdates.value++;
      }
    });
  }

  @override
  void didUpdateWidget(covariant DriverNavigationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapUpdates.value++;
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _mapUpdates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.clock();
    final date = dhakaTime(
      DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
    );
    final route = widget.catalog.routes[widget.routeId];
    if (route == null || route.stopIds.length < 2) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'নির্ধারিত route ও stop-এর তথ্য এখনও পাওয়া যায়নি। Reload assignment করুন।',
          ),
        ),
      );
    }
    final fix = widget.fix;
    final snapshot = DriverNavigationSnapshot.calculate(
      catalog: widget.catalog,
      route: route,
      fix: fix,
      now: now,
      confirmedLeg: fix == null
          ? null
          : widget.learning?.confirmedLeg(
              widget.busId,
              fix,
              widget.catalog,
              route,
            ),
    );
    final progress = snapshot.progress;
    final schedule = widget.catalog.trips
        .where(
          (trip) =>
              trip.busId == widget.busId &&
              trip.routeId == route.id &&
              trip.dayType == widget.catalog.dayType(date),
        )
        .toList();
    final ageSeconds = fix == null
        ? null
        : ((now - fix.timestamp) ~/ 1000).clamp(0, 999999);
    final elapsed = widget.startedAt == null || widget.startedAt! > now
        ? null
        : (now - widget.startedAt!) ~/ 60000;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('চলতি যাত্রা', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${driverClock(date)} · বাংলাদেশ সময়',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(dateLabel(date)),
            if (widget.startedAt != null)
              Text('Trip শুরু: ${driverArrivalClock(widget.startedAt!)}'),
            if (elapsed != null) Text('Trip-এর সময়: $elapsed মিনিট'),
            const SizedBox(height: 10),
            Text(
              route.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.tracking
                  ? 'Tracking চালু'
                  : 'Tracking বন্ধ · Private preview',
            ),
            if (fix == null)
              const Text(
                'ফোনের অবস্থান দেখতে GPS preview নিন অথবা Start trip করুন।',
              )
            else if (!snapshot.fresh)
              Text('শেষ জানা অবস্থান · GPS ${ageSeconds}s আগে')
            else
              Text(
                'GPS ${ageSeconds}s আগে · accuracy ±${fix.accuracy!.round()} m',
              ),
            if (!widget.tracking)
              OutlinedButton.icon(
                onPressed: widget.onLocate,
                icon: const Icon(Icons.my_location),
                label: const Text('আমার GPS preview'),
              ),
            const SizedBox(height: 12),
            if (snapshot.nearestStopIndex != null)
              Text(
                'কাছের stop: ${widget.catalog.stopName(route.stopIds[snapshot.nearestStopIndex!])} · ${metersLabel(snapshot.nearestMeters!)} সরলরেখায়',
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.map_outlined),
              label: const Text('Map দেখুন'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('চালকের map')),
                    body: AnimatedBuilder(
                      animation: _mapUpdates,
                      builder: (context, _) {
                        final currentRoute =
                            widget.catalog.routes[widget.routeId] ?? route;
                        final currentFix = widget.fix;
                        final fresh = DriverNavigationSnapshot.calculate(
                          catalog: widget.catalog,
                          route: currentRoute,
                          fix: currentFix,
                          now: widget.clock(),
                        ).fresh;
                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Text(currentRoute.name),
                            widget.mapBuilder?.call(
                                  context,
                                  widget.catalog,
                                  currentRoute,
                                  currentFix,
                                  fresh,
                                ) ??
                                DriverRouteMap(
                                  key: ValueKey(currentRoute.id),
                                  catalog: widget.catalog,
                                  route: currentRoute,
                                  fix: currentFix,
                                  fresh: fresh,
                                ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 28),
            StopJourney(
              catalog: widget.catalog,
              route: route,
              progress: progress,
              now: now,
              learning: widget.learning,
            ),
            if (schedule.isNotEmpty)
              Text(
                'আজকের নির্ধারিত departure: ${schedule.map((trip) => formatTime(trip.departTime)).join(' · ')}',
              ),
          ],
        ),
      ),
    );
  }
}
