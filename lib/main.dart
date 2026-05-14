import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'providers/command_provider.dart';
import 'providers/diagnostics_provider.dart';
import 'providers/event_provider.dart';
import 'providers/replay_provider.dart';
import 'providers/telemetry_provider.dart';
import 'providers/testing_provider.dart';
import 'screens/connection_screen.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait and immersive status bar
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppConstants.bgPrimary,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const RgbInvadersApp());
}

class RgbInvadersApp extends StatelessWidget {
  const RgbInvadersApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TelemetryProvider()),
        ChangeNotifierProxyProvider<TelemetryProvider, EventProvider>(
          create: (_) => EventProvider(),
          update: (_, telemetryProv, eventProv) {
            // Share the EventService from TelemetryProvider so events
            // routed by WebSocket are visible to the EventProvider.
            if (eventProv != null &&
                eventProv.service != telemetryProv.eventService) {
              // Replace with a provider that uses the shared service.
              return EventProvider.withService(telemetryProv.eventService);
            }
            return eventProv ?? EventProvider();
          },
        ),
        ChangeNotifierProxyProvider<TelemetryProvider, DiagnosticsProvider>(
          create: (_) => DiagnosticsProvider(),
          update: (_, telemetryProv, diagProv) {
            // Share the BugDetectionService and DiagnosticsService from
            // TelemetryProvider so packets routed by WebSocket flow into
            // the DiagnosticsProvider for the UI.
            if (diagProv != null) {
              diagProv.updateServices(
                telemetryProv.bugService,
                telemetryProv.diagService,
              );
              return diagProv;
            }
            return DiagnosticsProvider.withServices(
              telemetryProv.bugService,
              telemetryProv.diagService,
            );
          },
        ),
        ChangeNotifierProxyProvider<TelemetryProvider, TestingProvider>(
          create: (_) => TestingProvider(),
          update: (_, telemetryProv, testProv) {
            if (testProv != null) {
              testProv.updateService(telemetryProv.testingService);
              return testProv;
            }
            return TestingProvider.withService(
              telemetryProv.testingService,
            );
          },
        ),
        ChangeNotifierProxyProvider<TelemetryProvider, ReplayProvider>(
          create: (_) => ReplayProvider(),
          update: (_, telemetryProv, replayProv) {
            if (replayProv != null) {
              replayProv.updateServices(
                telemetryProv.recorderService,
                telemetryProv.replayEngine,
              );
              return replayProv;
            }
            return ReplayProvider.withServices(
              telemetryProv.recorderService,
              telemetryProv.replayEngine,
            );
          },
        ),
        ChangeNotifierProxyProvider<TelemetryProvider, CommandProvider>(
          create: (_) => CommandProvider(),
          update: (_, telemetryProv, cmdProv) {
            if (cmdProv != null) {
              cmdProv.updateService(telemetryProv.commandService);
              return cmdProv;
            }
            return CommandProvider.withService(
              telemetryProv.commandService,
            );
          },
        ),
      ],
      child: MaterialApp(
        title: 'Ultimate RGB Invaders',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppConstants.bgPrimary,
          colorScheme: ColorScheme.dark(
            primary: AppConstants.neonCyan,
            secondary: AppConstants.neonMagenta,
            surface: AppConstants.bgCard,
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData.dark().textTheme,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppConstants.bgPrimary,
            elevation: 0,
          ),
        ),
        home: const ConnectionScreen(),
      ),
    );
  }
}
