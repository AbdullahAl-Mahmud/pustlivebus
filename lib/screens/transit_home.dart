import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/transit_repository.dart';
import '../widgets/route_timeline.dart';
import '../widgets/arrival_card.dart';
import '../theme/app_brand.dart';
import 'transit_map_screen.dart';
import 'arrival_planner_screen.dart';

class TransitHome extends StatefulWidget {
  const TransitHome({super.key, required this.repository});
  final TransitRepository repository;
  @override
  State<TransitHome> createState() => _TransitHomeState();
}

class _TransitHomeState extends State<TransitHome> {
  int _tab = 0;
  String _query = '', _filter = 'all', _day = 'today';
  String? _stopId;
  DateTime? _date;
  final _search = TextEditingController();
  TransitRepository get repo => widget.repository;
  TransitCatalog get catalog => repo.catalog!;
  DateTime get selectedDate => _date ?? repo.now;
  String get dayType => _day == 'today' ? catalog.dayType(selectedDate) : _day;
  bool get today =>
      dateLabel(selectedDate) == dateLabel(repo.now) &&
      dayType == catalog.dayType(repo.now);
  List<ScheduledTrip> get trips =>
      catalog.trips.where((t) => t.dayType == dayType).toList();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repo,
    builder: (context, _) {
      if (repo.catalog == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          title: BrandTitle(
            title: [
              'PUST LiveBus',
              'Fixed Routes',
              'Departure Board',
              'Offline & Settings',
            ][_tab],
          ),
          actions: [
            IconButton(
              tooltip: 'Live bus map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TransitMapScreen(repository: repo),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() {
            _tab = index;
            _query = '';
            _search.clear();
          }),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.directions_bus_outlined),
              selectedIcon: Icon(Icons.directions_bus),
              label: 'Buses',
            ),
            NavigationDestination(icon: Icon(Icons.alt_route), label: 'Routes'),
            NavigationDestination(
              icon: Icon(Icons.departure_board),
              label: 'Board',
            ),
            NavigationDestination(
              icon: Icon(Icons.offline_pin_outlined),
              label: 'Offline',
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                key: ValueKey('$_tab:${repo.source}'),
                padding: const EdgeInsets.all(16),
                children: [
                  _connectionNotice(),
                  for (final reminder in repo.reminders.where(
                    (r) =>
                        r['delivered'] == true &&
                        (r['departureAt'] as num) > repo.serverNow,
                  ))
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: Text(
                          'Departure reminder · ${reminder['title']}',
                        ),
                        subtitle: const Text(
                          'Scheduled departure is within 10 minutes. Check live status before leaving.',
                        ),
                        trailing: IconButton(
                          tooltip: 'Dismiss reminder',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              repo.removeReminder(reminder['id'] as String),
                        ),
                      ),
                    ),
                  if (_tab != 3) ...[
                    const SizedBox(height: 20),
                    Text(
                      [
                        'আপনার বাস খুঁজুন',
                        'নির্ধারিত রুট ও স্টপ',
                        'স্টপ অনুযায়ী বাসের সময়',
                      ][_tab],
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _tab == 1
                          ? 'All configured routes, even on days with no trips.'
                          : 'Departure times are from the timetable. Live status requires driver GPS.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: _tab == 1
                            ? 'Route or stop · রুট বা স্টপ'
                            : 'Bus, route or stop · বাস, রুট বা স্টপ',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _query = '';
                                  _search.clear();
                                }),
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    if (_tab != 1) ...[
                      const SizedBox(height: 14),
                      _daySelector(),
                    ],
                    const SizedBox(height: 18),
                  ],
                  if (_tab == 0) ..._busList(),
                  if (_tab == 1) ..._routes(),
                  if (_tab == 2) ..._board(),
                  if (_tab == 3) ..._offline(),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _connectionNotice() {
    final label = repo.isReference
        ? 'Included offline timetable · Reference copy'
        : repo.connected
        ? 'Connected · Schedule saved on this device'
        : 'Offline · Saved timetable';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  repo.connected
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (repo.isReference) ...[
              const SizedBox(height: 8),
              Text(
                'কার্যকর তারিখ: ${catalog.meta['effectiveFrom'] ?? 'not supplied'}',
              ),
            ],
            if (!repo.connected) ...[
              const SizedBox(height: 8),
              const Text(
                'Live GPS unavailable. Timetables and route stops still work.',
              ),
            ],
            if (repo.failedPaths.isNotEmpty || repo.startupError != null) ...[
              const SizedBox(height: 8),
              const Text(
                'Online data could not be loaded. Available offline information is shown.',
              ),
            ],
            if (repo.storageError != null) ...[
              const SizedBox(height: 8),
              Text(repo.storageError!),
            ],
            if (repo.savedIsOld && !repo.isReference) ...[
              const SizedBox(height: 8),
              const Text(
                'Saved timetable is over 7 days old. Connect to check for changes.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _daySelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final entry in {
            'today': 'Auto by date',
            'regular': 'Regular · কর্মদিবস',
            'holiday': 'Holiday · ছুটির দিন',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: _day == entry.key,
              onSelected: (_) => setState(() => _day = entry.key),
            ),
        ],
      ),
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            '${dateLabel(selectedDate)} · ${dayType == 'regular' ? 'Regular' : 'Holiday'} · Bangladesh time',
          ),
          TextButton.icon(
            icon: const Icon(Icons.calendar_month, size: 18),
            label: const Text('Change date'),
            onPressed: () async {
              final now = repo.now;
              final value = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (value != null && mounted) {
                setState(() {
                  _date = value;
                  _day = 'today';
                });
              }
            },
          ),
          if (_date != null)
            TextButton(
              onPressed: () => setState(() {
                _date = null;
                _day = 'today';
              }),
              child: const Text('Today'),
            ),
        ],
      ),
    ],
  );

  List<Widget> _busList() {
    final buses =
        catalog.buses.values
            .where((b) => catalog.matchesBus(b, _query))
            .where(
              (b) => switch (_filter) {
                'live' => repo.locationState(b.id) == LocationState.live,
                'favorites' => repo.isFavorite(b.id),
                _ => true,
              },
            )
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
    return [
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final entry in {
            'all': 'All ${catalog.buses.length}',
            'live': 'Live GPS',
            'favorites': '★ Favourites',
          }.entries)
            FilterChip(
              label: Text(entry.value),
              selected: _filter == entry.key,
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (trips.isEmpty)
        const EmptyMessage(
          icon: Icons.event_busy,
          text: 'No timetable has been added for this day type. Check Regular / Holiday or contact the transport office.',
        ),
      if (trips.isEmpty && !repo.isReference)
        TextButton.icon(
          icon: const Icon(Icons.offline_pin_outlined),
          label: const Text('Open included reference timetable'),
          onPressed: () => repo.selectReference(true),
        ),
      if (buses.isEmpty)
        EmptyMessage(
          icon: Icons.search_off,
          text: _filter == 'live'
              ? 'No fresh driver GPS right now.'
              : _filter == 'favorites'
              ? 'Tap a bus’s star to save it here.'
              : 'No matching bus. Try another name or stop.',
        ),
      for (final bus in buses) _busCard(bus),
    ];
  }

  Widget _busCard(Bus bus) {
    final departures = trips.where((t) => t.busId == bus.id).toList();
    final minutes = repo.now.hour * 60 + repo.now.minute;
    final upcoming = departures
        .where((t) => !today || t.minutes >= minutes)
        .toList();
    final next = upcoming.isEmpty ? null : upcoming.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showBus(bus.id),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bus.name,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: repo.isFavorite(bus.id)
                        ? 'Remove favourite'
                        : 'Save favourite',
                    onPressed: () => repo.toggleFavorite(bus.id),
                    icon: Icon(
                      repo.isFavorite(bus.id) ? Icons.star : Icons.star_border,
                    ),
                  ),
                ],
              ),
              StatusLabel(state: repo.locationState(bus.id)),
              const SizedBox(height: 14),
              if (next != null) ...[
                const Text(
                  'SCHEDULED DEPARTURE',
                  style: TextStyle(fontSize: 11, letterSpacing: 1.1),
                ),
                Text(
                  formatTime(next.departTime),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(catalog.routeName(next.routeId)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(label: Text(audienceLabel(next.audience))),
                    if (today)
                      Chip(
                        label: Text(
                          next.minutes == minutes
                              ? 'Scheduled now'
                              : 'Scheduled in ${next.minutes - minutes} min',
                        ),
                      ),
                  ],
                ),
              ] else
                Text(
                  departures.isEmpty
                      ? 'No scheduled trips for this day type.'
                      : 'All scheduled departures for today have passed.',
                ),
              const SizedBox(height: 10),
              const Text('View departures & route stops →'),
            ],
          ),
        ),
      ),
    );
  }

  void _showBus(String id) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BusDetailsScreen(
        repository: repo,
        busId: id,
        dayType: dayType,
        date: dateLabel(selectedDate),
      ),
    ),
  );

  List<Widget> _routes() {
    final query = normalizeSearch(_query);
    final routes = catalog.routes.values
        .where(
          (r) => normalizeSearch(
            '${r.name} ${r.stopIds.map((id) => '${catalog.stopName(id)} ${catalog.stops[id]?.englishName ?? ''}').join(' ')}',
          ).contains(query),
        )
        .toList();
    return [
      Text('${routes.length} fixed routes · ${catalog.stops.length} stops'),
      const SizedBox(height: 12),
      if (routes.isEmpty)
        const EmptyMessage(
          icon: Icons.alt_route,
          text: 'No routes match your search.',
        ),
      for (final route in routes)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            key: ValueKey('${repo.source}:${route.id}'),
            leading: const Icon(Icons.alt_route),
            title: Text(
              route.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${route.stopIds.length} stops · ${catalog.trips.where((t) => t.routeId == route.id).map((t) => t.busId).toSet().length} buses',
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.all(18),
            children: [
              RouteTimeline(
                stops: route.stopIds.map(catalog.stopName).toList(),
              ),
              const Text(
                'Stop order includes the return journey where configured.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Route on map'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransitMapScreen(
                          repository: repo,
                          routeId: route.id,
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: const Text('স্টপের আনুমানিক সময়'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArrivalPlannerScreen(
                          repository: repo,
                          routeId: route.id,
                        ),
                      ),
                    ),
                  ),
                  for (final id
                      in catalog.trips
                          .where((t) => t.routeId == route.id)
                          .map((t) => t.busId)
                          .toSet())
                    ActionChip(
                      label: Text(catalog.buses[id]!.name),
                      onPressed: () => _showBus(id),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _board() {
    final validStop = catalog.stops.containsKey(_stopId) ? _stopId : null;
    final shown = trips
        .where(
          (t) =>
              (validStop == null ||
                  catalog.routes[t.routeId]!.stopIds.contains(validStop)) &&
              catalog.matchesBus(catalog.buses[t.busId]!, _query),
        )
        .toList();
    return [
      DropdownButtonFormField<String>(
        key: ValueKey('${repo.source}:$validStop'),
        initialValue: validStop,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Your stop · আপনার স্টপ',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('All stops')),
          for (final stop in catalog.stops.values)
            DropdownMenuItem(value: stop.id, child: Text(stop.name)),
        ],
        onChanged: (value) => setState(() => _stopId = value),
      ),
      const SizedBox(height: 12),
      const Text(
        'Times below are departures from the route origin. Arrival times at intermediate stops are not supplied.',
      ),
      const SizedBox(height: 14),
      if (shown.isEmpty)
        const EmptyMessage(
          icon: Icons.departure_board,
          text: 'No scheduled departures match these filters.',
        ),
      for (final trip in shown)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            title: Text(
              '${formatTime(trip.departTime)} · ${catalog.buses[trip.busId]!.name}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${catalog.routeName(trip.routeId)}\n${audienceLabel(trip.audience)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBus(trip.busId),
          ),
        ),
    ];
  }

  List<Widget> _offline() => [
    const SizedBox(height: 18),
    Text(
      'ইন্টারনেট ছাড়াও প্রস্তুত',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
    const SizedBox(height: 10),
    const Text(
      'Included routes and schedules are available from the first launch. Online schedules are automatically saved for later visits on this device.',
    ),
    const SizedBox(height: 16),
    if (!repo.connected && repo.retryOnline != null)
      OutlinedButton.icon(
        icon: const Icon(Icons.refresh),
        label: const Text('Retry online connection'),
        onPressed: repo.retryOnline,
      ),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current copy: ${repo.isReference ? 'Included reference' : 'Downloaded schedule'}',
            ),
            Text(
              '${catalog.buses.length} buses · ${catalog.routes.length} routes · ${catalog.trips.length} departures',
            ),
            if (repo.savedAt != null)
              Text(
                'Downloaded copy saved: ${dateLabel(dhakaTime(DateTime.fromMillisecondsSinceEpoch(repo.savedAt!, isUtc: true)))}',
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('View included reference copy'),
              subtitle: const Text(
                'Show the built-in reference timetable instead of the downloaded copy.',
              ),
              value: repo.isReference,
              onChanged: repo.hasDownloaded ? repo.selectReference : null,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.download_done),
              label: const Text('Save downloaded schedule again'),
              onPressed: repo.hasDownloaded
                  ? () async {
                      await repo.saveForOffline();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              repo.storageError ??
                                  'Schedule saved for offline use.',
                            ),
                          ),
                        );
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    ),
    SwitchListTile(
      title: const Text('Dark mode'),
      secondary: const Icon(Icons.dark_mode_outlined),
      value: repo.darkMode,
      onChanged: repo.setDarkMode,
    ),
    ListTile(
      leading: const Icon(Icons.insights_outlined),
      title: const Text('Arrival time শেখার তথ্য'),
      subtitle: Text('${repo.arrivalLearning.sampleCount}টি যাত্রাসময়ের নমুনা'),
      trailing: IconButton(
        tooltip: 'শেখা সময় মুছুন',
        icon: const Icon(Icons.delete_outline),
        onPressed: repo.arrivalLearning.sampleCount == 0
            ? null
            : repo.clearArrivalLearning,
      ),
    ),
    const Divider(),
    Text('Departure reminders', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    const Text(
      'Set a reminder from a bus’s trip details. Reminders appear inside the app while it is open; they are not background phone notifications.',
    ),
    for (final reminder in repo.reminders)
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text('${reminder['title']}'),
        subtitle: Text(
          '${reminder['date']} · ${(reminder['departureAt'] as num) <= repo.serverNow
              ? 'Departure time passed'
              : reminder['delivered'] == true
              ? 'Reminder due'
              : '10 minutes before departure'}',
        ),
        trailing: IconButton(
          tooltip: 'Remove reminder',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => repo.removeReminder(reminder['id'] as String),
        ),
      ),
    const Divider(),
    const ListTile(
      leading: Icon(Icons.offline_pin_outlined),
      title: Text('Works offline'),
      subtitle: Text(
        'Bus search, timetable, fixed route stops, departure board and favourites.',
      ),
    ),
    const ListTile(
      leading: Icon(Icons.wifi),
      title: Text('Needs internet'),
      subtitle: Text(
        'Fresh driver GPS, new schedule downloads and map tiles. The installed Android app works offline immediately. A release web build can reopen offline after its first complete online visit on HTTPS or localhost.',
      ),
    ),
    const ListTile(
      leading: Icon(Icons.info_outline),
      title: Text('Schedule ≠ actual departure'),
      subtitle: Text(
        'No GPS means the actual bus position is unknown. No automatic “running” or “delayed” claim is made from the timetable.',
      ),
    ),
    const ListTile(
      leading: Icon(Icons.event),
      title: Text('Holiday calendar'),
      subtitle: Text(
        'Friday is the default holiday. Online calendar entries can override specific dates. Always follow transport office notices.',
      ),
    ),
  ];
}

