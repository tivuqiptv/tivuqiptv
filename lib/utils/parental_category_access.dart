import 'package:flutter/material.dart';

import '../providers/settings_provider.dart';
import '../widgets/parental_pin_dialog.dart';

String parentalSessionKey(String type, String category) =>
    '$type\u0000$category';

Future<bool> ensureCategoryAccess(
  BuildContext context, {
  required SettingsProvider settings,
  required String type,
  required String category,
  required Set<String> sessionUnlocks,
  String? profileId,
}) async {
  if (!settings.isCategoryLocked(type, category, profileId: profileId)) {
    return true;
  }
  final sessionKey = parentalSessionKey(type, category);
  if (sessionUnlocks.contains(sessionKey)) return true;
  final verified = await requestParentalPin(
    context,
    settings: settings,
    profileId: profileId,
  );
  if (verified) sessionUnlocks.add(sessionKey);
  return verified;
}

Future<void> toggleCategoryParentalLock(
  BuildContext context, {
  required SettingsProvider settings,
  required String type,
  required String category,
  required Set<String> sessionUnlocks,
  String? profileId,
}) async {
  if (!settings.hasParentalPin(profileId: profileId)) {
    final created = await requestParentalPin(
      context,
      settings: settings,
      profileId: profileId,
      createPin: true,
    );
    if (!created) return;
  } else {
    final verified = await requestParentalPin(
      context,
      settings: settings,
      profileId: profileId,
    );
    if (!verified) return;
  }
  final wasLocked = settings.isCategoryLocked(
    type,
    category,
    profileId: profileId,
  );
  try {
    await settings.setCategoryLocked(
      type,
      category,
      !wasLocked,
      profileId: profileId,
    );
  } catch (_) {
    if (!context.mounted) return;
    final message = settings.language == 'tr'
        ? 'Kategori kilidi kaydedilemedi'
        : settings.language == 'de'
            ? 'Kategoriesperre konnte nicht gespeichert werden'
            : 'Category lock could not be saved';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  sessionUnlocks.remove(parentalSessionKey(type, category));
  if (!context.mounted) return;
  final language = settings.language;
  final message = !wasLocked
      ? (language == 'tr'
          ? '$category kilitlendi'
          : language == 'de'
              ? '$category wurde gesperrt'
              : '$category was locked')
      : (language == 'tr'
          ? '$category kilidi kaldırıldı'
          : language == 'de'
              ? '$category wurde entsperrt'
              : '$category was unlocked');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> hideCategoryWithParentalControl(
  BuildContext context, {
  required SettingsProvider settings,
  required String type,
  required String category,
  String? profileId,
}) async {
  final hasPin = settings.hasParentalPin(profileId: profileId);
  final authorized = await requestParentalPin(
    context,
    settings: settings,
    profileId: profileId,
    createPin: !hasPin,
    waitForSelectRelease: true,
  );
  if (!authorized) return false;
  try {
    await settings.setCategoryHidden(
      type,
      category,
      true,
      profileId: profileId,
    );
  } catch (_) {
    if (!context.mounted) return false;
    final message = settings.language == 'tr'
        ? 'Kategori gizlenemedi'
        : settings.language == 'de'
            ? 'Kategorie konnte nicht ausgeblendet werden'
            : 'Category could not be hidden';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
  if (!context.mounted) return true;
  final message = settings.language == 'tr'
      ? '$category gizlendi'
      : settings.language == 'de'
          ? '$category wurde ausgeblendet'
          : '$category was hidden';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
  return true;
}
