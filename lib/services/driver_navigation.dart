import '../models/transit.dart';
import 'arrival_estimator.dart';

class DriverNavigationSnapshot {
  const DriverNavigationSnapshot(
    this.fresh,
    this.nearestStopIndex,
    this.nearestMeters,
    this.progress,
  );
  final bool fresh;
  final int? nearestStopIndex;
  final double? nearestMeters;
  final RouteProjection? progress;
  int? get nextStopIndex => progress == null ? null : progress!.leg + 1;

  factory DriverNavigationSnapshot.calculate({
    required TransitCatalog catalog,
    required FixedRoute route,
    required LiveBus? fix,
    required int now,
    int? confirmedLeg,
  }) {
    final age = fix == null ? null : now - fix.timestamp;
    final fresh =
        fix != null &&
        age! >= -5000 &&
        age < 30000 &&
        fix.lat.isFinite &&
        fix.lng.isFinite &&
        fix.lat.abs() <= 90 &&
        fix.lng.abs() <= 180 &&
        fix.accuracy != null &&
        fix.accuracy!.isFinite &&
        fix.accuracy! >= 0 &&
        fix.accuracy! <= 100;
    if (!fresh) return const DriverNavigationSnapshot(false, null, null, null);
    int? nearest;
    double? nearestMeters;
    for (var i = 0; i < route.stopIds.length; i++) {
      final stop = catalog.stops[route.stopIds[i]];
      if (stop?.hasCoordinates != true) continue;
      final away = distanceMeters(fix.lat, fix.lng, stop!.lat!, stop.lng!);
      if (nearestMeters == null || away < nearestMeters) {
        nearest = i;
        nearestMeters = away;
      }
    }
    final progress = fix.routeId == route.id
        ? projectOnRoute(
            catalog,
            route,
            fix.lat,
            fix.lng,
            confirmedLeg: confirmedLeg,
          )
        : null;
    return DriverNavigationSnapshot(true, nearest, nearestMeters, progress);
  }
}

String driverClock(DateTime dhakaDate) =>
    '${dhakaDate.hour.toString().padLeft(2, '0')}:${dhakaDate.minute.toString().padLeft(2, '0')}:${dhakaDate.second.toString().padLeft(2, '0')}';

String driverArrivalClock(int timestamp) {
  final date = dhakaTime(
    DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
  );
  return '${dateLabel(date)} · ${formatTime('${date.hour}:${date.minute.toString().padLeft(2, '0')}')}';
}
