import 'package:flutter/material.dart';

import '../models/transit.dart';
import '../services/arrival_estimator.dart';
import '../services/driver_navigation.dart';

/// A GPS projection on ordered stop occurrences, never timetable progress.
class StopJourney extends StatelessWidget {
  const StopJourney({
    super.key,
    required this.catalog,
    required this.route,
    required this.progress,
    required this.now,
    this.learning,
  });
  final TransitCatalog catalog;
  final FixedRoute route;
  final RouteProjection? progress;
  final int now;
  final ArrivalLearning? learning;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final primary = Theme.of(context).colorScheme.primary;
    String name(int index) => catalog.stopName(route.stopIds[index]);
    final next = p == null
        ? null
        : estimateArrival(
            catalog: catalog,
            route: route,
            destination: p.leg + 1,
            from: p,
            learning: learning,
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stop থেকে stop', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (p != null) ...[
            Text(
              '${name(p.leg)} → ${name(p.leg + 1)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: p.fraction.clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              semanticsLabel: 'বর্তমান stop দুটির মাঝে আনুমানিক অগ্রগতি',
            ),
            const SizedBox(height: 8),
            Text('এই দুই stop-এর মাঝে প্রায় ${(p.fraction * 100).round()}%'),
            Text('পরের stop: ${name(p.leg + 1)}'),
            if (next != null) ...[
              Text(
                'আনুমানিক ${next.range}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                'সম্ভাব্য arrival: ${driverArrivalClock(now + next.lowerMinutes * 60000)} – ${driverArrivalClock(now + next.upperMinutes * 60000)}',
              ),
            ],
          ] else
            const Text('Live progress নেই · Stop order'),
          const SizedBox(height: 18),
          Text(
            'Stop ও আনুমানিক সময়',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (var i = 0; i < route.stopIds.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Icon(
                          p != null && i == p.leg + 1
                              ? Icons.directions_bus
                              : p != null && i <= p.leg
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: p != null && i <= p.leg + 1
                              ? primary
                              : Theme.of(context).colorScheme.outline,
                          size: 20,
                        ),
                        if (i < route.stopIds.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              color: p != null && i <= p.leg
                                  ? primary
                                  : Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${name(i)}',
                            style: TextStyle(
                              fontWeight: p != null && i == p.leg + 1
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          Text(
                            _time(i),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _time(int index) {
    final p = progress;
    if (p != null && index <= p.leg) return 'রুটের এই অবস্থান পেছনে';
    if (p == null && index == 0) return 'শুরুর stop';
    final estimate = estimateArrival(
      catalog: catalog,
      route: route,
      destination: index,
      from: p,
      learning: learning,
    );
    if (estimate == null) return 'সময় পাওয়া যায়নি';
    if (p == null) return 'ছাড়ার পর প্রায় ${estimate.range}';
    return 'আর প্রায় ${estimate.range}\n${driverArrivalClock(now + estimate.lowerMinutes * 60000)} – ${driverArrivalClock(now + estimate.upperMinutes * 60000)}';
  }
}
