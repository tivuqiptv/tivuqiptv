import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/license_service.dart';
import '../providers/settings_provider.dart';
import '../providers/watch_history_provider.dart';
import '../main.dart';
import 'activation_screen.dart';
import 'trial_intro_screen.dart';

class SplashScreen extends StatefulWidget {
  final SettingsProvider settingsProvider;
  final WatchHistoryProvider watchHistoryProvider;

  const SplashScreen({
    super.key,
    required this.settingsProvider,
    required this.watchHistoryProvider,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();

    // Nefes alıp veren (breathing glow) şık logo animasyonu
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeInBackground();
    });
  }

  Future<void> _initializeInBackground() async {
    // Live TV does not need VOD watch history. Large histories used to delay
    // every cold start even though the last live stream was already known.
    // Load it independently and let movie/series screens consume it when ready.
    final historyLoad = widget.watchHistoryProvider.init();
    await Future.wait([
      widget.settingsProvider.init(),
      LicenseService.init(),
    ]).timeout(const Duration(seconds: 15), onTimeout: () => <void>[]);
    // Keep errors handled without extending the splash lifetime.
    historyLoad.catchError((Object error) {
      debugPrint('İzleme geçmişi arka planda yüklenemedi: $error');
    });

    if (!mounted) return;

    if (LicenseService.status == LicenseStatus.expired) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ActivationScreen()),
      );
    } else if (LicenseService.status == LicenseStatus.trial &&
        !LicenseService.trialIntroductionCompleted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TrialIntroScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RootWrapper()),
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SplashScreenBody(pulseController: _pulseController);
  }
}

class SplashScreenBody extends StatelessWidget {
  final AnimationController? pulseController;

  const SplashScreenBody({super.key, this.pulseController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Işıltılı Nefes Alan Logo
            if (pulseController != null)
              AnimatedBuilder(
                animation: pulseController!,
                builder: (context, child) {
                  final value = pulseController!.value;
                  return Transform.scale(
                    scale: 1.0 +
                        (value * 0.06), // Zarif ışıltılı nefes alma efekti
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.2 + (value * 0.4)),
                            blurRadius: 25 + (value * 20),
                            spreadRadius: 4 + (value * 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.live_tv,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              )
            else
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.live_tv, size: 60, color: Colors.white),
              ),
            const SizedBox(height: 32),
            // Başlık
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'TIVUQ',
                    style: GoogleFonts.splineSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 36,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                  TextSpan(
                    text: 'IPTV',
                    style: GoogleFonts.splineSans(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF6366F1),
                      fontSize: 36,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            // Şık, Pürüzsüz İlerleme Çubuğu (Donma hissiyatı vermeyen sinematik tasarım)
            SizedBox(
              width: 140,
              height: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const LinearProgressIndicator(
                  backgroundColor: Color(0xFF1E1B2E),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
