import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yamtrack/src/screens/helpers/error_state.dart';
import 'package:yamtrack/src/providers/company_providers.dart';
import '../navbar/bar.dart';
import 'package:yamtrack/src/models/library/library_media_scope.dart';
import 'package:yamtrack/src/controllers/auth_controller.dart';
import '../widgets/movie_tab_bar.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/models/games/game_company_catalog_detail.dart';
import 'package:yamtrack/src/widgets/cultur_app_bar.dart';
import 'package:yamtrack/src/screens/widgets/media_detail_links_section.dart';
import 'package:yamtrack/src/screens/media/games/home/widgets/game_home_poster_card.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_list_row.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/utils/igdb_image_url.dart';

part 'company_detail_header_part.dart';
part 'company_detail_details_tab_part.dart';
part 'company_detail_catalog_part.dart';

class CompanyDetailPage extends ConsumerStatefulWidget {
  const CompanyDetailPage({
    required this.companyId,
    this.role = 'publisher',
    this.initialName,
    super.key,
  });

  final String companyId;
  final String role;
  final String? initialName;

  @override
  ConsumerState<CompanyDetailPage> createState() => _CompanyDetailPageState();
}

class _CompanyDetailPageState extends ConsumerState<CompanyDetailPage> {
  int _tabIndex = 0;
  bool _bioExpanded = false;

  GameCompanyDetailRequest get _request => GameCompanyDetailRequest(
        companyId: widget.companyId,
        role: widget.role,
      );

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _openCatalogItem(GameCompanyCatalogItem item) {
    context.push('/games/${item.media.id}');
  }

  int _watchedCountInCatalog(GameCompanyCatalogDetail company, Set<String> watchedIds) {
    var n = 0;
    for (final entry in _dedupeCompanyCatalogItems(company.catalog)) {
      if (watchedIds.contains(entry.media.id)) {
        n++;
      }
    }
    return n;
  }

  Future<void> _toggleFavorite({
    required String username,
    required GameCompanyCatalogDetail company,
  }) async {
    await ref.read(favoriteCompaniesControllerProvider).toggleFavoriteCompany(
          username: username,
          companyId: company.companyId,
          name: company.name,
          role: widget.role,
          imageUrl: company.imageUrl,
        );
    ref.invalidate(favoriteCompaniesProvider);
  }

  void _requireSessionSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final asyncCompany = ref.watch(gameCompanyCatalogDetailProvider(_request));
    final digestAsync = ref.watch(userGameTrackingDigestProvider);
    final favoritesAsync = ref.watch(favoriteCompaniesProvider);
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    final isLoggedIn = username != null && username.isNotEmpty;
    final watchedIds = switch (digestAsync) {
      AsyncData(:final value) => value.watchedIds,
      _ => <String>{},
    };

    return Scaffold(
      appBar: const CulturAppBar(),
      extendBody: true,
      body: asyncCompany.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(gameCompanyCatalogDetailProvider(_request)),
        ),
        data: (company) {
          final watchedCount = _watchedCountInCatalog(company, watchedIds);
          final favoriteData = switch (favoritesAsync) {
            AsyncData(:final value) => value,
            _ => const FavoriteCompaniesData(companies: []),
          };
          final isFavorite = favoriteData.companies.any(
            (c) => c.companyId == company.companyId,
          );
          final displayName = company.name.isNotEmpty
              ? company.name
              : (widget.initialName?.trim().isNotEmpty == true
                  ? widget.initialName!.trim()
                  : 'Company');

          final tabBody = switch (_tabIndex) {
            1 => _CompanyCatalogTab(
                items: company.catalog,
                digest: switch (digestAsync) {
                  AsyncData(:final value) => value,
                  _ => const UserGameTrackingDigest(watchedIds: {}, byMediaId: {}),
                },
                onOpenItem: _openCatalogItem,
              ),
            _ => _CompanyDetailsTab(
                company: company,
                displayName: displayName,
                bioExpanded: _bioExpanded,
                onToggleBio: () {
                  setState(() {
                    _bioExpanded = !_bioExpanded;
                  });
                },
                onOpenLink: _openUrl,
                onOpenCatalogItem: _openCatalogItem,
              ),
          };

          return RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.refresh(gameCompanyCatalogDetailProvider(_request).future),
                ref.refresh(userGameTrackingDigestProvider.future),
                if (isLoggedIn) ref.refresh(favoriteCompaniesProvider.future),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                _CompanyProfileHeader(
                  company: company,
                  displayName: displayName,
                  watchedCount: watchedCount,
                  isLoggedIn: isLoggedIn,
                  isFavorite: isFavorite,
                  onWatchedTap: !isLoggedIn
                      ? () => _requireSessionSnack(
                            'Sign in to see how many of these games you have played.',
                          )
                      : watchedCount == 0
                      ? null
                      : () {
                          setState(() {
                            _tabIndex = 1;
                          });
                        },
                  onFavoriteTap: !isLoggedIn
                      ? () => _requireSessionSnack(
                            'Sign in to add companies to your favorites list.',
                          )
                      : () async {
                          await _toggleFavorite(username: username, company: company);
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
                  tabs: const ['Details', 'Catalog'],
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
      bottomNavigationBar: const FloatingLibraryNav(
        currentDestination: FloatingLibraryDestination.home,
        mediaScope: LibraryMediaScope.game,
      ),
    );
  }
}
