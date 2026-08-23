import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../main.dart';
import '../l10n/app_strings.dart';
import '../services/license_service.dart';

class TrialIntroScreen extends StatefulWidget {
  const TrialIntroScreen({super.key});

  @override
  State<TrialIntroScreen> createState() => _TrialIntroScreenState();
}

class _TrialIntroScreenState extends State<TrialIntroScreen> {
  bool _starting = false;

  Future<void> _startTrial() async {
    if (_starting) return;
    setState(() => _starting = true);
    await LicenseService.completeTrialIntroduction();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RootWrapper()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final downloadUri = LicenseService.phoneAppDownloadUri;
    final deviceCode = LicenseService.deviceId;
    final expiry = LicenseService.trialExpiresAt;
    final expiryText = expiry == null
        ? null
        : MaterialLocalizations.of(context).formatMediumDate(expiry.toLocal());

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0B14),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF151123),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white10),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 48,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(38),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _TrialBadge(days: LicenseService.trialDays),
                                  const SizedBox(height: 20),
                                  Text(
                                    strings
                                        .trialTitle(LicenseService.trialDays),
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 38,
                                      height: 1.08,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    strings.trialDescription(
                                      LicenseService.trialDays,
                                    ),
                                    style: GoogleFonts.inter(
                                      color: Colors.white70,
                                      fontSize: 16,
                                      height: 1.55,
                                    ),
                                  ),
                                  if (expiryText != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      strings.trialEndDate(expiryText),
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFAAA4FF),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  Text(
                                    strings.deviceCode,
                                    style: GoogleFonts.inter(
                                      color: Colors.white38,
                                      fontSize: 11,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    deviceCode,
                                    style: GoogleFonts.firaCode(
                                      color: const Color(0xFF8D86FF),
                                      fontSize: 25,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 26),
                                  ElevatedButton.icon(
                                    autofocus: true,
                                    onPressed: _starting ? null : _startTrial,
                                    icon: _starting
                                        ? const SizedBox(
                                            width: 19,
                                            height: 19,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.play_arrow_rounded),
                                    label: Text(
                                      _starting
                                          ? strings.starting
                                          : strings.startFreeTrial,
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF7068FF),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 28,
                                        vertical: 18,
                                      ),
                                      textStyle: GoogleFonts.inter(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 42),
                        Expanded(
                          flex: 3,
                          child: _PhoneAppCard(downloadUri: downloadUri),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrialBadge extends StatelessWidget {
  const _TrialBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF36D399).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF36D399).withValues(alpha: 0.32),
        ),
      ),
      child: Text(
        AppStrings.of(context).freeDaysBadge(days),
        style: GoogleFonts.inter(
          color: const Color(0xFF59E2B0),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _PhoneAppCard extends StatelessWidget {
  const _PhoneAppCard({required this.downloadUri});

  final Uri? downloadUri;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0C18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (downloadUri != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
              ),
              child: QrImageView(
                data: downloadUri.toString(),
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            )
          else
            Container(
              width: 208,
              height: 208,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(
                Icons.qr_code_2_rounded,
                size: 92,
                color: Colors.white24,
              ),
            ),
          const SizedBox(height: 18),
          Text(
            strings.downloadPhoneApp,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            downloadUri?.toString() ?? strings.phoneAppAddressPending,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            strings.phoneAppCompanionDescription,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
