import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_theme.dart';
import '../../app_router.dart';
import '../../widgets/option_card.dart';

class PhoneNumberScreen extends StatelessWidget {
  const PhoneNumberScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Get Your Number'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Set up your free\ninterview number',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to receive calls. Both options are free.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Option A: Google Voice
              OptionCard(
                title: 'Google Voice',
                subtitle: 'Free +1 US number',
                icon: Icons.phone_android,
                isRecommended: true,
                body: 'Google Voice gives you a free +1 US number. '
                    'Anyone can call it from any phone.\n\n'
                    'Setup steps (one time, ~5 minutes):\n'
                    '1. Go to voice.google.com on your computer\n'
                    '2. Sign in with Google and claim a free number\n'
                    '3. Go to Settings → Calls → Forward calls to...\n'
                    '4. Add your SIP address as forwarding destination\n'
                    '   (you\'ll create this in the next step)\n'
                    '5. Your Google Voice number is now your interview number',
                buttonText: 'Open voice.google.com',
                onButtonPressed: () => _launchUrl('https://voice.google.com'),
              ),

              const SizedBox(height: 16),

              // Option B: Telnyx
              OptionCard(
                title: 'Telnyx',
                subtitle: 'Works worldwide (40+ countries)',
                icon: Icons.language,
                isRecommended: false,
                body: 'Telnyx gives you a real phone number with free trial credits. '
                    'Works in US, UK, Canada, and 40+ countries.\n\n'
                    'Setup steps:\n'
                    '1. Go to telnyx.com and create free account\n'
                    '2. Use free trial credits to get a number (~\$1)\n'
                    '3. Create a SIP Connection\n'
                    '4. Enter credentials in next screen',
                buttonText: 'Open telnyx.com',
                onButtonPressed: () => _launchUrl('https://telnyx.com'),
              ),

              const SizedBox(height: 32),

              // Next button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRouter.sipAddress);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Next', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
