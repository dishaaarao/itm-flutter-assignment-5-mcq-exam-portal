import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_theme.dart';
import 'providers/attempt_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/exam_provider.dart';
import 'screens/splash_screen.dart';
import 'services/app_services.dart';

void main() {
  runApp(const McqPortalApp());
}

class McqPortalApp extends StatelessWidget {
  const McqPortalApp({super.key, this.services});

  /// Injectable so widget tests can supply a stubbed client instead of
  /// reaching for a real backend.
  final AppServices? services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppServices>(create: (_) => services ?? AppServices()),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(context.read<AppServices>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ExamProvider(context.read<AppServices>()),
        ),
        ChangeNotifierProvider(
          create: (context) => AttemptProvider(context.read<AppServices>()),
        ),
      ],
      child: MaterialApp(
        title: 'MCQ Exam Portal',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const SplashScreen(),
      ),
    );
  }
}
