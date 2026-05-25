import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({required this.baseUrl, super.key});

  final String baseUrl;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _isRegisterMode = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (_isRegisterMode) {
        await ref
            .read(authControllerProvider.notifier)
            .register(
              username: _usernameController.text.trim(),
              password: _passwordController.text,
              displayName: _displayNameController.text,
            );
      } else {
        await ref
            .read(authControllerProvider.notifier)
            .signIn(
              username: _usernameController.text.trim(),
              password: _passwordController.text,
            );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isRegisterMode ? 'Create account' : 'Sign in'),
        actions: [
          IconButton(
            tooltip: 'Change server',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).clearServerApiUrl(),
            icon: const Icon(Icons.settings_ethernet),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Connected to ${widget.baseUrl}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _isRegisterMode
                ? 'Create your cult.u.r account on this server.'
                : 'Sign in to your cult.u.r account.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Column(
              children: [
                if (_isRegisterMode) ...[
                  TextFormField(
                    controller: _displayNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Enter your username.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Enter your password.';
                    }
                    if (_isRegisterMode && (value?.length ?? 0) < 8) {
                      return 'Use at least 8 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isRegisterMode ? 'Create account' : 'Sign in'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          setState(() => _isRegisterMode = !_isRegisterMode);
                        },
                  child: Text(
                    _isRegisterMode
                        ? 'Already have an account? Sign in'
                        : 'Need an account? Register',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
