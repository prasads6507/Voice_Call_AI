import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../app_router.dart';
import '../../services/storage_service.dart';

class ResumeScreen extends StatefulWidget {
  const ResumeScreen({super.key});

  @override
  State<ResumeScreen> createState() => _ResumeScreenState();
}

class _ResumeScreenState extends State<ResumeScreen> {
  final _resumeController = TextEditingController();
  bool _showTips = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final resume = await StorageService.getResume();
    if (resume.isNotEmpty) {
      _resumeController.text = resume;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _resumeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Context'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add your interview\ncontext',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The more detail you add, the better your AI answers will be.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Text area
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDarkElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _resumeController,
                    onChanged: (_) => setState(() {}),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'Paste your resume, LinkedIn bio, skills, work experience, '
                          'projects, and achievements here.\n\n'
                          'Example:\n'
                          '- 4 years React and TypeScript experience\n'
                          '- Built e-commerce platform serving 50,000 users\n'
                          '- Led team of 3 engineers at StartupXYZ\n'
                          '- Strong background in Node.js, PostgreSQL, AWS',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                        height: 1.6,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),

              // Character counter
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_resumeController.text.length} characters',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ),

              // Tips accordion
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => setState(() => _showTips = !_showTips),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDarkCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 18,
                        color: AppTheme.accentOrange,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tips for better AI answers',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Icon(
                        _showTips
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showTips) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDarkCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TipItem('Include specific technologies and years of experience'),
                      SizedBox(height: 8),
                      _TipItem(
                          'Add measurable achievements (numbers, percentages)'),
                      SizedBox(height: 8),
                      _TipItem('Include company names and project outcomes'),
                      SizedBox(height: 8),
                      _TipItem(
                          'Mention leadership roles and team collaboration'),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAndContinue,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save and Continue',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndContinue() async {
    setState(() => _saving = true);

    await StorageService.saveResume(_resumeController.text);
    await StorageService.setOnboardingComplete(true);

    if (mounted) {
      // Navigate to API key setup
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRouter.apiKey,
        (route) => false,
      );
    }
  }
}

class _TipItem extends StatelessWidget {
  final String text;
  const _TipItem(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  ', style: TextStyle(color: AppTheme.accentOrange)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
