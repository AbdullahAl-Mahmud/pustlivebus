import 'dart:convert';
import 'dart:math' as math;

import '../models/transit.dart';

/// Stop occurrences are indexed: an outward stop and its return visit differ.
class RouteProjection {
  const RouteProjection(this.leg, this.fraction, this.offRouteMeters);
  final int leg;
  final double fraction, offRouteMeters;
}

class ArrivalEstimate {
  const ArrivalEstimate(
    this.minutes,
    this.sketchMeters,
    this.learnedLegs,
    this.totalLegs,
  );
  final double minutes, sketchMeters;
  final int learnedLegs, totalLegs;
  int get lowerMinutes => math.max(1, (minutes * .7).floor());
  int get upperMinutes =>
      math.max(lowerMinutes + 1, (minutes * 1.5 + 2).ceil());
  String get range => '$lowerMinutes–$upperMinutes min';
}

double? legMeters(TransitCatalog catalog, FixedRoute route, int leg) {
  if (leg < 0 || leg + 1 >= route.stopIds.length) return null;
  final a = catalog.stops[route.stopIds[leg]];
  final b = catalog.stops[route.stopIds[leg + 1]];
  if (a?.hasCoordinates != true || b?.hasCoordinates != true) return null;
  return distanceMeters(a!.lat!, a.lng!, b!.lat!, b.lng!);
}

String routeSignature(TransitCatalog catalog, FixedRoute route) => jsonEncode([
  route.id,
  for (final id in route.stopIds)
    [id, catalog.stops[id]?.lat, catalog.stops[id]?.lng],
]);

/// A projection on the stop sketch, not a road routing result. Withhold a
/// direction when separate outward/return legs fit the same fix equally well.
RouteProjection? projectOnRoute(
  TransitCatalog catalog,
  FixedRoute route,
  double lat,
  double lng, {
  int? confirmedLeg,
}) {
  final candidates = <RouteProjection>[];
  for (var i = 0; i + 1 < route.stopIds.length; i++) {
    if (confirmedLeg != null && i != confirmedLeg) continue;
    final length = legMeters(catalog, route, i);
    if (length == null || length < 10) continue;
    final a = catalog.stops[route.stopIds[i]]!;
    final b = catalog.stops[route.stopIds[i + 1]]!;
    final scale = math.cos(lat * math.pi / 180);
    final ax = (a.lng! - lng) * scale, ay = a.lat! - lat;
    final bx = (b.lng! - lng) * scale, by = b.lat! - lat;
    final dx = bx - ax, dy = by - ay;
    final fraction = (-(ax * dx + ay * dy) / (dx * dx + dy * dy)).clamp(
      0.0,
      1.0,
    );
    final nearLat = a.lat! + (b.lat! - a.lat!) * fraction;
    final nearLng = a.lng! + (b.lng! - a.lng!) * fraction;
    final away = distanceMeters(lat, lng, nearLat, nearLng);
    if (away <= 250) candidates.add(RouteProjection(i, fraction, away));
  }
  candidates.sort((a, b) => a.offRouteMeters.compareTo(b.offRouteMeters));
  if (candidates.isEmpty) return null;
  final best = candidates.first;
  for (final other in candidates.skip(1)) {
    if (other.offRouteMeters > best.offRouteMeters + 40) continue;
    // Adjacent legs may both match the same junction; that is one occurrence.
    final atSameJunction =
        (other.leg - best.leg).abs() == 1 &&
        ((best.fraction > .85 &&
                other.fraction < .15 &&
                other.leg > best.leg) ||
            (other.fraction > .85 &&
                best.fraction < .15 &&
                best.leg > other.leg));
    if (!atSameJunction) return null;
  }
  return best;
}

ArrivalEstimate? estimateArrival({
  required TransitCatalog catalog,
  required FixedRoute route,
  required int destination,
  RouteProjection? from,
  ArrivalLearning? learning,
  double planningSpeedKmh = 20,
  double stopWaitMinutes = .5,
}) {
  if (destination < 0 ||
      destination >= route.stopIds.length ||
      !planningSpeedKmh.isFinite ||
      planningSpeedKmh < 5 ||
      planningSpeedKmh > 60 ||
      !stopWaitMinutes.isFinite ||
      stopWaitMinutes < 0 ||
      stopWaitMinutes > 5) {
    return null;
  }
  final firstLeg = from?.leg ?? 0;
  if (destination <= firstLeg) return null;
  double minutes = 0, meters = 0;
  var learned = 0;
  for (var leg = firstLeg; leg < destination; leg++) {
    final distance = legMeters(catalog, route, leg);
    if (distance == null) return null; // Never bridge missing coordinates.
    final fraction = leg == firstLeg ? 1 - (from?.fraction ?? 0) : 1.0;
    final measured = learning?.legMinutes(catalog, route, leg);
    // Explicit planning assumption, not measured road distance or traffic data.
    final travel = measured ?? distance * 1.25 / 1000 / planningSpeedKmh * 60;
    minutes += travel * fraction;
    meters += distance * fraction;
    if (measured != null) learned++;
    if (leg + 1 < destination) minutes += stopWaitMinutes;
  }
  return ArrivalEstimate(minutes, meters, learned, destination - firstLeg);
}

