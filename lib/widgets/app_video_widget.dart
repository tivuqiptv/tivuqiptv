import 'package:flutter/material.dart';
import '../services/player_engine.dart';

class AppVideoWidget extends StatelessWidget {
  final AppPlayerEngine playerEngine;
  final BoxFit fit;

  const AppVideoWidget({
    super.key,
    required this.playerEngine,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(playerEngine.engineType),
      child: playerEngine.adapter.buildPlayerView(fit: fit),
    );
  }
}
