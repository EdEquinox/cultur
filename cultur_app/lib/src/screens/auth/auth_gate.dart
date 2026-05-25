import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/screens/auth/native_welcome_page.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/auth/login_page.dart';
import 'package:yamtrack/src/screens/auth/server_setup.dart';

class AuthGatePage extends ConsumerWidget {
  const AuthGatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return authState.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(authControllerProvider),
        ),
      ),
      data: (state) {
        if (!state.hasConfiguredServer) {
          return const ServerSetupPage();
        }

        if (!state.isAuthenticated) {
          return LoginPage(baseUrl: state.serverApiBaseUrl!);
        }

        return NativeWelcomePage(session: state.session!);
      },
    );
  }
}
