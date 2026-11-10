import 'dart:async';

import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/arrival_estimator.dart';
import '../services/student_location.dart';
import '../services/transit_repository.dart';
import 'stop_journey.dart';

class ArrivalCard extends StatefulWidget {
  const ArrivalCard({
    super.key,
    required this.repository,
    this.busId,
    this.routeId,
    this.date,
    this.dayType,
    this.onStudentLocation,
    this.locate,
  });
  final TransitRepository repository;
  final String? busId, routeId, date, dayType;
  final ValueChanged<StudentFix?>? onStudentLocation;
  final Future<StudentFix> Function()? locate;
  @override
  State<ArrivalCard> createState() => _ArrivalCardState();
}

class _ArrivalCardState extends State<ArrivalCard> {
  String? _bus, _route, _departure, _message;
  int? _destination;
  double _speed = 20;
  StudentFix? _student;
  bool _locating = false;

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      final fix = await (widget.locate ?? requestStudentLocation)();
      if (!mounted) return;
      setState(() {
        _student = fix;
        _destination = null;
      });
      widget.onStudentLocation?.call(fix);
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _message =
              'Location পেতে সময় লাগছে। আবার চেষ্টা করুন অথবা স্টপ বেছে নিন।',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is StateError ? error.message : 'Location পাওয়া যায়নি। Permission এবং GPS পরীক্ষা করুন, অথবা স্টপ বেছে নিন।',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Widget _select<T>(
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items,
      onChanged: change,
    ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.repository,
    builder: (context, _) {
      final repo = widget.repository, catalog = widget.repository.catalog!;
      final buses = catalog.buses.values
          .where(
            (bus) =>
                widget.routeId == null ||
                catalog.trips.any(
                  (trip) =>
                      trip.busId == bus.id && trip.routeId == widget.routeId,
                ) ||
                (!repo.isReference &&
                    repo.live[bus.id]?.routeId == widget.routeId),
          )
          .toList();
      final busId =
          widget.busId ??
          (buses.any((bus) => bus.id == _bus) ? _bus : buses.firstOrNull?.id);
      final currentSchedule =
          (widget.date == null || widget.date == dateLabel(repo.now)) &&
          (widget.dayType == null ||
              widget.dayType == catalog.dayType(repo.now));
      final position = repo.isReference || !currentSchedule
          ? null
          : repo.live[busId];
      final live =
          currentSchedule &&
          busId != null &&
          repo.locationState(busId) == LocationState.live;
      final routeIds = {
        if (widget.routeId != null &&
            catalog.routes.containsKey(widget.routeId))
          widget.routeId!,
        if (widget.routeId == null)
          ...catalog.trips.where((t) => t.busId == busId).map((t) => t.routeId),
        if (widget.routeId == null &&
            live &&
            catalog.routes.containsKey(position?.routeId))
          position!.routeId!,
      };
      final routeId = routeIds.contains(_route)
          ? _route
          : routeIds.contains(position?.routeId)
          ? position?.routeId
          : routeIds.firstOrNull;
      final candidateRoute = catalog.routes[routeId];
      final route = candidateRoute != null && candidateRoute.stopIds.length >= 2
          ? candidateRoute
          : null;
      final student = _student?.fresh == true ? _student : null;
      RouteProjection? projection;
      if (live &&
          route != null &&
          position!.routeId == route.id &&
          position.accuracy != null &&
          position.accuracy! <= 100) {
        projection = projectOnRoute(
          catalog,
          route,
          position.lat,
          position.lng,
          confirmedLeg: repo.arrivalLearning.confirmedLeg(
            busId,
            position,
            catalog,
            route,
          ),
        );
      }
      var destination =
          route != null &&
              _destination != null &&
              _destination! < route.stopIds.length
          ? _destination!
          : (route?.stopIds.length ?? 1) - 1;
      double? studentToStop;
      if (route != null && student != null) {
        var closest = double.infinity;
        var closestIndex = -1;
        for (var i = 0; i < route.stopIds.length; i++) {
          final stop = catalog.stops[route.stopIds[i]];
          if (stop?.hasCoordinates != true) continue;
          final distance = distanceMeters(
            student.lat,
            student.lng,
            stop!.lat!,
            stop.lng!,
          );
          if (distance < closest - 1 ||
              ((distance - closest).abs() <= 1 &&
                  projection != null &&
                  closestIndex <= projection.leg &&
                  i > projection.leg)) {
            closest = distance;
            closestIndex = i;
          }
        }
        if (_destination == null && closestIndex >= 0) {
          destination = closestIndex;
        }
        final stop = catalog.stops[route.stopIds[destination]];
        if (stop?.hasCoordinates == true) {
          studentToStop = distanceMeters(
            student.lat,
            student.lng,
            stop!.lat!,
            stop.lng!,
          );
        }
      }
      final estimate = route == null
          ? null
          : estimateArrival(
              catalog: catalog,
              route: route,
              destination: destination,
              from: projection,
              learning: repo.isReference ? null : repo.arrivalLearning,
              planningSpeedKmh: _speed,
            );
      final day = widget.dayType ?? catalog.dayType(repo.now);
      final departures =
          catalog.trips
              .where(
                (t) =>
                    t.busId == busId &&
                    t.routeId == routeId &&
                    t.dayType == day,
              )
              .map((t) => t.departTime)
              .toSet()
              .toList()
            ..sort((a, b) => timeMinutes(a)!.compareTo(timeMinutes(b)!));
      final departure = departures.contains(_departure)
          ? _departure
          : departures.firstOrNull;
      final planning = projection == null;
      final passed = projection != null && destination <= projection.leg;
      final date = widget.date ?? dateLabel(repo.now);
      final arrival = estimate != null && departure != null && planning
          ? timeMinutes(departure)! + estimate.minutes.ceil()
          : null;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'আমার স্টপে কখন আসবে?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              const Text('অবস্থান ব্যবহার করুন অথবা স্টপ বেছে নিন।'),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _locate,
                    icon: const Icon(Icons.my_location),
                    label: Text(
                      _locating
                          ? 'অবস্থান নেওয়া হচ্ছে…'
                          : _student == null
                          ? 'আমার অবস্থান ব্যবহার করুন'
                          : 'অবস্থান refresh করুন',
                    ),
                  ),
                  if (_student != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _student = null;
                          _message = null;
                        });
                        widget.onStudentLocation?.call(null);
                      },
                      child: const Text('অবস্থান মুছুন'),
                    ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_message!),
                ),
              if (_student != null && student == null)
                const Text('অবস্থান refresh করুন।'),
              if (widget.busId == null && buses.isNotEmpty)
                _select<String>(
                  'বাস',
                  busId!,
                  [
                    for (final bus in buses)
                      DropdownMenuItem(
                        value: bus.id,
                        child: Text(bus.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  (value) => setState(() {
                    _bus = value;
                    _route = null;
                    _destination = null;
                    _departure = null;
                  }),
                ),
              if (route != null) ...[
                _select<String>(
                  'Fixed route',
                  route.id,
                  [
                    for (final id in routeIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(
                          catalog.routeName(id),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  (value) => setState(() {
                    _route = value;
                    _destination = null;
                    _departure = null;
                  }),
                ),
                _select<int>('আমার গন্তব্য / stop', destination, [
                  for (var i = 0; i < route.stopIds.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i + 1}. ${catalog.stopName(route.stopIds[i])}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ], (value) => setState(() => _destination = value)),
                if (studentToStop != null)
                  Text(
                    'আপনি → নির্বাচিত স্টপ: ${metersLabel(studentToStop)} (সরলরেখায়)',
                  ),
                if (studentToStop != null && studentToStop > 1500)
                  const Text(
                    'নির্বাচিত স্টপ আপনার থেকে বেশ দূরে। সঠিক route/stop বেছে নিন।',
                  ),
                if (student != null && position != null)
                  Text(
                    '${live ? 'বাস → আপনার বর্তমান অবস্থান' : 'বাসের শেষ জানা অবস্থান → আপনি'}: '
                    '${metersLabel(distanceMeters(student.lat, student.lng, position.lat, position.lng))} সরলরেখায়।',
                  ),
                if (student != null)
                  Text('আপনার GPS accuracy: ±${student.accuracy.round()} m'),
                const Divider(),
                if (passed)
                  const Text(
                    'বাস নির্বাচিত স্টপের এই যাত্রাংশ পার হয়েছে। ফিরতি স্টপের ক্রমটি বেছে নিন।',
                  )
                else if (!planning && estimate != null) ...[
                  if (position != null &&
                      catalog
                              .stops[route.stopIds[destination]]
                              ?.hasCoordinates ==
                          true &&
                      distanceMeters(
                            position.lat,
                            position.lng,
                            catalog.stops[route.stopIds[destination]]!.lat!,
                            catalog.stops[route.stopIds[destination]]!.lng!,
                          ) <=
                          80)
                    const Text(
                      'বাস নির্বাচিত স্টপের কাছে আছে।',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  Text(
                    'আনুমানিক ${estimate.range}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'সম্ভাব্য সময়: ${_clock(repo.now.hour * 60 + repo.now.minute + estimate.lowerMinutes)}–${_clock(repo.now.hour * 60 + repo.now.minute + estimate.upperMinutes)}',
                  ),
                  Text(
                    'বাস → স্টপ: ${metersLabel(estimate.sketchMeters)} (আনুমানিক)',
                  ),
                  if (position!.speedKmh != null && position.speedKmh! < 3)
                    const Text('বাস ধীরে চলছে বা থেমে আছে।'),
                ] else if (!planning) ...[
                  const Text('Arrival time পাওয়া যায়নি।'),
                ] else ...[
                  const Text(
                    'যাত্রা পরিকল্পনা',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    !currentSchedule
                        ? 'নির্বাচিত দিনের সময়সূচি'
                        : live
                        ? 'যাওয়ার দিক নিশ্চিত নয়।'
                        : 'Live GPS নেই।',
                  ),
                  if (departures.isNotEmpty)
                    _select<String>('ছাড়ার নির্ধারিত সময়', departure!, [
                      for (final time in departures)
                        DropdownMenuItem(
                          value: time,
                          child: Text(formatTime(time)),
                        ),
                    ], (value) => setState(() => _departure = value)),
                  if (destination == 0)
                    const Text('শুরুর স্টপ · নির্ধারিত departure')
                  else if (estimate != null) ...[
                    Text(
                      'বাস ছাড়ার পর এই স্টপ পর্যন্ত প্রায় ${estimate.range}।',
                    ),
                    if (arrival != null)
                      Text('$date · সময়মতো ছাড়লে আনুমানিক ${_clock(arrival)}'),
                  ] else
                    const Text('সময় পাওয়া যায়নি।'),
                ],
                ...[
                  StopJourney(
                    catalog: catalog,
                    route: route,
                    progress: projection,
                    now: repo.serverNow,
                    learning: repo.isReference ? null : repo.arrivalLearning,
                  ),
                  const Divider(height: 28),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('যাত্রা পরিকল্পনার গতি ও সময়'),
                  children: [
                    Row(
                      children: [
                        const Expanded(child: Text('পরিকল্পনার গড় গতি')),
                        Text('${_speed.round()} km/h'),
                      ],
                    ),
                    Slider(
                      value: _speed,
                      min: 10,
                      max: 40,
                      divisions: 6,
                      label: '${_speed.round()} km/h',
                      onChanged: (value) => setState(() => _speed = value),
                    ),
                    for (var i = 0; i < route.stopIds.length; i++)
                      Builder(
                        builder: (_) {
                          final item = i == 0
                              ? null
                              : estimateArrival(
                                  catalog: catalog,
                                  route: route,
                                  destination: i,
                                  planningSpeedKmh: _speed,
                                  learning: repo.isReference
                                      ? null
                                      : repo.arrivalLearning,
                                );
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${i + 1}. ${catalog.stopName(route.stopIds[i])}',
                            ),
                            subtitle: Text(
                              i == 0
                                  ? 'শুরুর স্টপ'
                                  : item == null
                                  ? 'Coordinate নেই · সময় পাওয়া যায়নি'
                                  : 'ছাড়ার পর ${item.range}${departure != null ? ' · প্রায় ${_clock(timeMinutes(departure)! + item.minutes.ceil())}' : ''}',
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('এই বাসের fixed route এখনও দেওয়া হয়নি।'),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String _clock(int minutes) {
  final days = minutes ~/ 1440;
  final time = minutes % 1440;
  return '${formatTime('${time ~/ 60}:${(time % 60).toString().padLeft(2, '0')}')}${days > 0 ? ' (+$days দিন)' : ''}';
}
