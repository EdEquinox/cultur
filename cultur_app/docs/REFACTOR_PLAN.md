# Yamtrack Flutter — plano de refatoração (pausado)

**Estado:** app funcional; `dart analyze lib` limpo.  
**Fase A:** widgets de **browse** em `lib/src/widgets/cards/` — base feita (2026-05-18).  
**Continue watching:** manter UI atual de TV; unificar mais tarde (ver secção abaixo).

Quando voltares, diz ao agente: *“continua o plano em `docs/REFACTOR_PLAN.md`”*.

---

## Já feito

| Área | Notas |
|------|--------|
| **Models** | `lib/src/models/{auth,catalog,movie,lists,library,tracking,tv,person}/` — sem shims em `exports/` |
| **Providers** | Por domínio em `lib/src/providers/` (tracking, catalog, library, person, TV season, movie detail, etc.) |
| **Controllers** | `auth`, `tracking_controller`, `custom_lists_controller`, `tv_custom_lists_controller` |
| **Core** | API, sessão, `ApiException`, `StorageKeys` |
| **Theme** | `CulturPalette`, tokens, temas de componentes |
| **Buy tab** | Coleção “buy” alinhada com Later |

---

## Próximo passo (após design dos cards)

### Fase A — Cards partilhados ✅ base

**Implementado** em `lib/src/widgets/cards/`:

| Ficheiro | Papel |
|----------|--------|
| `cultur_media_card_content.dart` | Dados normalizados + factories `fromCatalog` / `fromTracking` |
| `cultur_poster_image.dart` | Poster + placeholder por `mediaType` |
| `cultur_poster_size.dart` | Presets xs/sm/md/lg |
| `cultur_card_shell.dart` | Card + InkWell + padding |
| `cultur_list_row_card.dart` | Lista detailed/compact |
| `cultur_grid_tile.dart` | Grelha flat / elevated |
| `cultur_poster_card.dart` | Poster wall |

**Já delegam** para estes widgets: `library_*_card`, `catalog_movie_tile`, `compact_movie_tile`, `movie_grid_card`, `poster_wall_card`, `library_poster_thumb`, `movie_poster_thumb`.  
**Corrigido:** `library_tracking_layout` usa `LibraryGridCard` / `LibraryPosterCard` em grid e posters.

**Ainda por migrar** (Fase A cont.): home shelves (`next_to_watch_poster_card`, `latest_release_card`, …), TV/history cards, `NextToWatchPosterCard` com `imageOverlay`.

**Widgets legados** (em `screens/widgets/` e `screens/library/widgets/`):

- Posters: `poster_wall_card`, `library_poster_card`, `movie_poster_thumb`, `library_poster_thumb`, `compact_movie_tile`, `catalog_movie_tile`, `result_movie_tile`, `movie_grid_card`
- Biblioteca: `library_detailed_card`, `library_compact_card`, `library_grid_card`, `library_watched_style_catalog_row`
- TV: `tv_next_episode_card`, cards em `watched_tv_*`, `tv_custom_list_*`
- Home: `next_to_watch_poster_card`, `latest_release_card`, `upcoming_*`

**Sugestão de destino no código** (ajustar ao design final):

```
lib/src/widgets/cards/     # ou screens/shared/cards/
  cultur_poster_card.dart
  cultur_list_row_card.dart
  cultur_grid_tile.dart
  ...
```

Definir no design: variantes (compact / detailed / grid / poster wall), slots (rating, badge, progresso episódio, ações rápidas), e props por `LibraryMediaScope` / filme vs série.

---

## Cards “Continue” / em progresso (visão de produto)

Família **separada** dos cards de browse (`CulturListRowCard`, etc.): interativos, com progresso e ações inline.

| Media | Estado hoje | Ações desejadas (futuro) |
|-------|-------------|---------------------------|
| **TV** (`mediaType: tv`) | ✅ `TvNextUpEpisodeRow` (home), `TvNextEpisodeCard` (detalhe série) | Marcar episódio visto (+ data); abrir episódio; barra de progresso real (hoje placeholder `0.2`) |
| **Livros** | ❌ | Atualizar páginas lidas / %; capa + título + autor |
| **Jogos** | ❌ | Completado, rating, pausado, dropado |

