import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit.dart';

/// Uses the assigned driver's local GPS, independent of student reference mode.
class DriverRouteMap extends StatefulWidget {
  const DriverRouteMap({
    super.key,
    required this.catalog,
    required this.route,
    required this.fix,
    required this.fresh,
  });
  final TransitCatalog catalog;
  final FixedRoute route;
  final LiveBus? fix;
  final bool fresh;
  @override
  State<DriverRouteMap> createState() => _DriverRouteMapState();
}

class _DriverRouteMapState extends State<DriverRouteMap> {
  final _map = MapController();
  bool _ready = false, _follow = true;

  @override
  void didUpdateWidget(covariant DriverRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fix = widget.fix;
    if (_ready &&
        _follow &&
        widget.fresh &&
        fix != null &&
        (fix.lat != oldWidget.fix?.lat || fix.lng != oldWidget.fix?.lng)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ready && _follow) {
          _map.move(LatLng(fix.lat, fix.lng), _map.camera.zoom);
        }
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stops = widget.route.stopIds
        .toSet()
        .map((id) => widget.catalog.stops[id])
        .whereType<BusStop>()
        .where((stop) => stop.hasCoordinates)
        .toList();
    final points = stops.map((stop) => LatLng(stop.lat!, stop.lng!)).toList();
    final fix = widget.fix;
    final center = fix != null
        ? LatLng(fix.lat, fix.lng)
        : points.firstOrNull ?? const LatLng(24.0144204, 89.2792439);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 255,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                initialCameraFit: fix == null && points.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(points),
                        padding: const EdgeInsets.all(32),
                      )
                    : null,
                onMapReady: () => _ready = true,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.pustlivebus.pustlivebus',
                ),
                PolylineLayer(
                  polylines: [
                    for (var i = 0; i + 1 < widget.route.stopIds.length; i++)
                      if (widget
                                  .catalog
                                  .stops[widget.route.stopIds[i]]
                                  ?.hasCoordinates ==
                              true &&
                          widget
                                  .catalog
                                  .stops[widget.route.stopIds[i + 1]]
                                  ?.hasCoordinates ==
                              true)
                        Polyline(
                          points: [
                            LatLng(
                              widget
                                  .catalog
                                  .stops[widget.route.stopIds[i]]!
                                  .lat!,
                              widget
                                  .catalog
                                  .stops[widget.route.stopIds[i]]!
                                  .lng!,
                            ),
                            LatLng(
                              widget
                                  .catalog
                                  .stops[widget.route.stopIds[i + 1]]!
                                  .lat!,
                              widget
                                  .catalog
                                  .stops[widget.route.stopIds[i + 1]]!
                                  .lng!,
                            ),
                          ],
                          strokeWidth: 4,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final stop in stops)
                      Marker(
                        point: LatLng(stop.lat!, stop.lng!),
                        width: 32,
                        height: 32,
                        child: Tooltip(
                          message: stop.name,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.deepOrange,
                            size: 28,
                          ),
                        ),
                      ),
                    if (fix != null)
                      Marker(
                        point: LatLng(fix.lat, fix.lng),
                        width: 48,
                        height: 48,
                        child: Tooltip(
                          message: widget.fresh
                              ? 'এই ফোনের বর্তমান GPS'
                              : 'শেষ জানা GPS',
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.fresh
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.directions_bus,
                              color: widget.fresh
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.grey,
                            ),
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
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: IconButton(
                  tooltip: _follow
                      ? 'GPS auto-follow বন্ধ করুন'
                      : 'নিজের GPS follow করুন',
                  icon: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
                  onPressed: () {
                    setState(() => _follow = !_follow);
                    if (_follow && _ready && fix != null) {
                      _map.move(LatLng(fix.lat, fix.lng), 15);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
