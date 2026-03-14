import 'package:flutter/material.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/phone_number_screen.dart';
import 'screens/onboarding/sip_address_screen.dart';
import 'screens/onboarding/sip_credentials_screen.dart';
import 'screens/onboarding/resume_screen.dart';
import 'screens/onboarding/api_key_screen.dart';
import 'screens/home_screen.dart';
import 'screens/active_call_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_guide_screen.dart';

class AppRouter {
  static const String welcome = '/welcome';
  static const String phoneNumber = '/onboarding/phone-number';
  static const String sipAddress = '/onboarding/sip-address';
  static const String sipCredentials = '/onboarding/sip-credentials';
  static const String resume = '/onboarding/resume';
  static const String apiKey = '/onboarding/api-key';
  static const String home = '/home';
  static const String activeCall = '/active-call';
  static const String settings = '/settings';
  static const String setupGuide = '/setup-guide';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case welcome:
        return _fadeRoute(const WelcomeScreen(), settings);
      case phoneNumber:
        return _slideRoute(const PhoneNumberScreen(), settings);
      case sipAddress:
        return _slideRoute(const SipAddressScreen(), settings);
      case sipCredentials:
        return _slideRoute(const SipCredentialsScreen(), settings);
      case resume:
        return _slideRoute(const ResumeScreen(), settings);
      case apiKey:
        return _fadeRoute(const ApiKeyScreen(), settings);
      case home:
        return _fadeRoute(const HomeScreen(), settings);
      case activeCall:
        return _slideRoute(const ActiveCallScreen(), settings, direction: AxisDirection.up);
      case AppRouter.settings:
        return _slideRoute(const SettingsScreen(), settings);
      case setupGuide:
        return _slideRoute(const SetupGuideScreen(), settings);
      default:
        return _fadeRoute(const WelcomeScreen(), settings);
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static PageRouteBuilder _slideRoute(
    Widget page,
    RouteSettings settings, {
    AxisDirection direction = AxisDirection.left,
  }) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        Offset begin;
        switch (direction) {
          case AxisDirection.left:
            begin = const Offset(1.0, 0.0);
            break;
          case AxisDirection.up:
            begin = const Offset(0.0, 1.0);
            break;
          default:
            begin = const Offset(1.0, 0.0);
        }
        return SlideTransition(
          position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}
