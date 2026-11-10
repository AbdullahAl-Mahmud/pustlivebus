import '../models/transit.dart';

/// Shared by the admin editor and tests. Rejects invalid references before write.
String? validateCatalogRecord(
  String kind,
  Map<String, dynamic> row,
  Map<String, dynamic> data,
) {
  bool exists(String table, Object? id) =>
      id is String &&
      objectMap(data[table]).containsKey(id) &&
      objectMap(objectMap(data[table])[id])['active'] != false;
  bool named() => '${row['nameBn'] ?? row['name'] ?? ''}'.trim().isNotEmpty;
  switch (kind) {
    case 'buses':
      if (!named()) return 'Enter a bus name.';
      final number = row['number'];
      if (number is! int || number < 1) {
        return 'Enter a positive whole bus number.';
      }
    case 'stops':
      if (!named()) return 'Enter a stop name.';
      final lat = row['lat'], lng = row['lng'];
      if ((lat == null) != (lng == null)) {
        return 'Enter both latitude and longitude, or leave both empty.';
      }
      if (lat != null &&
          (lat is! num ||
              lng is! num ||
              !lat.isFinite ||
              !lng.isFinite ||
              lat.abs() > 90 ||
              lng.abs() > 180)) {
        return 'Coordinates are outside the valid range.';
      }
    case 'routes':
      if (!named()) return 'Enter a route name.';
      final stops = row['stops'];
      if (stops is! List || stops.length < 2) {
        return 'A route needs at least two stops.';
      }
      if (!stops.every((id) => exists('stops', id))) {
        return 'Choose existing active stops for this route.';
      }
    case 'schedules':
      if (!exists('buses', row['busId'])) return 'Choose an active bus.';
      if (!exists('routes', row['routeId'])) return 'Choose an active route.';
      if (row['departTime'] is! String ||
          timeMinutes(row['departTime']) == null) {
        return 'Use a valid 24-hour departure time, for example 08:10.';
      }
      if (!['regular', 'holiday'].contains(row['dayType'])) {
        return 'Choose Regular or Holiday.';
      }
      if (!['male', 'female', 'both'].contains(row['audience'])) {
        return 'Choose the passenger group.';
      }
    case 'drivers':
      if (!exists('buses', row['busId'])) return 'Choose an active bus.';
      if ('${row['name'] ?? ''}'.trim().isEmpty) return 'Enter a driver name.';
    default:
      return 'Unknown record type.';
  }
  return null;
}