class _Journey {
  _Journey(this.trip, this.signature, this.stop, this.at, this.lastFix);
  final String trip, signature;
  int stop, at, lastFix;
}

/// Learns only from fresh official driver fixes while this app is open.
/// Persists bounded per-leg travel durations; no student GPS or raw traces.
class ArrivalLearning {
  final Map<String, Map<String, List<double>>> _profiles = {};
  final Map<String, _Journey> _journeys = {};
  int get sampleCount => _profiles.values.fold(
    0,
    (sum, legs) =>
        sum + legs.values.fold(0, (count, samples) => count + samples.length),
  );

  Map<String, dynamic> toJson() => {'version': 1, 'profiles': _profiles};
  void restore(Object? saved) {
    final root = objectMap(saved);
    if (root['version'] != 1) return;
    for (final entry in objectMap(root['profiles']).entries.take(60)) {
      final legs = <String, List<double>>{};
      for (final leg in objectMap(entry.value).entries.take(100)) {
        if (int.tryParse(leg.key) == null || leg.value is! List) continue;
        legs[leg.key] = (leg.value as List)
            .whereType<num>()
            .where((v) => v.isFinite && v >= .2 && v <= 180)
            .take(12)
            .map((v) => v.toDouble())
            .toList();
      }
      _profiles[entry.key] = legs;
    }
  }

  double? legMinutes(TransitCatalog catalog, FixedRoute route, int leg) {
    final values = _profiles[routeSignature(catalog, route)]?['$leg'];
    if (values == null || values.length < 3) return null;
    final sorted = [...values]..sort();
    // Median resists occasional GPS/geofence timing outliers.
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  int? confirmedLeg(
    String busId,
    LiveBus fix,
    TransitCatalog catalog,
    FixedRoute route,
  ) {
    final journey = _journeys[busId];
    if (journey?.trip != fix.tripId ||
        journey?.signature != routeSignature(catalog, route) ||
        journey!.stop + 1 >= route.stopIds.length) {
      return null;
    }
    return journey.stop;
  }

  bool observe(
    String busId,
    LiveBus fix,
    TransitCatalog catalog,
    int now,
    bool connected,
  ) {
    final route = catalog.routes[fix.routeId];
    if (!catalog.buses.containsKey(busId) ||
        fix.state(now, connected) != LocationState.live ||
        fix.tripId == null ||
        route == null ||
        fix.accuracy == null ||
        fix.accuracy! > 60) {
      _journeys.remove(busId);
      return false;
    }
    final signature = routeSignature(catalog, route);
    var journey = _journeys[busId];
    if (journey != null &&
        (journey.trip != fix.tripId ||
            journey.signature != signature ||
            fix.timestamp - journey.lastFix > 45000)) {
      _journeys.remove(busId);
      journey = null;
    }
    double away(int index) {
      final stop = catalog.stops[route.stopIds[index]];
      return stop?.hasCoordinates == true
          ? distanceMeters(fix.lat, fix.lng, stop!.lat!, stop.lng!)
          : double.infinity;
    }

    if (journey == null) {
      // Repeated stops cannot establish outward/return direction on their own.
      final near = [
        for (var i = 0; i < route.stopIds.length; i++)
          if (away(i) <= 80) i,
      ];
      if (near.length == 1) {
        _journeys[busId] = _Journey(
          fix.tripId!,
          signature,
          near.single,
          fix.timestamp,
          fix.timestamp,
        );
      }
      return false;
    }
    if (fix.timestamp <= journey.lastFix) return false;
    journey.lastFix = fix.timestamp;
    if (away(journey.stop) <= 80) {
      journey.at = fix.timestamp;
      return false;
    }
    final next = journey.stop + 1;
    if (next >= route.stopIds.length ||
        away(next) > 80 ||
        (legMeters(catalog, route, journey.stop) ?? 0) < 160) {
      return false;
    }
    final minutes = (fix.timestamp - journey.at) / 60000;
    var changed = false;
    final speedKmh =
        (legMeters(catalog, route, journey.stop) ?? 0) / 1000 / (minutes / 60);
    if (minutes >= .2 && minutes <= 180 && speedKmh <= 100) {
      if (!_profiles.containsKey(signature) && _profiles.length >= 60) {
        _profiles.remove(_profiles.keys.first);
      }
      final samples = (_profiles[signature] ??= {})['${journey.stop}'] ??= [];
      samples.add(minutes);
      if (samples.length > 12) samples.removeAt(0);
      changed = true;
    }
    journey.stop = next;
    journey.at = fix.timestamp;
    return changed;
  }

  void resetJourneys() => _journeys.clear();
  void clear() {
    _profiles.clear();
    _journeys.clear();
  }
}
