import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/core/api_client_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/core/session_storage.dart';
import 'package:yamtrack/src/core/storage_keys.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
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
import 'package:yamtrack/src/utils/bookmory_parser.dart';
import 'package:yamtrack/src/utils/musicboard_csv_parser.dart';
import 'package:yamtrack/src/utils/stash_csv_parser.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

part '../profile/profile_bgg_import_part.dart';
part '../profile/profile_bookmory_import_part.dart';
part '../profile/profile_hardcover_import_part.dart';
part '../profile/profile_stash_import_part.dart';
part '../profile/profile_musicboard_import_part.dart';

/// Imports from external services (BGG, Bookmory, Hardcover, Stash, Musicboard).
class LibraryExternalImportPage extends ConsumerWidget {
  const LibraryExternalImportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final session = authState?.session;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CulturAppBar(
        backEnabled: true,
        onBack: () => context.pop(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(
            'Import from other apps',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull your library from BoardGameGeek, Bookmory, Hardcover, Stash, or Musicboard. '
            'For a full Cultur JSON backup, use Backup (import & export) in Profile.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (session != null && session.username.isNotEmpty) ...[
            const SizedBox(height: 20),
            _ProfileBggImportCard(theme: theme, username: session.username),
            const SizedBox(height: 16),
            _ProfileBookmoryImportCard(theme: theme, username: session.username),
            const SizedBox(height: 16),
            _ProfileHardcoverImportCard(theme: theme, username: session.username),
            const SizedBox(height: 16),
            _ProfileStashImportCard(theme: theme, username: session.username),
            const SizedBox(height: 16),
            _ProfileMusicboardImportCard(theme: theme, username: session.username),
          ] else ...[
            const SizedBox(height: 24),
            Text(
              'Sign in to import from external services.',
              style: CulturCatalogTypography.listMeta(theme, theme.colorScheme),
            ),
          ],
        ],
      ),
    );
  }
}
