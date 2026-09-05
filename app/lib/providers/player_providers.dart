import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'player_provider.dart';

final playerProvider = Provider<PlayerController>((ref) {
  final controller = PlayerController();
  ref.onDispose(controller.dispose);
  return controller;
});
