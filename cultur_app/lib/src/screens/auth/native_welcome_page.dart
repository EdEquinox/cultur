import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/auth/auth_session.dart';
import 'package:yamtrack/src/screens/home/home_page.dart';

class NativeWelcomePage extends StatelessWidget {
  const NativeWelcomePage({required this.session, super.key});

  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    return HomePage(session: session);
  }
}
