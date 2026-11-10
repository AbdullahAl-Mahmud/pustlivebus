import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/driver_trip_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/transit_home.dart';
import 'services/transit_repository.dart';
import 'services/browser_connection.dart';
import 'theme/app_brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = TransitRepository(store: PreferencesStore());
  await repository.initialize();
  repository.retryOnline = () => _connectBackend(repository);
  watchBrowserOnline(() => unawaited(_connectBackend(repository)));
  runApp(PustLiveBusApp(repository: repository));
  unawaited(_connectBackend(repository));
}

Future<void> _connectBackend(TransitRepository repository) async {
  if (!browserIsOnline) {
    repository.setConnection(false);
    return;
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 15));
    repository.attach(FirebaseDatabase.instance);
    await FirebaseDatabase.instance.goOnline();
  } catch (_) {
    repository.startupError =
        'Online services are unavailable. Offline timetables remain available.';
    repository.setConnection(false);
  }
}

class PustLiveBusApp extends StatelessWidget {
  const PustLiveBusApp({super.key, required this.repository});
  final TransitRepository repository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) => MaterialApp(
        title: 'PUST LiveBus',
        debugShowCheckedModeBanner: false,
        theme: AppBrand.theme(Brightness.light),
        darkTheme: AppBrand.theme(Brightness.dark),
        themeMode: repository.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: RoleScreen(repository: repository),
      ),
    );
  }
}

class RoleScreen extends StatelessWidget {
  const RoleScreen({super.key, this.repository});
  final TransitRepository? repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(),
        actions: [
          IconButton(
            tooltip: 'Transport admin',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: repository?.firebaseReady != true
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminScreen(repository: repository!),
                    ),
                  ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final actions = Card(
            margin: EdgeInsets.zero,
            color: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: const RoundedRectangleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 72)),
                  const SizedBox(height: 20),
                  Text(
                    'Your campus. Your next bus.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Find PUST buses, explore stops and check live locations shared by your driver.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: repository == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TransitHome(repository: repository!),
                              ),
                            ),
                      icon: const Icon(Icons.school),
                      label: const Text('I am a Student'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          repository == null || !repository!.firebaseReady
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    DriverTripScreen(repository: repository!),
                              ),
                            ),
                      icon: const Icon(Icons.drive_eta),
                      label: const Text('I am a Driver'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.offline_pin_outlined, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Schedules & fixed routes work offline. Driver tracking needs an online connection.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: dark ? .16 : .095,
                      child: Center(
                        child: Image.asset(
                          AppBrand.logo,
                          width: (constraints.maxWidth * .9).clamp(
                            320.0,
                            900.0,
                          ),
                          height: constraints.maxHeight * .95,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: actions,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
