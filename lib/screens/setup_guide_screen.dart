import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';

class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppTheme.primaryGradient.createShader(bounds),
              child: const Text(
                'How to Set Up\nGoogle Voice',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete setup in about 10 minutes',
              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),

            // Step 1
            _GuideStep(
              number: '1',
              title: 'Get your free number',
              color: AppTheme.accent,
              steps: const [
                'Go to voice.google.com',
                'Sign in with Google account',
                'Choose a phone number (pick any area code)',
                'Complete verification',
              ],
              buttonText: 'Open Google Voice',
              buttonUrl: 'https://voice.google.com',
            ),

            // Step 2
            _GuideStep(
              number: '2',
              title: 'Get your free SIP address',
              color: AppTheme.primary,
              steps: const [
                'Go to sip2sip.info',
                'Click Register → choose username',
                'Note your SIP address: username@sip2sip.info',
                'Note your password',
              ],
              buttonText: 'Open sip2sip.info',
              buttonUrl: 'https://sip2sip.info',
            ),

            // Step 3
            _GuideStep(
              number: '3',
              title: 'Connect Google Voice to SIP',
              color: AppTheme.accentOrange,
              steps: const [
                'In Google Voice Settings → Calls',
                'Click "Add another phone"',
                'Enter your SIP address as a forwarding number',
                'Format: username@sip2sip.info',
                'Verify and enable forwarding',
              ],
            ),

            // Step 4
            _GuideStep(
              number: '4',
              title: 'Enter credentials here',
              color: AppTheme.accentGreen,
              steps: const [
                'Go to Settings → SIP Connection',
                'Enter your sip2sip.info username and password',
                'Tap Test Connection → should show ✅',
              ],
            ),

            // Step 5
            _GuideStep(
              number: '5',
              title: 'Share your number',
              color: const Color(0xFFE040FB),
              steps: const [
                'Copy your Google Voice number from Home screen',
                'Give it to your interviewer',
                'When they call, the app will ring and AI will help',
              ],
            ),

            const SizedBox(height: 24),

            // How it works diagram
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDarkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How calls flow:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FlowItem('Interviewer dials your Google Voice number', Icons.phone_outlined, AppTheme.accent),
                  _FlowArrow(),
                  _FlowItem('Google Voice forwards to your SIP address', Icons.call_split, AppTheme.primary),
                  _FlowArrow(),
                  _FlowItem('StealthAnswer receives the call', Icons.headset_mic, AppTheme.accentGreen),
                  _FlowArrow(),
                  _FlowItem('Moonshine transcribes the interview question', Icons.mic, AppTheme.accentOrange),
                  _FlowArrow(),
                  _FlowItem('AI generates your answer on screen', Icons.smart_toy, const Color(0xFFE040FB)),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  final String number;
  final String title;
  final Color color;
  final List<String> steps;
  final String? buttonText;
  final String? buttonUrl;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.color,
    required this.steps,
    this.buttonText,
    this.buttonUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    number,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('→  ', style: TextStyle(color: color, fontSize: 14)),
                  Expanded(
                    child: Text(
                      step,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (buttonText != null && buttonUrl != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(buttonUrl!);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(buttonText!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowItem extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _FlowItem(this.text, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _FlowArrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, top: 4, bottom: 4),
      child: Icon(
        Icons.arrow_downward,
        size: 16,
        color: AppTheme.textMuted,
      ),
    );
  }
}
