import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'app_router.dart';
import 'services/sip_service.dart';
import 'services/stt_service.dart';
import 'services/llm_service.dart';
import 'services/storage_service.dart';
import 'providers/call_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for light theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.bgLight,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Determine initial route
  final isOnboarded = await StorageService.isOnboardingComplete();
  String initialRoute;
  if (!isOnboarded) {
    initialRoute = AppRouter.welcome;
  } else {
    // Check if Gemini API key is configured
    final hasApiKey = await StorageService.hasGeminiApiKey();
    if (!hasApiKey) {
      initialRoute = AppRouter.apiKey;
    } else {
      initialRoute = AppRouter.home;
    }
  }

  runApp(StealthAnswerApp(initialRoute: initialRoute));
}

class StealthAnswerApp extends StatelessWidget {
  final String initialRoute;

  const StealthAnswerApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SipService()),
        ChangeNotifierProvider(create: (_) => SttService()),
        ChangeNotifierProvider(create: (_) => LlmService()),
        ChangeNotifierProvider(create: (_) => CallProvider()),
      ],
      child: MaterialApp(
        title: 'StealthAnswer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: initialRoute,
        onGenerateRoute: AppRouter.generateRoute,
      ),
    );
  }
}
