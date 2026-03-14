import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../app_theme.dart';
import '../app_router.dart';
import '../services/model_download_service.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  final ModelDownloadService _downloadService = ModelDownloadService();
  bool _isOnWifi = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _checkExistingModels();
    _downloadService.addListener(_onDownloadUpdate);
  }

  @override
  void dispose() {
    _downloadService.removeListener(_onDownloadUpdate);
    super.dispose();
  }

  void _onDownloadUpdate() {
    setState(() {});
    if (_downloadService.allModelsReady) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRouter.home,
            (route) => false,
          );
        }
      });
    }
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isOnWifi = result.contains(ConnectivityResult.wifi);
    });
  }

  Future<void> _checkExistingModels() async {
    await _downloadService.checkModels();
    if (_downloadService.allModelsReady && mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRouter.home,
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                'Download AI\nModels',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'These models run 100% on your device. No data ever leaves your phone.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),

              // WiFi warning
              if (!_isOnWifi)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.accentOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off,
                          color: AppTheme.accentOrange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'WiFi recommended — downloads are ~875MB total',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.accentOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // Whisper Model
              _ModelCard(
                name: 'Whisper Tiny',
                description: 'Speech-to-text engine',
                size: '~75 MB',
                icon: Icons.mic_none_outlined,
                color: AppTheme.accent,
                state: _downloadService.whisperState,
                progress: _downloadService.whisperProgress,
                error: _downloadService.whisperError,
                onDownload: _downloadService.downloadWhisper,
                onCancel: _downloadService.cancelWhisper,
              ),

              const SizedBox(height: 16),

              // Gemma Model
              _ModelCard(
                name: 'Gemma-3 1B',
                description: 'AI answer engine (4-bit quantized)',
                size: '~800 MB',
                icon: Icons.smart_toy_outlined,
                color: AppTheme.primary,
                state: _downloadService.gemmaState,
                progress: _downloadService.gemmaProgress,
                error: _downloadService.gemmaError,
                onDownload: _downloadService.downloadGemma,
                onCancel: _downloadService.cancelGemma,
              ),

              const Spacer(),

              // Download All button
              if (!_downloadService.allModelsReady)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _downloadService.whisperState ==
                                DownloadState.downloading ||
                            _downloadService.gemmaState ==
                                DownloadState.downloading
                        ? null
                        : _downloadService.downloadAll,
                    icon: const Icon(Icons.download, size: 20),
                    label: const Text(
                      'Download All Models',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),

              if (_downloadService.allModelsReady)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRouter.home,
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.check_circle, size: 20),
                    label: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentGreen,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Skip option
              if (!_downloadService.allModelsReady)
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRouter.home,
                        (route) => false,
                      );
                    },
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMuted,
                      ),
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
}

class _ModelCard extends StatelessWidget {
  final String name;
  final String description;
  final String size;
  final IconData icon;
  final Color color;
  final DownloadState state;
  final double progress;
  final String error;
  final VoidCallback onDownload;
  final VoidCallback onCancel;

  const _ModelCard({
    required this.name,
    required this.description,
    required this.size,
    required this.icon,
    required this.color,
    required this.state,
    required this.progress,
    required this.error,
    required this.onDownload,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDarkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state == DownloadState.completed
              ? AppTheme.accentGreen.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                size,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress / Status
          if (state == DownloadState.downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppTheme.surfaceDarkElevated,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                GestureDetector(
                  onTap: onCancel,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.accentRed,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (state == DownloadState.completed) ...[
            Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppTheme.accentGreen, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Ready',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.accentGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],

          if (state == DownloadState.error) ...[
            Row(
              children: [
                Icon(Icons.error, color: AppTheme.accentRed, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.accentRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDownload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
                child: const Text('Retry'),
              ),
            ),
          ],

          if (state == DownloadState.idle || state == DownloadState.paused)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDownload,
                icon: Icon(
                  state == DownloadState.paused
                      ? Icons.play_arrow
                      : Icons.download,
                  size: 18,
                ),
                label: Text(
                  state == DownloadState.paused ? 'Resume' : 'Download',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