**Decisão (2026-05-18):** não redesenhar agora — continuar com os widgets TV existentes até haver backend/modelos para livros/jogos.

### Widgets atuais (TV)

| Widget | Onde | Notas |
|--------|------|--------|
| `TvNextUpEpisodeRow` | `home/widgets/tv_next_up_section.dart` | Shelf horizontal “Next up”; mark watched via `episodeWatchMutationController` |
| `TvNextEpisodeCard` | `series_detail`, nested sections | Still 16:9 + toggle watched |
| `NextToWatchPosterCard` | home filmes/TV listas | Poster + badges Priority/Cinema — **não** é continue episódio |

Providers: `tvNextToWatchShelfProvider`, shelves em `catalog_shelf_providers.dart` (`catalogContinueWatchingSortedNewestFirst`).

### Direção técnica (quando implementar multi-media)

1. **Modelo** `CulturInProgressCardContent` + `InProgressMediaKind { tvEpisode, book, game }` com progresso tipado:
   - TV: `season`, `episode`, `watched`
   - Livro: `pageCurrent`, `pageTotal`
   - Jogo: `status` (playing \| paused \| completed \| dropped), `score?`
2. **Widget** `CulturInProgressCard` em `lib/src/widgets/cards/`:
   - layout comum: thumb + 3 linhas texto + barra progresso + **primary action** (slot)
   - **secondary actions** por kind (menu ou ícones: pause/drop/rate/páginas)
3. **Controllers** por domínio (como `episodeWatchMutationController` hoje), não lógica API dentro do card
4. **Backend** `mediaType` + metadata/progress no tracking — alinhar com `CatalogItem.mediaType`

Ordem sugerida: (1) unificar os dois widgets TV num `CulturInProgressCard` kind=tvEpisode; (2) barra progresso real; (3) livros; (4) jogos.

### Fase B — Desacoplamento rápido ✅ (2026-05-18)

1. **Enums** → `models/library/library_enums.dart` (`LibraryCollectionKind`, `LibraryFilterSurface`, `LibraryViewMode`, `collectionPathSegment`)
2. **UI extensões** → `screens/library/library_view_mode_ui.dart` (`LibraryViewModeUi`)
3. **Navegação TV** → `screens/library/library_navigation.dart` (`openTvCustomListItem`)
4. **`LibraryTrackingFilterModel`** importa só `models/`
5. **Barrels removidos:** `custom_lists_storage.dart`, `built_in_movie_lists.dart`, `favorite_people_storage.dart` (já não eram usados)
6. `library_pages.dart` removido (substituído pelos três ficheiros acima)
7. Pasta `screens/tracking/` — já não existia

### Fase C — Organização de screens (médio esforço)

```
screens/
  auth/
  home/
  library/          # páginas + widgets/library/
  collections/
  lists/
  profile/
  person/
  media/movies/
  media/shows/
  shared/           # ErrorState, EmptyState, sheets genéricos
```

- Partir `tracking_collection_page.dart` (~987 linhas): filtros, sort, corpo TV vs filme → widgets/helpers
- Migrar imports relativos TV → `package:yamtrack/...`
- Depois de Fase A: esvaziar `screens/widgets/` antigo ou deixar só o que não for card

### Fase D — Polimento opcional

- `utils/collection_filters.dart` — grande; avaliar mover lógica de sheet para `screens/library/` ou módulo `library/filters/`
- `UserMovieTrackingDigest` → `models/person/` (hoje em `person_providers.dart`)
- Unificar chamadas `/backend/tracking` (limites 200 / 500 / 2000) se quiseres menos duplicação de fetch
- Testes widget/integration para cards e biblioteca
- `search_provider`: sair de `flutter_riverpod/legacy.dart` quando conveniente

---

## O que **não** bloqueia

- Backend `cultur_backend/` — pacote separado
- Commits/MRs — só quando pedires

---

## Referências úteis

- Tracking UI: `lib/src/screens/collections/tracking_collection_page.dart`
- Filtros: `lib/src/models/library/library_tracking_filter_model.dart`, `lib/src/utils/collection_filters.dart`
- Providers tracking: `lib/src/providers/library_tracking_providers.dart`, `tracking_providers.dart`
- Tema: `lib/src/app/theme.dart`
