import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit.dart';
import '../services/transit_repository.dart';
import '../services/student_location.dart';
import '../widgets/arrival_card.dart';

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({
    super.key,
    required this.repository,
    this.busId,
    this.routeId,
  });
  final TransitRepository repository;
  final String? busId, routeId;
  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final _controller = MapController();
  bool _ready = false;
  StudentFix? _student;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final repo = widget.repository;
      final catalog = repo.catalog!;
      final selected = repo.isReference ? null : repo.live[widget.busId];
      final route = catalog.routes[widget.routeId ?? selected?.routeId];
      final stopIds = route?.stopIds ?? <String>[];
      final stops = stopIds
          .toSet()
          .map((id) => catalog.stops[id])
          .whereType<BusStop>()
          .where((s) => s.hasCoordinates)
          .toList();
      final points = stops.map((s) => LatLng(s.lat!, s.lng!)).toList();
      final positions = repo.isReference
          ? <MapEntry<String, LiveBus>>[]
          : repo.live.entries
                .where((e) => widget.busId == null || e.key == widget.busId)
                .toList();
      final initial = selected != null
          ? LatLng(selected.lat, selected.lng)
          : points.isNotEmpty
          ? points.first
          : const LatLng(24.0144204, 89.2792439);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            route?.name ?? catalog.buses[widget.busId]?.name ?? 'Live bus map',
          ),
        ),
        body: Column(
          children: [
            if (!repo.connected || repo.isReference)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Live GPS and map tiles need internet. Saved stop lists are available in Fixed Routes.',
                ),
              ),
            if (route != null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Lines connect known stops as a route sketch; they do not trace the road. Missing coordinates are left as gaps.',
                ),
              ),
            Expanded(
              child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCenter: initial,
                  initialZoom: 13,
                  initialCameraFit: selected == null && points.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(points),
                          padding: const EdgeInsets.all(40),
                        )
                      : null,
                  onMapReady: () => _ready = true,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.pustlivebus.pustlivebus',
                  ),
                  if (route != null)
                    PolylineLayer(
                      polylines: [
                        for (var i = 0; i < stopIds.length - 1; i++)
                          if (catalog.stops[stopIds[i]]?.hasCoordinates ==
                                  true &&
                              catalog.stops[stopIds[i + 1]]?.hasCoordinates ==
                                  true)
                            Polyline(
                              points: [
                                LatLng(
                                  catalog.stops[stopIds[i]]!.lat!,
                                  catalog.stops[stopIds[i]]!.lng!,
                                ),
                                LatLng(
                                  catalog.stops[stopIds[i + 1]]!.lat!,
                                  catalog.stops[stopIds[i + 1]]!.lng!,
                                ),
                              ],
                              strokeWidth: 4,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      if (_student?.fresh == true)
                        Marker(
                          point: LatLng(_student!.lat, _student!.lng),
                          width: 42,
                          height: 42,
                          child: const Tooltip(
                            message: 'আপনার বর্তমান অবস্থান',
                            child: Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 38,
                            ),
                          ),
                        ),
                      for (final stop in stops)
                        Marker(
                          point: LatLng(stop.lat!, stop.lng!),
                          width: 36,
                          height: 36,
                          child: Tooltip(
                            message: stop.name,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.deepOrange,
                              size: 28,
                            ),
                          ),
                        ),
                      for (final entry in positions)
                        Marker(
                          point: LatLng(entry.value.lat, entry.value.lng),
                          width: 110,
                          height: 66,
                          child: Tooltip(
                            message:
                                '${catalog.buses[entry.key]?.name ?? entry.key} · ${repo.locationState(entry.key).name}',
                            child: Column(
                              children: [
                                Icon(
                                  Icons.directions_bus,
                                  size: 32,
                                  color:
                                      repo.locationState(entry.key) ==
                                          LocationState.live
                                      ? Colors.green.shade700
                                      : Colors.grey.shade700,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                  ),
                                  color: Theme.of(context).colorScheme.surface,
                                  child: Text(
                                    repo.locationState(entry.key) ==
                                            LocationState.live
                                        ? 'Live GPS'
                                        : 'Last known',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SimpleAttributionWidget(
                    source: Text('© OpenStreetMap contributors'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ArrivalCard(
                    repository: repo,
                    busId: widget.busId,
                    routeId: widget.routeId,
                    onStudentLocation: (fix) => setState(() => _student = fix),
                  ),
                  if (positions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No driver location is available for this selection.',
                      ),
                    ),
                  for (final entry in positions)
                    ListTile(
                      leading: const Icon(Icons.directions_bus),
                      title: Text(catalog.buses[entry.key]?.name ?? entry.key),
                      subtitle: Text(
                        '${repo.locationState(entry.key) == LocationState.live ? 'Live GPS' : 'Last known location'} · ${entry.value.speedKmh?.round() ?? '—'} km/h',
                      ),
                      trailing: const Icon(Icons.my_location),
                      onTap: () {
                        if (_ready) {
                          _controller.move(
                            LatLng(entry.value.lat, entry.value.lng),
                            16,
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
