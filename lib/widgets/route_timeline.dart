import 'package:flutter/material.dart';

/// Scheduled stop order only; no GPS progress is inferred from the timetable.
class RouteTimeline extends StatelessWidget {
  const RouteTimeline({super.key, required this.stops});

  final List<String> stops;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < stops.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 30,
                  child: Column(
                    children: [
                      Icon(
                        i == 0 || i == stops.length - 1
                            ? Icons.radio_button_checked
                            : Icons.circle_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      if (i < stops.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 20),
                    child: Text(stops[i], style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
