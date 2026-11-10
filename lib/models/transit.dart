import 'dart:math' as math;

Map<String, dynamic> objectMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};

String normalizeSearch(String value) {
  const bn = '০১২৩৪৫৬৭৮৯';
  var result = value.trim().toLowerCase();
  for (var i = 0; i < bn.length; i++) {
    result = result.replaceAll(bn[i], '$i');
  }
  return result;
}

int? timeMinutes(String value) {
  final parts = normalizeSearch(value).split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

String formatTime(String value) {
  final minutes = timeMinutes(value);
  if (minutes == null) return value;
  final h = minutes ~/ 60;
  return '${h % 12 == 0 ? 12 : h % 12}:${(minutes % 60).toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

DateTime dhakaTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 6));
String dateLabel(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String audienceLabel(String value) => switch (value) {
  'male' => 'ছাত্র / Boys',
  'female' => 'ছাত্রী / Girls',
  _ => 'সবার জন্য / All',
};

class Bus {
  const Bus(this.id, this.name, this.englishName, this.number);
  final String id, name, englishName;
  final int number;
}

class BusStop {
  const BusStop(this.id, this.name, this.englishName, this.lat, this.lng);
  final String id, name, englishName;
  final double? lat, lng;
  bool get hasCoordinates => lat != null && lng != null;
}

class FixedRoute {
  const FixedRoute(this.id, this.name, this.stopIds);
  final String id, name;
  final List<String> stopIds;
}

class ScheduledTrip {
  const ScheduledTrip(
    this.id,
    this.busId,
    this.routeId,
    this.departTime,
    this.audience,
    this.dayType,
  );
  final String id, busId, routeId, departTime, audience, dayType;
  int get minutes => timeMinutes(departTime)!;
}

class TransitCatalog {
  TransitCatalog._(this.raw, this.buses, this.stops, this.routes, this.trips);
  final Map<String, dynamic> raw;
  final Map<String, Bus> buses;
  final Map<String, BusStop> stops;
  final Map<String, FixedRoute> routes;
  final List<ScheduledTrip> trips;
  Map<String, dynamic> get meta => objectMap(raw['meta']);

  factory TransitCatalog.parse(Map<String, dynamic> data) {
    final buses = <String, Bus>{};
    for (final entry in objectMap(data['buses']).entries) {
      final row = objectMap(entry.value);
      if (row.isEmpty || row['active'] == false) continue;
      buses[entry.key] = Bus(
        entry.key,
        '${row['nameBn'] ?? row['name'] ?? entry.key}',
        '${row['name'] ?? ''}',
        (num.tryParse('${row['number']}') ?? 999).toInt(),
      );
    }
    final stops = <String, BusStop>{};
    for (final entry in objectMap(data['stops']).entries) {
      final row = objectMap(entry.value);
      final lat = double.tryParse('${row['lat'] ?? row['latitude']}');
      final lng = double.tryParse('${row['lng'] ?? row['longitude']}');
      final valid =
          lat != null &&
          lng != null &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90 &&
          lng.abs() <= 180;
      stops[entry.key] = BusStop(
        entry.key,
        '${row['nameBn'] ?? row['nameEn'] ?? row['name'] ?? entry.key}',
        '${row['nameEn'] ?? row['name'] ?? ''}',
        valid ? lat : null,
        valid ? lng : null,
      );
    }
    final routes = <String, FixedRoute>{};
    for (final entry in objectMap(data['routes']).entries) {
      final row = objectMap(entry.value);
      final source = row['stops'];
      List<String> ids = [];
      if (source is List) {
        ids = source.where((e) => e != null).map((e) => e.toString()).toList();
      } else if (source is Map) {
        final items = objectMap(source).entries.toList()
          ..sort((a, b) {
            final ai = int.tryParse(a.key), bi = int.tryParse(b.key);
            return ai != null && bi != null
                ? ai.compareTo(bi)
                : a.key.compareTo(b.key);
          });
        ids = items.map((e) => e.value.toString()).toList();
      }
      if (row['active'] != false) {
        routes[entry.key] = FixedRoute(
          entry.key,
          '${row['nameBn'] ?? row['name'] ?? entry.key}',
          ids,
        );
      }
    }
    final trips = <ScheduledTrip>[];
    for (final entry in objectMap(data['schedules']).entries) {
      final row = objectMap(entry.value);
      final bus = row['busId'],
          route = row['routeId'],
          time = row['departTime'];
      if (row['active'] == false ||
          bus is! String ||
          route is! String ||
          time is! String ||
          timeMinutes(time) == null) {
        continue;
      }
      if (!buses.containsKey(bus) || !routes.containsKey(route)) continue;
      trips.add(
        ScheduledTrip(
          entry.key,
          bus,
          route,
          time,
          '${row['audience'] ?? 'both'}',
          '${row['dayType'] ?? 'regular'}',
        ),
      );
    }
    trips.sort((a, b) => a.minutes.compareTo(b.minutes));
    return TransitCatalog._(data, buses, stops, routes, trips);
  }

  String stopName(String id) => stops[id]?.name ?? id;
  String routeName(String id) => routes[id]?.name ?? id;
  String get searchText => buses.values.map((b) => b.name).join(' ');

  String dayType(DateTime date) {
    final exceptions = objectMap(raw['calendar']);
    final override = exceptions[dateLabel(date)];
    if (override == 'regular' || override == 'holiday') {
      return override as String;
    }
    final configured = meta['holidayWeekdays'];
    final holidays = configured is List
        ? configured.whereType<num>().map((e) => e.toInt()).toSet()
        : {DateTime.friday};
    return holidays.contains(date.weekday) ? 'holiday' : 'regular';
  }

  bool matchesBus(Bus bus, String query) {
    final text = StringBuffer('${bus.name} ${bus.englishName} ${bus.number} ');
    for (final trip in trips.where((t) => t.busId == bus.id)) {
      final route = routes[trip.routeId];
      if (route == null) continue;
      text.write('${route.name} ');
      for (final id in route.stopIds) {
        text.write('${stopName(id)} ${stops[id]?.englishName ?? ''} ');
      }
    }
    return normalizeSearch(text.toString()).contains(normalizeSearch(query));
  }
}

enum LocationState { live, stale, offline }

class LiveBus {
  const LiveBus(
    this.lat,
    this.lng,
    this.timestamp,
    this.sharing,
    this.speedKmh,
    this.routeId,
    this.tripId, [
    this.accuracy,
  ]);
  final double lat, lng;
  final int timestamp;
  final bool sharing;
  final double? speedKmh;
  final String? routeId, tripId;
  final double? accuracy;

  static LiveBus? parse(Object? value) {
    final row = objectMap(value);
    final lat = row['lat'], lng = row['lng'], ts = row['ts'];
    if (lat is! num ||
        lng is! num ||
        ts is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        !ts.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    final speed = row['speedKmh'];
    return LiveBus(
      lat.toDouble(),
      lng.toDouble(),
      row['capturedAt'] is num && (row['capturedAt'] as num).isFinite
          ? math.min(ts.toInt(), (row['capturedAt'] as num).toInt())
          : ts.toInt(),
      row['sharing'] == true,
      speed is num && speed.isFinite && speed >= 0 && speed <= 150
          ? speed.toDouble()
          : null,
      row['routeId'] is String ? row['routeId'] as String : null,
      row['tripId'] is String ? row['tripId'] as String : null,
      row['accuracy'] is num &&
              (row['accuracy'] as num).isFinite &&
              (row['accuracy'] as num) >= 0
          ? (row['accuracy'] as num).toDouble()
          : null,
    );
  }

  LocationState state(int now, bool connected) {
    if (!sharing) return LocationState.offline;
    final age = now - timestamp;
    return connected && age >= -5000 && age < 30000
        ? LocationState.live
        : LocationState.stale;
  }
}

double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final a =
      math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(a.clamp(0, 1)));
}
