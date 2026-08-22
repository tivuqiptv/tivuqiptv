import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/license_service.dart';
import '../main.dart'; // or wherever we can restart the app or reload
import '../l10n/app_strings.dart';
import '../config/distribution_config.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  bool _isChecking = false;
  String? _error;

  Future<void> _verifyLicense() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final active = await LicenseService.refreshStatus();
    if (!mounted) return;
    if (active && LicenseService.status == LicenseStatus.active) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const RootWrapper()),
      );
      return;
    }

    setState(() {
      _isChecking = false;
      _error = AppStrings.of(context).licenseVerificationFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final deviceId = LicenseService.deviceId;
    final activationUri = LicenseService.activationUri;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0B14),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 800),
              width: double.infinity,
              padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).height < 700 ? 28 : 48,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF131022),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Sol Taraf: Bilgiler
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock_clock,
                                color: Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                strings.trialExpired,
                                style: GoogleFonts.inter(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          strings.activateToContinue,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          strings.yourDeviceCode,
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                deviceId,
                                style: GoogleFonts.firaCode(
                                  color: const Color(0xFF6366F1),
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          DistributionConfig.isAmazonAppstore
                              ? strings.amazonDeviceCodeExplanation
                              : strings.deviceCodeExplanation,
                          style: GoogleFonts.inter(
                            color: Colors.white60,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          Text(
                            _error!.isEmpty
                                ? strings.licenseVerificationFailed
                                : _error!,
                            style: GoogleFonts.inter(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        ElevatedButton.icon(
                          onPressed: _isChecking ? null : _verifyLicense,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 20,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: _isChecking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(
                            _isChecking
                                ? strings.checking
                                : strings.checkLicense,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sağ Taraf: QR Kod
                  Expanded(
                    flex: 2,
                    child: DistributionConfig.isAmazonAppstore
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.shopping_bag_rounded,
                                color: Color(0xFFAAA4FF),
                                size: 104,
                              ),
                              const SizedBox(height: 24),
                              Text(
                                strings.amazonPurchaseTitle,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                strings.amazonProcessesPurchases,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white54,
                                  fontSize: 13,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: QrImageView(
                                  data: activationUri?.toString() ??
                                      'tivuq://activate?deviceId=$deviceId',
                                  version: QrVersions.auto,
                                  size: 200.0,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                strings.scanWithPhone,
                                style: GoogleFonts.inter(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                activationUri?.host ??
                                    strings.activationAddressMissing,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