class BusDetailsScreen extends StatelessWidget {
  const BusDetailsScreen({
    super.key,
    required this.repository,
    required this.busId,
    required this.dayType,
    required this.date,
  });
  final TransitRepository repository;
  final String busId, dayType, date;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) {
      final catalog = repository.catalog!;
      final bus = catalog.buses[busId];
      final trips = catalog.trips
          .where((t) => t.busId == busId && t.dayType == dayType)
          .toList();
      final position = repository.isReference ? null : repository.live[busId];
      return Scaffold(
        appBar: AppBar(title: Text(bus?.name ?? 'Bus unavailable')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text('$date · $dayType schedule · Bangladesh time'),
                const SizedBox(height: 12),
                StatusLabel(state: repository.locationState(busId)),
                if (position != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Last GPS update: ${_age(repository.serverNow - position.timestamp)}',
                  ),
                  if (repository.locationState(busId) == LocationState.live &&
                      position.speedKmh != null)
                    Text('Speed: ${position.speedKmh!.round()} km/h'),
                ],
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('View this bus on map'),
                  onPressed: repository.isReference
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TransitMapScreen(
                              repository: repository,
                              busId: busId,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 18),
                ArrivalCard(
                  repository: repository,
                  busId: busId,
                  dayType: dayType,
                  date: date,
                ),
                if (trips.isEmpty)
                  const EmptyMessage(
                    icon: Icons.event_busy,
                    text: 'No scheduled trips for this day type.',
                  ),
                for (final trip in trips)
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatTime(trip.departTime),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(audienceLabel(trip.audience)),
                          const SizedBox(height: 8),
                          Text(
                            catalog.routeName(trip.routeId),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.notifications_outlined),
                            label: const Text('Remind me 10 minutes before'),
                            onPressed: () {
                              final message = repository.addReminder(
                                trip,
                                date,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    message ?? 'Reminder set. Keep the app open to see it.',
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          RouteTimeline(
                            stops: catalog.routes[trip.routeId]!.stopIds
                                .map(catalog.stopName)
                                .toList(),
                          ),
                          const Text(
                            'Scheduled stop order · intermediate arrival times unavailable',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _age(int ms) {
  if (ms < -5000) return 'timestamp is ahead of the server clock';
  final seconds = (ms / 1000).floor().clamp(0, 999999999);
  if (seconds < 60) return '${seconds}s ago';
  if (seconds < 3600) return '${seconds ~/ 60} min ago';
  return '${seconds ~/ 3600}h ago';
}

class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.state});
  final LocationState state;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.circle,
        size: 9,
        color: state == LocationState.live
            ? Colors.green
            : state == LocationState.stale
            ? Colors.orange
            : Colors.grey,
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(switch (state) {
          LocationState.live => 'Live GPS',
          LocationState.stale => 'Last known · GPS stale',
          LocationState.offline => 'No live GPS',
        }),
      ),
    ],
  );
}

class EmptyMessage extends StatelessWidget {
  const EmptyMessage({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28),
    child: Column(
      children: [
        Icon(icon, size: 36),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}
