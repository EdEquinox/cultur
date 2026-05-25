import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/core/app_build_config.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/auth/auth_session.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/app_accent_provider.dart';
import 'package:yamtrack/src/providers/boardgames_home_providers.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/providers/catalog_shelf_providers.dart';
import 'package:yamtrack/src/providers/catalog_tracking_providers.dart';
import 'package:yamtrack/src/providers/company_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/followed_artists_provider.dart';
import 'package:yamtrack/src/providers/games_home_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/next_to_watch_providers.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/providers/publisher_providers.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

part 'profile_identity_server_part.dart';
part 'profile_appearance_settings_part.dart';
part 'profile_purge_library_part.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final session = authState?.session;
    final accentId = ref.watch(culturAccentProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: const CulturAppBar(showProfileAction: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _ProfileUserCard(session: session, theme: theme),
          const SizedBox(height: 16),
          _ProfileAppearanceSettingsCard(
            theme: theme,
            selected: accentId,
            onAccentSelected: (id) =>
                ref.read(culturAccentProvider.notifier).setAccent(id),
          ),
          const SizedBox(height: 16),
          _ProfileServerCard(
            serverUrl: authState?.serverApiBaseUrl,
            theme: theme,
          ),
          if (kIsWeb && AppBuildConfig.hasAndroidApkUrl) ...[
            const SizedBox(height: 12),
            _ProfileAndroidInstallCard(theme: theme),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_download_outlined, color: theme.colorScheme.primary),
            title: Text('Import from other apps', style: CulturCatalogTypography.listTitle(theme)),
            subtitle: Text(
              'BGG, Bookmory, Hardcover, Stash, Musicboard',
              style: CulturCatalogTypography.listMeta(theme, scheme),
            ),
            onTap: () => context.push('/library/external-import'),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restore_rounded, color: theme.colorScheme.primary),
            title: Text('Backup (import & export)', style: CulturCatalogTypography.listTitle(theme)),
            subtitle: Text(
              'Export or import your Cultur library as JSON',
              style: CulturCatalogTypography.listMeta(theme, scheme),
            ),
            onTap: () => context.push('/library/backup'),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined, color: theme.colorScheme.error),
            title: Text(
              'Delete library data',
              style: CulturCatalogTypography.listTitle(theme).copyWith(color: scheme.error),
            ),
            subtitle: Text(
              'Choose categories to remove (tracking, lists, favorites).',
              style: CulturCatalogTypography.listMeta(theme, scheme),
            ),
            onTap: _confirmAndPurgeLibraryData,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.movie,
      ),
    );
  }
}
