import 'package:flutter/material.dart';

import '../services/transit_repository.dart';
import '../widgets/arrival_card.dart';

class ArrivalPlannerScreen extends StatelessWidget {
  const ArrivalPlannerScreen({
    super.key,
    required this.repository,
    required this.routeId,
  });
  final TransitRepository repository;
  final String routeId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('স্টপের আনুমানিক সময়')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [ArrivalCard(repository: repository, routeId: routeId)],
        ),
      ),
    ),
  );
}
