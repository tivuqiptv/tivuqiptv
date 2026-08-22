import 'package:flutter/material.dart';

/// Opens TV dialogs without the framework's default entrance/exit animation.
///
/// This is intentionally limited to presentation. Dialog contents and any
/// playback-related work they trigger remain unchanged.
Future<T?> showInstantDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    barrierLabel: barrierDismissible
        ? (barrierLabel ??
            MaterialLocalizations.of(context).modalBarrierDismissLabel)
        : barrierLabel,
    transitionDuration: Duration.zero,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    pageBuilder: (context, _, __) => builder(context),
  );
}
