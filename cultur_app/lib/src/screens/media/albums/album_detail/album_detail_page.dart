import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/controllers/tracking_controller.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/catalog/catalog_detail.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/models/rating_sheet_result.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/catalog_detail_providers.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import 'package:yamtrack/src/providers/followed_artists_provider.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/widgets/album_action_row.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/widgets/album_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/widgets/album_tracklist_section.dart';
import 'package:yamtrack/src/screens/media/albums/album_detail/widgets/album_musicbrainz_lookup_sheet.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_hero_carousel.dart';
import 'package:yamtrack/src/screens/media/games/game_detail/widgets/game_pending_catalog_banner.dart';
import 'package:yamtrack/src/screens/navbar/bar.dart';
import 'package:yamtrack/src/screens/widgets/game_lists_sheet.dart';
import 'package:yamtrack/src/screens/widgets/genres_tags_card.dart';
import 'package:yamtrack/src/screens/widgets/mark_watched_sheet.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/widgets/movie_rating_sheet.dart';
import 'package:yamtrack/src/screens/widgets/movie_recommendation_shelf.dart';
import 'package:yamtrack/src/screens/widgets/movie_video_shelf.dart';
import 'package:yamtrack/src/utils/album_collected_toggle_flow.dart';
import 'package:yamtrack/src/utils/library_utils.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({required this.mediaId, super.key});

  final String mediaId;

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage> {
  bool _isSaving = false;
  bool _showFullOverview = false;

  CatalogDetailRequest get _request {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    return CatalogDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      kind: CatalogDetailKind.music,
    );
  }

  Future<void> _runTrackingMutation({
    required Future<String?> Function(TrackingMutationController controller, String username)
        mutation,
  }) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final message = await mutation(ref.read(trackingMutationControllerProvider), username);
      if (message == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      ref.invalidate(catalogDetailProvider(_request));
      ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
      ref.invalidate(customMusicListsProvider);
      invalidateAlbumsHomeCaches(ref, username: username);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (context.mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _togglePriority(CatalogDetail detail) async {
    await _runTrackingMutation(
      mutation: (controller, username) => controller.togglePriority(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
      ),
    );
  }

  Widget _heroPriorityPin(CatalogDetail detail) {
    final inPriority = trackingIsPriority(detail.tracking);
    return GameHeroOverlayPinButton(
      icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
      tooltip: inPriority ? 'Remove from priority' : 'Priority — show in Next to listen',
      onPressed: _isSaving ? null : () => _togglePriority(detail),
    );
  }

  String _defaultAlbumShareUrl(CatalogDetail detail) {
    final meta = detail.media.metadata;
    final lfmUrl = meta['lastfmUrl']?.toString().trim();
    if (lfmUrl != null && lfmUrl.isNotEmpty) {
      return lfmUrl;
    }
    final artist = detail.media.subtitle?.trim() ?? '';
    final album = detail.media.title.trim();
    if (artist.isNotEmpty && album.isNotEmpty) {
      return 'https://www.last.fm/music/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(album)}';
    }
    return 'https://www.last.fm/';
  }

  ({String id, String? name, String? imageUrl})? _primaryArtist(CatalogDetail detail) {
    if (detail.cast.isNotEmpty) {
      final person = detail.cast.first;
      final personId = person.personId?.trim() ?? '';
      final mbFromPerson = parseMusicBrainzArtistPersonId(personId);
      if (mbFromPerson != null && mbFromPerson.isNotEmpty) {
        return (id: mbFromPerson, name: person.name, imageUrl: person.imageUrl);
      }
    }
    final artists = detail.media.metadata['artists'];
    if (artists is! List || artists.isEmpty) {
      return null;
    }
    final first = artists.first;
    if (first is! Map) {
      return null;
    }
    final id = first['id']?.toString();
    final name = first['name']?.toString();
    final imageUrl = first['imageUrl']?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    return (id: normalizeArtistMbid(id), name: name, imageUrl: imageUrl);
  }

  Future<void> _toggleFollowArtist(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to follow artists.')),
      );
      return;
    }
    final artist = _primaryArtist(detail);
    if (artist == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No artist linked to this album.')),
      );
      return;
    }

    final followedAsync = ref.read(followedMusicArtistIdsProvider(username));
    final followed = followedAsync.value ?? {};
    final isFollowing = followed.contains(compactArtistMbid(artist.id));

    setState(() => _isSaving = true);
    try {
      await ref.read(favoritePeopleControllerProvider).toggleMusicArtist(
            username: username,
            artistMbid: artist.id,
            name: artist.name ?? 'Artist',
            imageUrl: artist.imageUrl,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFollowing
                ? 'Unfollowed ${artist.name ?? 'artist'}.'
                : 'Following ${artist.name ?? 'artist'}.',
          ),
        ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(followedMusicArtistsProvider(username));
      ref.invalidate(favoritePeopleProvider);
      ref.invalidate(albumsMusicLatestProvider(username));
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Could not update follow:');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showListenedSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    final tracking = detail.tracking;
    final theme = Theme.of(context);
    final listened = trackingIsWatched(tracking);

    final result = await showModalBottomSheet<MarkWatchedSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: MarkWatchedSheet.forCatalog(
            media: detail.media,
            tracking: tracking,
            labels: MarkWatchedSheetLabels.album,
            isEditing: listened,
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.removeFromList) {
      await _runTrackingMutation(
        mutation: (controller, u) => controller.toggleWatched(
          username: u,
          media: detail.media,
          tracking: tracking,
        ),
      );
      return;
    }
    await _runTrackingMutation(
      mutation: (controller, u) => controller.markAsWatched(
        username: u,
        media: detail.media,
        tracking: tracking,
        completedAtUtc: result.completedAtUtc,
        score: result.score,
      ),
    );
  }

  Future<void> _showRatingSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }
    var stars = detail.tracking?.score?.round().clamp(0, 10) ?? 0;
    final hasExisting = detail.tracking?.score != null;

    final result = await showModalBottomSheet<RatingSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return MovieRatingSheet(
              title: 'Rate this album',
              prompt: 'Your rating',
              hasExistingRating: hasExisting,
              selectedStars: stars,
              onStarsChanged: (value) => setModalState(() => stars = value),
              onCancel: () => Navigator.of(context).pop(const RatingSheetDismissed()),
              onSave: () {
                if (stars <= 0) {
                  Navigator.of(context).pop(const RatingSheetRemoved());
                } else {
                  Navigator.of(context).pop(RatingSheetSet(stars.toDouble()));
                }
              },
            );
          },
        );
      },
    );

    switch (result) {
      case null:
      case RatingSheetDismissed():
        return;
      case RatingSheetRemoved():
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            remove: true,
          ),
        );
      case RatingSheetSet(:final score):
        await _runTrackingMutation(
          mutation: (controller, user) => controller.saveRating(
            username: user,
            media: detail.media,
            tracking: detail.tracking,
            score: score,
          ),
        );
    }
  }

  Future<void> _openMusicBrainzLookupSheet(CatalogDetail detail, {required bool isPending}) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to link this album.')),
      );
      return;
    }
    final resolvedId = await showAlbumMusicBrainzLookupSheet(
      context: context,
      ref: ref,
      mediaId: widget.mediaId,
      username: username,
      initialQuery: detail.media.title,
      isPending: isPending,
    );
    if (resolvedId == null || !mounted) {
      return;
    }
    ref.invalidate(catalogDetailProvider(_request));
    ref.invalidate(libraryTrackingForScopeProvider(LibraryMediaScope.music));
    ref.invalidate(customMusicListsProvider);
    invalidateAlbumsHomeCaches(ref, username: username);
    if (isPending && resolvedId != widget.mediaId) {
      context.pushReplacement('/albums/$resolvedId');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Album details updated from Last.fm.')),
    );
  }

  Future<void> _showListsSheet(CatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      return;
    }

    Future<void> createList() async {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Create custom list'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'List name'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      if (name == null || name.trim().isEmpty) {
        return;
      }
      await ref.read(customMusicListsControllerProvider).createList(username, name);
      ref.invalidate(customMusicListsProvider);
    }

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final listsAsync = ref.watch(customMusicListsProvider);
            return GameListsSheet(
              detail: detail,
              listsAsync: listsAsync,
              isBuiltInList: BuiltInMusicLists.isBuiltIn,
              itemLabel: 'albums',
              onCreateList: createList,
              onToggleList: (list) async {
                await ref.read(customMusicListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: detail.media,
                    );
                ref.invalidate(customMusicListsProvider);
              },
              onDone: () => Navigator.pop(context),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(catalogDetailProvider(_request));
    final theme = Theme.of(context);
    final username = ref.watch(authControllerProvider).asData?.value.session?.username ?? '';
    final followedAsync = username.isEmpty
        ? const AsyncValue<Set<String>>.data({})
        : ref.watch(followedMusicArtistIdsProvider(username));

    return Scaffold(
      extendBody: true,
      appBar: CulturAppBar(
        additionalActions: [
          IconButton(
            tooltip: 'Edit album',
            onPressed: () => context.push('/albums/${widget.mediaId}/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(catalogDetailProvider(_request)),
        ),
        data: (detail) {
          final overview = (detail.overview ?? '').trim();
          final tracking = detail.tracking;
          final scheme = theme.colorScheme;
          final collected = hasTrackingFlag(tracking, kCollectedTrackingFlag);
          final listened = trackingIsWatched(tracking);
          final artist = _primaryArtist(detail);
          final isFollowing = artist?.id != null &&
              (followedAsync.value ?? {}).contains(compactArtistMbid(artist!.id));
          final tracks = albumTracksFromMetadata(detail.media.metadata);
          final styleTags = detail.keywords;
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 120),
            children: [
              AlbumHeroCarousel(
                detail: detail,
                overlayActions: _heroPriorityPin(detail),
                onShareTap: () async {
                  final uri = detail.links.isNotEmpty
                      ? detail.links.first.url
                      : _defaultAlbumShareUrl(detail);
                  await Clipboard.setData(ClipboardData(text: uri));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied.')),
                    );
                  }
                },
              ),
              if (detail.catalogPending) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GamePendingCatalogBanner(
                    importSource: detail.importSource,
                    onSearchCatalog: () => _openMusicBrainzLookupSheet(detail, isPending: true),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: AlbumActionRow(
                  isSaving: _isSaving,
                  isInLater: trackingIsInWatchlist(tracking),
                  isFollowing: isFollowing,
                  isBuy: trackingIsBuy(tracking),
                  isOwned: collected,
                  rating: tracking?.score,
                  onLaterTap: () => _runTrackingMutation(
                    mutation: (controller, username) => controller.toggleWatchlist(
                      username: username,
                      media: detail.media,
                      tracking: tracking,
                    ),
                  ),
                  onFollowTap: artist == null ? () {} : () => _toggleFollowArtist(detail),
                  onBuyTap: () => _runTrackingMutation(
                    mutation: (controller, username) => controller.toggleBuy(
                      username: username,
                      media: detail.media,
                      tracking: tracking,
                    ),
                  ),
                  onOwnedTap: () => _runTrackingMutation(
                    mutation: (controller, username) => runAlbumCollectedToggle(
                      context: context,
                      controller: controller,
                      username: username,
                      media: detail.media,
                      tracking: tracking,
                    ),
                  ),
                  onRateTap: () => _showRatingSheet(detail),
                  onListsTap: () => _showListsSheet(detail),
                  below: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onPressed: _isSaving ? null : () => _showListenedSheet(detail),
                      icon: Icon(listened ? Icons.headphones : Icons.headphones_outlined),
                      label: Text(listened ? 'Listened' : 'Mark as listened'),
                    ),
                  ),
                ),
              ),
              if (detail.videos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MovieVideoShelf(
                    videos: detail.videos,
                    onOpenVideo: (url) async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              ],
              if (detail.genres.isNotEmpty || styleTags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GenresTagsCard(
                    genres: detail.genres,
                    keywords: styleTags,
                  ),
                ),
              ],
              if (tracks.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AlbumTracklistSection(tracks: tracks),
                ),
              ],
              if (overview.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Overview', style: CulturCatalogTypography.sectionHeading(theme)),
                      const SizedBox(height: 8),
                      Text(
                        overview,
                        maxLines: _showFullOverview ? null : 6,
                        overflow: _showFullOverview ? null : TextOverflow.ellipsis,
                        style: CulturCatalogTypography.bodyText(theme, scheme),
                      ),
                      if (overview.length > 280)
                        TextButton(
                          onPressed: () => setState(() => _showFullOverview = !_showFullOverview),
                          child: Text(_showFullOverview ? 'Show less' : 'Read more'),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _openMusicBrainzLookupSheet(
                            detail,
                            isPending: detail.catalogPending,
                          ),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(
                    detail.catalogPending
                        ? 'Search Last.fm to link'
                        : 'Search Last.fm to update details',
                  ),
                ),
              ),
              if (detail.recommendations.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MovieRecommendationShelf(
                    items: detail.recommendations,
                    onOpenRecommendation: (item) => context.push('/albums/${item.id}'),
                  ),
                ),
              ],
              if (detail.links.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: MediaDetailLinksSection(
                    links: detail.links,
                    onOpenLink: (url) async {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.music,
      ),
    );
  }
}
