import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/models/lists/custom_movie_list.dart';
import 'package:yamtrack/src/models/lists/custom_movie_lists_data.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';
import 'package:yamtrack/src/utils/library_item_search.dart';
import 'package:yamtrack/src/providers/custom_lists_providers.dart';
import '../navbar/bar.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import 'package:yamtrack/src/providers/person_providers.dart';
import 'package:yamtrack/src/providers/library_tracking_providers.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';
import 'package:yamtrack/src/providers/albums_home_providers.dart';
import 'package:yamtrack/src/providers/followed_artists_provider.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/utils/musicbrainz_person_utils.dart';
import 'package:yamtrack/src/utils/openlibrary_person_utils.dart';
import '../widgets/movie_tab_bar.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/person/person_catalog_detail.dart';
import 'package:yamtrack/src/models/tracking/tracking_models.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_home_poster_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

part 'person_detail_details_tab_part.dart';
part 'person_detail_filmography_digest_part.dart';
part 'person_detail_filmography_widgets_part.dart';
part 'person_detail_filmography_panel_part.dart';

class PersonDetailPage extends ConsumerStatefulWidget {
  const PersonDetailPage({required this.personId, super.key});

  final String personId;

  @override
  ConsumerState<PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends ConsumerState<PersonDetailPage> {
  int _tabIndex = 0;
  bool _bioExpanded = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool get _isBookAuthor => isBookAuthorPersonId(widget.personId);

  bool get _isMusicBrainzArtist => isMusicBrainzArtistPersonId(widget.personId);

  bool _isMusicArtistPage(PersonCatalogDetail person) {
    if (_isMusicBrainzArtist) {
      return true;
    }
    final dept = person.knownForDepartment?.trim().toLowerCase();
    if (dept == 'artist' || dept == 'group') {
      return true;
    }
    final film = person.filmography;
    return film.isNotEmpty && film.every((entry) => entry.mediaType == 'music');
  }

  Future<void> _openFilmographyEntry(PersonFilmographyEntry e) async {
    if (e.mediaType == 'book') {
      if (!mounted) {
        return;
      }
      context.push('/books/${e.media.id}');
      return;
    }
    if (e.mediaType == 'music') {
      if (!mounted) {
        return;
      }
      context.push(catalogItemDetailPath(e.media));
      return;
    }
    if (e.mediaType == 'movie') {
      if (!mounted) {
        return;
      }
      context.push('/movies/${e.media.id}');
      return;
    }
    final uri = Uri.parse('https://www.themoviedb.org/tv/${e.media.externalId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  int _watchedCountInFilmography(PersonCatalogDetail person, Set<String> watchedIds) {
    var n = 0;
    for (final entry in person.filmography) {
      if (watchedIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  int _readCountInBibliography(PersonCatalogDetail person, Set<String> readIds) {
    var n = 0;
    for (final entry in person.filmography) {
      if (readIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  int _listenedCountInDiscography(PersonCatalogDetail person, Set<String> listenedIds) {
    var n = 0;
    for (final entry in person.filmography) {
      if (listenedIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  Future<void> _toggleFollowMusicArtist({
    required String username,
    required PersonCatalogDetail person,
  }) async {
    final artistId = parseMusicBrainzArtistPersonId(person.personId);
    if (artistId == null) {
      return;
    }
    final id = normalizeArtistMbid(artistId);
    final followedAsync = ref.read(followedMusicArtistIdsProvider(username));
    final followed = followedAsync.value ?? {};
    final isFollowing = followed.contains(compactArtistMbid(id));

    try {
      await ref.read(favoritePeopleControllerProvider).toggleMusicArtist(
            username: username,
            artistMbid: id,
            name: person.name,
            imageUrl: person.imageUrl,
          );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isFollowing ? 'Unfollowed ${person.name}.' : 'Following ${person.name}.'),
        ),
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(followedMusicArtistsProvider(username));
      ref.invalidate(favoritePeopleProvider);
      ref.invalidate(albumsMusicLatestProvider(username));
    } catch (error) {
      if (context.mounted) {
        showApiErrorSnackBar(context, error, prefix: 'Could not update follow:');
      }
    }
  }

  Future<void> _toggleFavorite({
    required String username,
    required PersonCatalogDetail person,
  }) async {
    await ref.read(favoritePeopleControllerProvider).toggleFavoritePerson(
          username: username,
          routePersonId: person.personId,
          name: person.name,
          imageUrl: person.imageUrl,
        );
    ref.invalidate(favoritePeopleProvider);
  }

  void _requireSessionSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final asyncPerson = ref.watch(personCatalogDetailProvider(widget.personId));
    final digestAsync = _isBookAuthor || _isMusicBrainzArtist
        ? null
        : ref.watch(userMovieTrackingDigestProvider);
    final bookTrackingAsync = _isBookAuthor
        ? ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.book))
        : null;
    final musicTrackingAsync = !_isBookAuthor
        ? ref.watch(libraryTrackingForScopeProvider(LibraryMediaScope.music))
        : null;
    final favoritesAsync = _isMusicBrainzArtist ? null : ref.watch(favoritePeopleProvider);
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final isLoggedIn = username != null && username.isNotEmpty;
    final followedArtistsAsync = _isMusicBrainzArtist && isLoggedIn
        ? ref.watch(followedMusicArtistIdsProvider(username))
        : null;
    final watchedIds = switch (digestAsync) {
      AsyncData(:final value) => value.watchedIds,
      _ => <String>{},
    };
    final readIds = switch (bookTrackingAsync) {
      AsyncData(:final value) => value.items
          .where(trackingIsWatched)
          .map((item) => item.media.id)
          .toSet(),
      _ => <String>{},
    };
    final listenedIds = switch (musicTrackingAsync) {
      AsyncData(:final value) => value.items
          .where(trackingIsWatched)
          .map((item) => item.media.id)
          .toSet(),
      _ => <String>{},
    };

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: asyncPerson.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(personCatalogDetailProvider(widget.personId)),
        ),
        data: (person) {
          final isMusicArtist = _isMusicArtistPage(person);
          final watchedCount = _isBookAuthor
              ? _readCountInBibliography(person, readIds)
              : isMusicArtist
              ? _listenedCountInDiscography(person, listenedIds)
              : _watchedCountInFilmography(person, watchedIds);
          final favoriteData = switch (favoritesAsync) {
            AsyncData(:final value) => value,
            _ => const FavoritePeopleData(people: []),
          };
          final isFavorite = favoriteData.people.any(
            (p) => (p.personId ?? '') == person.personId,
          );
          final artistMbid = parseMusicBrainzArtistPersonId(person.personId);
          final isFollowing = switch (followedArtistsAsync) {
            AsyncData(:final value) =>
              artistMbid != null && value.contains(compactArtistMbid(artistMbid)),
            _ => false,
          };

          final tabBody = switch (_tabIndex) {
            1 => PersonFilmographyPanel(
                entries: person.filmography,
                booksOnly: _isBookAuthor,
                musicOnly: _isMusicBrainzArtist,
              ),
            _ => _PersonDetailsTab(
                person: person,
                bioExpanded: _bioExpanded,
                popularSectionTitle: _isMusicBrainzArtist ? 'Popular albums' : 'Popular titles',
                onToggleBio: () {
                  setState(() {
                    _bioExpanded = !_bioExpanded;
                  });
                },
                onOpenLink: _openUrl,
                onOpenFilmographyEntry: _openFilmographyEntry,
              ),
          };

          return RefreshIndicator(
            onRefresh: () async {
              if (!mounted) {
                return;
              }
              final futures = <Future<void>>[
                ref.refresh(personCatalogDetailProvider(widget.personId).future),
              ];
              if (_isBookAuthor) {
                futures.add(
                  ref.refresh(libraryTrackingForScopeProvider(LibraryMediaScope.book).future),
                );
              } else if (isMusicArtist) {
                futures.add(
                  ref.refresh(libraryTrackingForScopeProvider(LibraryMediaScope.music).future),
                );
              } else {
                futures.add(ref.refresh(userMovieTrackingDigestProvider.future));
              }
              if (isLoggedIn && _isMusicBrainzArtist) {
                futures.add(ref.refresh(followedMusicArtistsProvider(username).future));
              } else if (isLoggedIn) {
                futures.add(ref.refresh(favoritePeopleProvider.future));
              }
              await Future.wait(futures);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _PersonProfileHeader(
                  person: person,
                  watchedCount: watchedCount,
                  isLoggedIn: isLoggedIn,
                  isFavorite: _isMusicBrainzArtist ? isFollowing : isFavorite,
                  onWatchedTap: !isLoggedIn
                      ? () => _requireSessionSnack(
                            _isBookAuthor
                                ? 'Sign in to see how many of these books you have read.'
                                : isMusicArtist
                                ? 'Sign in to see how many of these albums you have listened to.'
                                : 'Sign in to see how many of these films you have watched.',
                          )
                      : watchedCount == 0
                      ? null
                      : () {
                          setState(() {
                            _tabIndex = 1;
                          });
                        },
                  watchedLabel: _isBookAuthor
                      ? 'Read'
                      : isMusicArtist
                      ? 'Listened'
                      : 'Watched',
                  useFollowButton: _isMusicBrainzArtist,
                  isFollowing: isFollowing,
                  onFavoriteTap: !isLoggedIn
                      ? () => _requireSessionSnack(
                            _isMusicBrainzArtist
                                ? 'Sign in to follow artists.'
                                : 'Sign in to add people to your favorites list.',
                          )
                      : _isMusicBrainzArtist
                      ? () async {
                          await _toggleFollowMusicArtist(
                            username: username,
                            person: person,
                          );
                        }
                      : () async {
                          await _toggleFavorite(username: username, person: person);
                        },
                ),
                const SizedBox(height: 20),
                MovieTabBar(
                  selectedIndex: _tabIndex,
                  onSelected: (index) {
                    setState(() {
                      _tabIndex = index;
                    });
                  },
                  tabs: _isBookAuthor
                      ? const ['Details', 'Bibliography']
                      : isMusicArtist
                      ? const ['Details', 'Discography']
                      : const ['Details', 'Filmography'],
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_tabIndex),
                    child: tabBody,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: _isBookAuthor
            ? LibraryMediaScope.book
            : _isMusicBrainzArtist
            ? LibraryMediaScope.music
            : LibraryMediaScope.movie,
      ),
    );
  }
}
