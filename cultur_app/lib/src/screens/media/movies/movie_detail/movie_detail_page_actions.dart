part of 'movie_detail_page.dart';

mixin _MovieDetailPageActions on ConsumerState<MovieDetailPage> {
  bool _isSaving = false;
  bool _showFullOverview = false;
  int _selectedTabIndex = 0;

  Future<void> _runTrackingMutation({
    required Future<String?> Function(
      TrackingMutationController controller,
      String username,
    )
    mutation,
  }) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
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
      final successMessage = await mutation(
        ref.read(trackingMutationControllerProvider),
        username,
      );
      if (successMessage == null) {
        return;
      }
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(
            mediaId: widget.mediaId,
            username: username,
            isTv: widget.isTv,
          ),
        ),
      );
      ref.invalidate(
        libraryTrackingForScopeProvider(
          widget.isTv ? LibraryMediaScope.tv : LibraryMediaScope.movie,
        ),
      );
      if (widget.isTv && username.isNotEmpty) {
        ref.invalidate(tvHomeShelvesProvider(username));
        ref.invalidate(tvSearchTrackingProvider(username));
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
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

  Future<void> _startWatchingTv(MovieCatalogDetail detail) async {
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

    if (tvSeriesHasEpisodeProgress(detail.tracking)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already started — check Continue watching on TV home.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await startTvSeriesFromFirstEpisode(
        episodes: ref.read(episodeWatchMutationControllerProvider),
        tracking: ref.read(trackingMutationControllerProvider),
        username: username,
        media: detail.media,
        trackingItem: detail.tracking,
      );
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(mediaId: widget.mediaId, username: username, isTv: true),
        ),
      );
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      ref.invalidate(tvHomeShelvesProvider(username));
      ref.invalidate(tvSearchTrackingProvider(username));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Episode 1 marked — find the next episode under Continue watching.',
          ),
        ),
      );
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

  Future<void> _togglePriority(MovieCatalogDetail detail) async {
    await _runTrackingMutation(
      mutation: (controller, username) => controller.togglePriority(
            username: username,
            media: detail.media,
            tracking: detail.tracking,
          ),
    );
  }

  Future<void> _showRatingSheet(MovieCatalogDetail detail) async {
    final current = detail.tracking?.score;
    final hasExisting = current != null && current > 0;
    var stars = (current ?? 7).round().clamp(0, 10);

    final theme = Theme.of(context);
    final isTv = widget.isTv;
    final result = await showModalBottomSheet<RatingSheetResult>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return MovieRatingSheet(
              title: isTv ? 'Rate this show' : 'Rate this movie',
              prompt: isTv ? 'Rate series?' : 'Rate movie?',
              hasExistingRating: hasExisting,
              selectedStars: stars,
              onStarsChanged: (value) {
                setModalState(() {
                  stars = value;
                });
              },
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
          mutation: (controller, username) => controller.saveRating(
            username: username,
            media: detail.media,
            tracking: detail.tracking,
            remove: true,
          ),
        );
      case RatingSheetSet(:final score):
        await _runTrackingMutation(
          mutation: (controller, username) => controller.saveRating(
            username: username,
            media: detail.media,
            tracking: detail.tracking,
            score: score,
          ),
        );
    }
  }

  Future<void> _showWatchedSheet(MovieCatalogDetail detail) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    final theme = Theme.of(context);
    final watched = trackingIsWatched(detail.tracking);

    if (watched) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        builder: (context) => RemoveWatchedSheet(detail: detail),
      );
      if (confirmed != true || !mounted) {
        return;
      }
      await _runTrackingMutation(
        mutation: (controller, u) => controller.toggleWatched(
          username: u,
          media: detail.media,
          tracking: detail.tracking,
        ),
      );
      return;
    }

    if (widget.isTv) {
      await _showTvMarkWatchedSheetAndApply(detail: detail, username: username);
      return;
    }

    final result = await showModalBottomSheet<MarkWatchedSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: MarkWatchedSheet(detail: detail),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }
    await _runTrackingMutation(
      mutation: (controller, u) => controller.markAsWatched(
        username: u,
        media: detail.media,
        tracking: detail.tracking,
        completedAtUtc: result.completedAtUtc,
        score: result.score,
      ),
    );
  }

  Future<void> _showTvWatchedProgressFromSeasonsTab() async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update tracking.')),
      );
      return;
    }

    final request = MovieDetailRequest(
      mediaId: widget.mediaId,
      username: username,
      isTv: true,
    );
    final detail = ref.read(movieDetailProvider(request)).asData?.value;
    if (detail == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still loading show details. Try again in a moment.')),
      );
      return;
    }

    await _showTvMarkWatchedSheetAndApply(detail: detail, username: username);
  }

  Future<void> _showTvMarkWatchedSheetAndApply({
    required MovieCatalogDetail detail,
    required String username,
  }) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<TvMarkWatchedProgressResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: TvMarkWatchedProgressSheet(
            mediaId: widget.mediaId,
            username: username,
            detail: detail,
          ),
        );
      },
    );
    if (result == null || !mounted) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(episodeWatchMutationControllerProvider).markEpisodesWatchedThrough(
        username: username,
        mediaId: widget.mediaId,
        throughSeasonNumber: result.throughSeasonNumber,
        throughEpisodeNumber: result.throughEpisodeNumber,
        watchedAtUtc: result.watchedAtUtc,
      );
      await ref.read(trackingMutationControllerProvider).markAsWatched(
        username: username,
        media: detail.media,
        tracking: detail.tracking,
        completedAtUtc: result.watchedAtUtc,
        score: result.score,
      );
      ref.invalidate(
        movieDetailProvider(
          MovieDetailRequest(
            mediaId: widget.mediaId,
            username: username,
            isTv: widget.isTv,
          ),
        ),
      );
      ref.invalidate(tvSeasonListCatalogProvider(widget.mediaId));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Progress saved through S${result.throughSeasonNumber} '
            'E${result.throughEpisodeNumber}.',
          ),
        ),
      );
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

  Future<void> _showListsSheet(MovieCatalogDetail detail) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to manage lists.')),
      );
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
              decoration: const InputDecoration(
                labelText: 'List name',
                hintText: 'Favorites, Rewatch, Film noir...',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
      if (name == null || name.trim().isEmpty) {
        return;
      }
      final list = await ref
          .read(customListsControllerProvider)
          .createList(username, name.trim());
      await ref.read(customListsControllerProvider).toggleItem(
            username: username,
            listId: list.id,
            item: detail.media,
          );
      ref.invalidate(customMovieListsProvider);
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final listsAsync = ref.watch(customMovieListsProvider);
            return MovieListsSheet(
              detail: detail,
              listsAsync: listsAsync,
              onCreateList: () async {
                await createList();
                ref.invalidate(customMovieListsProvider);
              },
              onToggleList: (list) async {
                await ref.read(customListsControllerProvider).toggleItem(
                      username: username,
                      listId: list.id,
                      item: detail.media,
                    );
                ref.invalidate(customMovieListsProvider);
              },
              onDone: () => Navigator.of(context).pop(),
            );
          },
        );
      },
    );
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open the link.')));
    }
  }

  Future<void> _toggleBuiltInList(MovieCatalogDetail detail, String listId) async {
    final authState = ref.read(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need an active session to update lists.')),
      );
      return;
    }

    final controller = ref.read(customListsControllerProvider);
    final listsBefore = await controller.load(username);
    CustomMovieList? target;
    for (final list in listsBefore.lists) {
      if (list.id == listId) {
        target = list;
        break;
      }
    }
    final hadItem = target?.items.any((i) => i.id == detail.media.id) ?? false;

    await controller.toggleItem(
      username: username,
      listId: listId,
      item: detail.media,
    );

    if (!hadItem && !trackingIsInWatchlist(detail.tracking)) {
      try {
        await ref.read(trackingMutationControllerProvider).toggleWatchlist(
              username: username,
              media: detail.media,
              tracking: detail.tracking,
            );
      } catch (error) {
        if (!mounted) {
          return;
        }
        showApiErrorSnackBar(context, error);
      }
    }

    ref.invalidate(customMovieListsProvider);
    ref.invalidate(
      movieDetailProvider(
        MovieDetailRequest(
          mediaId: widget.mediaId,
          username: username,
          isTv: widget.isTv,
        ),
      ),
    );
  }

  Widget? _movieHeroOverlayActions(MovieCatalogDetail detail) {
    final authState = ref.watch(authControllerProvider).asData?.value;
    final username = authState?.session?.username;
    if (username == null || username.isEmpty) {
      return null;
    }

    if (widget.isTv) {
      final inPriority = trackingIsPriority(detail.tracking);
      return _MovieHeroOverlayPinRow(
        children: [
          _MovieHeroOverlayPinButton(
            icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
            tooltip: inPriority
                ? 'Remove from priority queue'
                : 'Priority — show in Next to watch on TV home',
            onPressed: _isSaving ? null : () => _togglePriority(detail),
          ),
        ],
      );
    }

    final recentRelease = catalogItemReleasedWithinLastDays(detail.media, days: 30);
    final upcomingRelease = catalogItemNotYetReleased(detail.media);
    final showCinemaPin = recentRelease || upcomingRelease;
    final listsAsync = ref.watch(customMovieListsProvider);

    var inPriority = false;
    var inCinema = false;
    final listsData = listsAsync.asData?.value;
    if (listsData != null) {
      for (final list in listsData.lists) {
        if (list.id == BuiltInMovieLists.priorityListId) {
          inPriority = list.items.any((i) => i.id == detail.media.id);
        }
        if (list.id == BuiltInMovieLists.cinemaListId) {
          inCinema = list.items.any((i) => i.id == detail.media.id);
        }
      }
    }

    return _MovieHeroOverlayPinRow(
      children: [
        _MovieHeroOverlayPinButton(
          icon: inPriority ? Icons.push_pin : Icons.push_pin_outlined,
          tooltip: inPriority ? 'Remove from priority queue' : 'Add to priority queue',
          onPressed: listsAsync.isLoading
              ? null
              : () => _toggleBuiltInList(detail, BuiltInMovieLists.priorityListId),
        ),
        if (showCinemaPin)
          _MovieHeroOverlayPinButton(
            icon: inCinema ? Icons.theaters : Icons.theaters_outlined,
            tooltip: inCinema ? 'Remove from cinema list' : 'Add to movies in cinema',
            onPressed: listsAsync.isLoading
                ? null
                : () => _toggleBuiltInList(detail, BuiltInMovieLists.cinemaListId),
          ),
      ],
    );
  }

  Future<void> _openResolvePendingSheet(MovieCatalogDetail detail) async {
    final username = ref.read(authControllerProvider).asData?.value.session?.username;
    if (username == null || username.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isTv
                ? 'You need an active session to link this series.'
                : 'You need an active session to link this movie.',
          ),
        ),
      );
      return;
    }
    final resolvedId = await showCatalogResolvePendingSheet(
      context: context,
      ref: ref,
      kind: widget.isTv ? CatalogResolvePendingKind.tv : CatalogResolvePendingKind.movie,
      pendingMediaId: widget.mediaId,
      username: username,
      initialQuery: detail.media.title,
    );
    if (resolvedId == null || !mounted) {
      return;
    }
    ref.invalidate(
      movieDetailProvider(
        MovieDetailRequest(
          mediaId: widget.mediaId,
          username: username,
          isTv: widget.isTv,
        ),
      ),
    );
    final scope = widget.isTv ? LibraryMediaScope.tv : LibraryMediaScope.movie;
    ref.invalidate(libraryTrackingForScopeProvider(scope));
    if (widget.isTv) {
      ref.invalidate(customTvListsProvider);
      ref.invalidate(tvHomeShelvesProvider(username));
    } else {
      ref.invalidate(customMovieListsProvider);
    }
    ref.invalidate(
      pendingImportsShelfProvider((username: username, scope: scope)),
    );
    context.pushReplacement(widget.isTv ? '/tv/$resolvedId' : '/movies/$resolvedId');
  }

  Future<void> _copyPrimaryLink(MovieCatalogDetail detail) async {
    final primaryUrl = detail.links.isNotEmpty
        ? detail.links.first.url
        : (widget.isTv || detail.media.mediaType == 'tv')
        ? 'https://www.themoviedb.org/tv/${detail.media.externalId}'
        : 'https://www.themoviedb.org/movie/${detail.media.externalId}';
    await Clipboard.setData(ClipboardData(text: primaryUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link copied.')));
  }
}

class _MovieHeroOverlayPinRow extends StatelessWidget {
  const _MovieHeroOverlayPinRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          children[i],
        ],
      ],
    );
  }
}

class _MovieHeroOverlayPinButton extends StatelessWidget {
  const _MovieHeroOverlayPinButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = context.culturTokens.radiusTight;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(r),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
