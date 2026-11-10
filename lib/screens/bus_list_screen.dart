import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'student_screen.dart';
import '../widgets/route_timeline.dart';

/// Weekdays that use the "holiday" schedule. Friday by default.
/// Change this set if the weekly holiday is different.
const Set<int> kHolidayWeekdays = {DateTime.friday};

const int _staleMs = 30000; // a bus is "Live" only if updated in the last 30s

// ---- colors ----
const Color _kGreen = Color(0xFF0E5C3C);
const Color _kGreenSoft = Color(0xFFE3F1EA);
const Color _kBg = Color(0xFFF3F5F4);
const Color _kText = Color(0xFF1B2A24);
const Color _kMuted = Color(0xFF6B7A73);

int? _toMinutes(String hhmm) {
  final p = hhmm.split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

String _fmtTime(String hhmm) {
  final total = _toMinutes(hhmm);
  if (total == null) return hhmm;
  final h = total ~/ 60;
  final m = total % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final suffix = h < 12 ? 'AM' : 'PM';
  return '$h12:${m.toString().padLeft(2, '0')} $suffix';
}

String _audienceLabel(String a) {
  switch (a) {
    case 'male':
      return 'Boys';
    case 'female':
      return 'Girls';
    default:
      return 'Boys & Girls';
  }
}

String _countdown(int diffMin) {
  if (diffMin <= 0) return 'Departing now';
  if (diffMin < 60) return 'in $diffMin min';
  final h = diffMin ~/ 60;
  final m = diffMin % 60;
  return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
}

class _BusInfo {
  final String id;
  final String name;
  final int number;

  _BusInfo(this.id, this.name, this.number);
}

class _Trip {
  final String busId;
  final String routeId;
  final String departTime; // "HH:mm"
  final String audience; // male | female | both
  final String dayType; // regular | holiday

  _Trip(this.busId, this.routeId, this.departTime, this.audience, this.dayType);

  int get minutes => _toMinutes(departTime) ?? 0;
}

class BusListScreen extends StatefulWidget {
  const BusListScreen({super.key});

  @override
  State<BusListScreen> createState() => _BusListScreenState();
}

class _BusListScreenState extends State<BusListScreen> {
  Map<String, _BusInfo> _buses = {};
  Map<String, String> _routeNames = {};
  Map<String, List<String>> _routeStops = {};
  Map<String, String> _stopNames = {};
  List<_Trip> _trips = [];
  Map<String, int> _liveTs = {}; // busId -> last update (only if sharing)

  bool _busesLoaded = false;
  bool _tripsLoaded = false;
  final Set<String> _failed = {};
  int _offsetMs = 0;
  int _filter = 0; // 0 = all, 1 = live now
  String _query = '';
  final _search = TextEditingController();

  final List<StreamSubscription<DatabaseEvent>> _subs = [];
  Timer? _tick;

  @override
  void initState() {
    super.initState();

    _subs.add(
      FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen((
        e,
      ) {
        final v = e.snapshot.value;
        if (v is num) _offsetMs = v.toInt();
      }),
    );
    _subs.add(
      _listen('buses', (v) {
        _buses = _parseBuses(v);
        _busesLoaded = true;
      }),
    );
    _subs.add(
      _listen('routes', (v) {
        _routeNames = _parseRouteNames(v);
        _routeStops = _parseRouteStops(v);
      }),
    );
    _subs.add(
      _listen('stops', (v) {
        _stopNames = _parseStopNames(v);
      }),
    );
    _subs.add(
      _listen('schedules', (v) {
        _trips = _parseTrips(v);
        _tripsLoaded = true;
      }),
    );
    _subs.add(
      _listen('live', (v) {
        _liveTs = _parseLive(v);
      }),
    );

    // Refresh countdowns and "Live" status every 5 seconds.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  StreamSubscription<DatabaseEvent> _listen(
    String path,
    void Function(Object? value) onData,
  ) {
    return FirebaseDatabase.instance
        .ref(path)
        .onValue
        .listen(
          (e) {
            if (!mounted) return;
            setState(() {
              onData(e.snapshot.value);
              _failed.remove(path);
            });
          },
          onError: (_) {
            if (mounted) setState(() => _failed.add(path));
          },
        );
  }

  // ---------- parsing ----------

  Map<String, _BusInfo> _parseBuses(Object? v) {
    final out = <String, _BusInfo>{};
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map && value['active'] != false) {
          final id = k.toString();
          final name = (value['nameBn'] ?? value['name'] ?? id).toString();
          final number = value['number'];
          out[id] = _BusInfo(id, name, number is num ? number.toInt() : 999);
        }
      });
    }
    return out;
  }

  Map<String, String> _parseRouteNames(Object? v) {
    final out = <String, String>{};
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map && value['name'] is String) {
          out[k.toString()] = value['name'] as String;
        }
      });
    }
    return out;
  }

  Map<String, List<String>> _parseRouteStops(Object? v) {
    final out = <String, List<String>>{};
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map) {
          final s = value['stops'];
          if (s is List) {
            out[k.toString()] = s.map((e) => e.toString()).toList();
          }
        }
      });
    }
    return out;
  }

  Map<String, String> _parseStopNames(Object? v) {
    final out = <String, String>{};
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map) {
          final n = value['nameBn'] ?? value['nameEn'];
          if (n is String) out[k.toString()] = n;
        }
      });
    }
    return out;
  }

  List<_Trip> _parseTrips(Object? v) {
    final out = <_Trip>[];
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map) {
          final t = value['departTime'];
          final b = value['busId'];
          final r = value['routeId'];
          if (t is String &&
              b is String &&
              r is String &&
              _toMinutes(t) != null) {
            out.add(
              _Trip(
                b,
                r,
                t,
                (value['audience'] ?? 'both').toString(),
                (value['dayType'] ?? 'regular').toString(),
              ),
            );
          }
        }
      });
    }
    return out;
  }

  Map<String, int> _parseLive(Object? v) {
    final out = <String, int>{};
    if (v is Map) {
      v.forEach((k, value) {
        if (value is Map && value['sharing'] == true && value['ts'] is num) {
          out[k.toString()] = (value['ts'] as num).toInt();
        }
      });
    }
    return out;
  }

  // ---------- logic ----------

  int get _serverNow => DateTime.now().millisecondsSinceEpoch + _offsetMs;

  int get _nowMinutes {
    final now = DateTime.fromMillisecondsSinceEpoch(
      _serverNow,
      isUtc: true,
    ).add(const Duration(hours: 6));
    return now.hour * 60 + now.minute;
  }

  bool _isLive(String busId) {
    final ts = _liveTs[busId];
    return ts != null && (_serverNow - ts) < _staleMs;
  }

  String get _todayType =>
      kHolidayWeekdays.contains(
        DateTime.fromMillisecondsSinceEpoch(
          _serverNow,
          isUtc: true,
        ).add(const Duration(hours: 6)).weekday,
      )
      ? 'holiday'
      : 'regular';

  List<_Trip> _todayTrips(String busId) {
    final type = _todayType;
    final list = _trips
        .where((t) => t.busId == busId && t.dayType == type)
        .toList();
    list.sort((a, b) => a.minutes.compareTo(b.minutes));
    return list;
  }

  _Trip? _nextTrip(String busId) {
    final nowMin = _nowMinutes;
    for (final t in _todayTrips(busId)) {
      if (t.minutes >= nowMin) return t;
    }
    return null;
  }

  String _routeName(String routeId) => _routeNames[routeId] ?? routeId;

  String _stopsLine(String routeId) {
    final ids = _routeStops[routeId];
    if (ids == null || ids.isEmpty) return '';
    return ids.map((id) => _stopNames[id] ?? id).join(' → ');
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final ready = _busesLoaded && _tripsLoaded;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PUST Bus', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'Live tracking & schedule',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Live map',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StudentScreen())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              if (_failed.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.all(10),
                  child: const Text(
                    'Could not load some data. Check your internet.',
                  ),
                ),
              Expanded(
                child: !ready
                    ? const Center(child: CircularProgressIndicator())
                    : _buildList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final all = _buses.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    if (all.isEmpty) {
      return const Center(child: Text('No buses found.'));
    }
    final liveCount = all.where((b) => _isLive(b.id)).length;
    final shown = all.where((b) {
      if (_filter == 1 && !_isLive(b.id)) return false;
      final routes = _trips
          .where((t) => t.busId == b.id)
          .map((t) => '${_routeName(t.routeId)} ${_stopsLine(t.routeId)}')
          .join(' ');
      return '${b.name} ${b.number} $routes'.toLowerCase().contains(_query);
    }).toList();
    final holidayWithoutTrips =
        _todayType == 'holiday' && !_trips.any((t) => t.dayType == 'holiday');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const Text(
          'Find your campus bus',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _kText,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Search a bus, route or stop. Open a bus to see its trips.',
          style: TextStyle(color: _kMuted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _search,
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Bus name, number, route or stop',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _FilterPill(
              label: 'All ${all.length}',
              selected: _filter == 0,
              onTap: () => setState(() => _filter = 0),
            ),
            const SizedBox(width: 8),
            _FilterPill(
              label: 'Live now $liveCount',
              selected: _filter == 1,
              onTap: () => setState(() => _filter = 1),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (holidayWithoutTrips)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'Today is a holiday. The holiday schedule has not been added yet.',
              style: TextStyle(color: _kText),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                _query.isNotEmpty
                    ? 'No matching buses. Try another name or stop.'
                    : 'No bus is live right now.',
                style: const TextStyle(color: _kMuted),
              ),
            ),
          )
        else
          for (final b in shown) _busCard(b),
      ],
    );
  }

  Widget _busCard(_BusInfo bus) {
    final trips = _todayTrips(bus.id);
    final next = _nextTrip(bus.id);
    final live = _isLive(bus.id);
    final nowMin = _nowMinutes;

    return GestureDetector(
      onTap: () => _showTrips(bus),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bus.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kText,
                    ),
                  ),
                ),
                _StatusChip(live: live),
              ],
            ),
            const SizedBox(height: 14),
            if (next != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'NEXT DEPARTURE',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w600,
                          color: _kMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtTime(next.departTime),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: _kText,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  _Pill(
                    text: _countdown(next.minutes - nowMin),
                    background: _kGreenSoft,
                    foreground: _kGreen,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.alt_route, size: 16, color: _kMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _routeName(next.routeId),
                      style: const TextStyle(color: _kMuted, fontSize: 13),
                    ),
                  ),
                  _Pill(
                    text: _audienceLabel(next.audience),
                    background: const Color(0xFFF0F2F1),
                    foreground: _kText,
                  ),
                ],
              ),
            ] else
              Text(
                trips.isEmpty ? 'No trips today' : 'No more trips today',
                style: const TextStyle(color: _kMuted, fontSize: 15),
              ),
            if (trips.isNotEmpty) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in trips)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TimeChip(
                          label: _fmtTime(t.departTime),
                          state: t.minutes < nowMin
                              ? 0
                              : (identical(t, next) ? 2 : 1),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showTrips(_BusInfo bus) {
    final trips = _todayTrips(bus.id);
    final nowMin = _nowMinutes;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DBD8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                bus.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _kText,
                ),
              ),
              const SizedBox(height: 2),
              const Text("Today's trips", style: TextStyle(color: _kMuted)),
              const SizedBox(height: 14),
              if (trips.isEmpty)
                const Text('No trips today.', style: TextStyle(color: _kMuted))
              else
                for (final t in trips)
                  Opacity(
                    opacity: t.minutes < nowMin ? 0.45 : 1,
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _fmtTime(t.departTime),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: _kText,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _routeName(t.routeId),
                                  style: const TextStyle(
                                    color: _kMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              _Pill(
                                text: _audienceLabel(t.audience),
                                background: Colors.white,
                                foreground: _kText,
                              ),
                            ],
                          ),
                          if (_stopsLine(t.routeId).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'SCHEDULED ROUTE',
                              style: TextStyle(
                                color: _kMuted,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            RouteTimeline(
                              stops: (_routeStops[t.routeId] ?? [])
                                  .map((id) => _stopNames[id] ?? id)
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _kText,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool live;

  const _StatusChip({required this.live});

  @override
  Widget build(BuildContext context) {
    final fg = live ? _kGreen : const Color(0xFF6B7A73);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live ? _kGreenSoft : const Color(0xFFEEF0EF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            live ? 'Live' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// state: 0 = already left, 1 = upcoming, 2 = next
class _TimeChip extends StatelessWidget {
  final String label;
  final int state;

  const _TimeChip({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    if (state == 2) {
      bg = _kGreen;
      fg = Colors.white;
    } else if (state == 1) {
      bg = _kGreenSoft;
      fg = _kGreen;
    } else {
      bg = const Color(0xFFF0F2F1);
      fg = const Color(0xFF9AA6A0);
    }
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
