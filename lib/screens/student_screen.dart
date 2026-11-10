import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class _BusLive {
  final double lat;
  final double lng;
  final int ts;
  final bool sharing;

  _BusLive(this.lat, this.lng, this.ts, this.sharing);
}

class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  static const LatLng _center = LatLng(24.0064, 89.2372);
  static const int _staleMs = 30000; // ৩০ সেকেন্ডের পুরনো হলে stale

  final MapController _map = MapController();
  final Map<String, String> _names = {};
  Map<String, _BusLive> _live = {};
  int _offsetMs = 0;
  bool _loaded = false;
  String? _error;

  StreamSubscription<DatabaseEvent>? _liveSub;
  StreamSubscription<DatabaseEvent>? _offsetSub;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _offsetSub = FirebaseDatabase.instance
        .ref('.info/serverTimeOffset')
        .onValue
        .listen((e) {
          final v = e.snapshot.value;
          if (v is num) _offsetMs = v.toInt();
        });
    _liveSub = FirebaseDatabase.instance
        .ref('live')
        .onValue
        .listen(
          (e) {
            final result = <String, _BusLive>{};
            final v = e.snapshot.value;
            if (v is Map) {
              v.forEach((key, value) {
                if (value is Map) {
                  final lat = value['lat'];
                  final lng = value['lng'];
                  final ts = value['ts'];
                  if (lat is num && lng is num && ts is num) {
                    result[key.toString()] = _BusLive(
                      lat.toDouble(),
                      lng.toDouble(),
                      ts.toInt(),
                      value['sharing'] == true,
                    );
                  }
                }
              });
            }
            if (mounted) {
              setState(() {
                _live = result;
                _loaded = true;
                _error = null;
              });
            }
          },
          onError: (_) {
            if (mounted) {
              setState(
                () => _error = 'Could not load live data. Check your internet.',
              );
            }
          },
        );
    // প্রতি ৫ সেকেন্ডে stale অবস্থা আবার হিসাব করার জন্য
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _offsetSub?.cancel();
    _tick?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('buses').get();
      final v = snap.value;
      if (v is Map) {
        v.forEach((key, value) {
          final n = value is Map ? (value['nameBn'] ?? value['name']) : null;
          if (n is String) {
            _names[key.toString()] = n;
          }
        });
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  int get _serverNow => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  bool _isFresh(_BusLive b) => b.sharing && (_serverNow - b.ts) < _staleMs;

  String _status(_BusLive b) {
    if (!b.sharing) return 'Not sharing';
    final sec = ((_serverNow - b.ts) / 1000).round();
    if (sec < 0) return 'Live';
    if (!_isFresh(b)) return 'Stale (last seen ${sec}s ago)';
    return 'Live (${sec}s ago)';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _live.entries.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Live Buses')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                    initialCenter: _center,
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pustlivebus.pustlivebus',
                    ),
                    MarkerLayer(
                      markers: [
                        for (final e in entries)
                          if (e.value.sharing)
                            Marker(
                              point: LatLng(e.value.lat, e.value.lng),
                              width: 80,
                              height: 60,
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.directions_bus,
                                    size: 32,
                                    color: _isFresh(e.value)
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    color: Colors.white70,
                                    child: Text(
                                      _names[e.key] ?? e.key,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                    const SimpleAttributionWidget(
                      source: Text('© OpenStreetMap contributors'),
                    ),
                  ],
                ),
                if (_error != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(_error!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 160,
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? const Center(
                    child: Text('No bus is sharing its location right now.'),
                  )
                : ListView(
                    children: [
                      for (final e in entries)
                        ListTile(
                          leading: Icon(
                            Icons.directions_bus,
                            color: _isFresh(e.value)
                                ? Colors.green
                                : Colors.grey,
                          ),
                          title: Text(_names[e.key] ?? e.key),
                          subtitle: Text(_status(e.value)),
                          onTap: e.value.sharing
                              ? () => _map.move(
                                  LatLng(e.value.lat, e.value.lng),
                                  16,
                                )
                              : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
