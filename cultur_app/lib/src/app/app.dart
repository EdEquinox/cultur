import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_accent_provider.dart';
import 'router.dart';
import 'theme.dart';

class CulturApp extends ConsumerWidget {
  const CulturApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final accent = ref.watch(culturAccentOptionProvider);

    return MaterialApp.router(
      title: 'cult.u.r',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(accentSeed: accent.seed),
      routerConfig: router,
    );
  }
}
