import 'package:flutter/material.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/app_build_config.dart';

class ServerSetupPage extends ConsumerStatefulWidget {
  const ServerSetupPage({super.key});

  @override
  ConsumerState<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends ConsumerState<ServerSetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initialValue = ref
        .read(authControllerProvider)
        .asData
        ?.value
        .serverApiBaseUrl;
    _controller = TextEditingController(
      text: initialValue ??
          (AppBuildConfig.hasDefaultApiBaseUrl
              ? AppBuildConfig.defaultApiBaseUrl
              : 'http://localhost:8787'),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .saveServerApiUrl(_controller.text);
    } catch (error) {
      if (!mounted) {
        return;
      }
      showApiErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up cult.u.r')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Use the API URL for your cult.u.r server.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'cult.u.r talks only to your API layer, so the upstream tracker stays insulated.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server API URL',
                    hintText: 'https://media.example.com:8787',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    final uri = Uri.tryParse(text);
                    if (uri == null || uri.host.isEmpty || !uri.hasScheme) {
                      return 'Enter a valid http:// or https:// URL.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward),
                    label: const Text('Save and continue'),
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
