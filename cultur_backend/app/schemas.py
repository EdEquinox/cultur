from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    username: str
    password: str


class RegisterRequest(BaseModel):
    username: str
    password: str
    displayName: str | None = None


class RefreshRequest(BaseModel):
    refreshToken: str


class ProgressRequest(BaseModel):
    mediaRef: str
    status: str = "In progress"
    progress: int | None = None
    score: float | None = None


class WatchActionRequest(BaseModel):
    mediaRef: str
    action: str


class AuthResponse(BaseModel):
    sessionToken: str
    refreshToken: str
    username: str
    displayName: str | None = None
    sessionExpiresAt: str


class MeResponse(BaseModel):
    username: str
    displayName: str | None = None
    sessionExpiresAt: str


class MediaSummary(BaseModel):
    mediaRef: str
    title: str
    subtitle: str | None = None
    imageUrl: str | None = None
    detailPath: str | None = None
    status: str | None = None
    mediaType: str | None = None
    mediaTypeLabel: str | None = None


class MediaSection(BaseModel):
    title: str
    subtitle: str | None = None
    mediaType: str | None = None
    items: list[MediaSummary]


class DashboardResponse(BaseModel):
    sections: list[MediaSection]
    activePlayback: MediaSummary | None = None


class HistoryResponse(BaseModel):
    sections: list[MediaSection]


class SearchResponse(BaseModel):
    items: list[MediaSummary]
    emptyMessage: str | None = None


class ListSummary(BaseModel):
    title: str
    path: str
    subtitle: str | None = None
    itemsCount: int | None = None


class ListsResponse(BaseModel):
    items: list[ListSummary]


class MediaDetailResponse(BaseModel):
    mediaRef: str
    title: str
    subtitle: str | None = None
    imageUrl: str | None = None
    currentStatus: str | None = None
    source: str | None = None
    mediaType: str | None = None
    mediaId: str | None = None
    canUpdateProgress: bool = False
    facts: list[str] = Field(default_factory=list)
    metadata: dict[str, str] = Field(default_factory=dict)


class ErrorResponse(BaseModel):
    error: str


class SessionRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    sessionId: str
    username: str
    yamtrackBaseUrl: str
    accessTokenHash: str
    refreshTokenHash: str
    accessExpiresAt: str
    refreshExpiresAt: str
    createdAt: str
    updatedAt: str
    encryptedCookies: str
    encryptedCsrfToken: str | None = None
    encryptedPassword: str | None = None
    rememberCredentials: bool = False
    lastReloginAt: str | None = None


class SessionBundle(BaseModel):
    access_token: str
    refresh_token: str
    record: SessionRecord


JsonDict = dict[str, Any]


class BackendBootstrapRequest(BaseModel):
    username: str = "owner"
    displayName: str | None = None


class BackendUserResponse(BaseModel):
    id: str
    username: str
    displayName: str | None = None


class BackendBootstrapResponse(BaseModel):
    status: str
    databaseDialect: str
    user: BackendUserResponse


class BackendPurgeLibraryRequest(BaseModel):
    username: str
    mediaTypes: list[str] = Field(
        default_factory=list,
        description=(
            "Catalog categories to purge: movie, tv, game, boardgame, book, music. "
            "Empty list removes all categories (legacy behaviour)."
        ),
    )


class BackendPurgeLibraryResponse(BaseModel):
    ok: bool = True
    message: str = ""
    trackingRowsRemoved: int = 0
    tvEpisodeWatchRowsRemoved: int = 0
    tvEpisodeUserStateRowsRemoved: int = 0
    tvSeasonUserStateRowsRemoved: int = 0
    collectionsRemoved: int = 0


class AvaBackupImportRequest(BaseModel):
    """Body for `POST /backend/import/ava-backup-v1` (SeriesGuide / `.avabackup` JSON root)."""

    username: str
    backup: dict[str, Any]
    skipExistingTracking: bool = Field(
        default=True,
        description="When true, existing tracking rows are left unchanged (per media item).",
    )


class ImportedBackupListPayload(BaseModel):
    """Serialized curated list for the client to merge into local custom lists."""

    name: str
    items: list["BackendMediaResponse"]


class AvaBackupExportRequest(BaseModel):
    """Body for `POST /backend/export/ava-backup-v1`."""

    username: str


class AvaBackupExportResponse(BaseModel):
    ok: bool = True
    message: str = ""
    backup: dict[str, Any]
    moviesExported: int = 0
    showsExported: int = 0
    episodesExported: int = 0
    seasonsExported: int = 0
    skippedNonTmdb: int = 0


class CulturBackupV3ExportRequest(BaseModel):
    username: str


class CulturBackupV3ExportResponse(BaseModel):
    ok: bool = True
    message: str = ""
    document: dict[str, Any]
    summary: dict[str, Any] = Field(default_factory=dict)


class CulturBackupV3ImportRequest(BaseModel):
    username: str
    document: dict[str, Any]
    skipExistingTracking: bool = Field(
        default=False,
        description="When true, existing tracking rows are left unchanged.",
    )
    importLegacyAva: bool = Field(
        default=True,
        description="When the backup includes legacy.ava (or v2 server.ava), also run AVA import.",
    )


class CulturBackupV3ImportResponse(BaseModel):
    ok: bool = True
    message: str = ""
    summary: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)


class AvaBackupImportResponse(BaseModel):
    ok: bool = True
    message: str = ""
    moviesImported: int = 0
    moviesSkippedTmdb: int = 0
    moviesPending: int = 0
    showsImported: int = 0
    showsSkippedTmdb: int = 0
    showsPending: int = 0
    trackingWritten: int = 0
    trackingSkippedExisting: int = 0
    episodeWatchesWritten: int = 0
    curatedListsDetected: int = 0
    seasonUserStatesWritten: int = 0
    episodeUserStatesWritten: int = 0
    importedListCount: int = 0
    importedListItemCount: int = 0
    importedMovieLists: list[ImportedBackupListPayload] = Field(default_factory=list)
    importedTvLists: list[ImportedBackupListPayload] = Field(default_factory=list)
    importWarnings: list[str] = Field(
        default_factory=list,
        description="Human-readable issues (skipped rows, TMDB misses, invalid episode keys, etc.).",
    )


class BackendHealthResponse(BaseModel):
    service: str
    status: str
    databaseDialect: str
    users: int
    mediaItems: int
    trackingEntries: int


class BackendMediaUpsertRequest(BaseModel):
    source: str = "manual"
    externalId: str
    mediaType: str
    title: str
    subtitle: str | None = None
    description: str | None = None
    imageUrl: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class BackendMediaResponse(BaseModel):
    id: str
    source: str
    externalId: str
    mediaType: str
    title: str
    subtitle: str | None = None
    description: str | None = None
    imageUrl: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class BackendMediaListResponse(BaseModel):
    items: list[BackendMediaResponse]


class MovieHomeShelfResponse(BaseModel):
    """Single response for catalog home movie rails (one client round-trip)."""

    nowPlaying: BackendMediaListResponse
    upcoming: BackendMediaListResponse


class MusicHomeResponse(BaseModel):
    """Albums home: Last.fm popular tag shelf + user's latest rated albums."""

    popular: BackendMediaListResponse
    latest: BackendMediaListResponse


class MusicReleaseVersionItem(BaseModel):
    discogsReleaseId: str
    title: str
    format: str | None = None
    country: str | None = None
    released: str | None = None
    label: str | None = None
    thumbUrl: str | None = None
    catno: str | None = None


class MusicReleaseVersionsResponse(BaseModel):
    items: list[MusicReleaseVersionItem] = Field(default_factory=list)


class FollowedArtistPayload(BaseModel):
    username: str
    discogsArtistId: str
    name: str | None = None
    imageUrl: str | None = None


class FollowedArtistResponse(BaseModel):
    id: str
    discogsArtistId: str
    name: str
    imageUrl: str | None = None


class FollowedArtistsListResponse(BaseModel):
    items: list[FollowedArtistResponse] = Field(default_factory=list)


class UserFollowPayload(BaseModel):
    username: str
    entityKind: str = Field(
        description="person | music_artist | company | publisher",
    )
    personId: str | None = None
    sourceCode: str | None = None
    externalId: str | None = None
    name: str | None = None
    imageUrl: str | None = None


class UserFollowResponse(BaseModel):
    id: str
    personId: str
    entityKind: str
    name: str
    imageUrl: str | None = None
    sourceCode: str | None = None
    externalId: str | None = None


class UserFollowListResponse(BaseModel):
    items: list[UserFollowResponse] = Field(default_factory=list)


class CollectionResponse(BaseModel):
    id: str
    name: str
    createdAt: str
    isBuiltIn: bool = False
    mediaType: str
    items: list[dict[str, Any]] = Field(default_factory=list)


class CollectionListResponse(BaseModel):
    lists: list[CollectionResponse] = Field(default_factory=list)


class CollectionCreateRequest(BaseModel):
    username: str
    mediaType: str
    name: str


class CollectionRenameRequest(BaseModel):
    username: str
    name: str


class CollectionToggleItemRequest(BaseModel):
    username: str
    mediaId: str | None = None
    catalogItemId: str | None = None
    seasonNumber: int | None = None
    episodeNumber: int | None = None


class CollectionSyncListPayload(BaseModel):
    id: str
    name: str
    createdAt: str | None = None
    items: list[dict[str, Any]] = Field(default_factory=list)


class CollectionBulkSyncRequest(BaseModel):
    username: str
    mediaType: str
    lists: list[CollectionSyncListPayload] = Field(default_factory=list)


class TvLibraryHomeResponse(BaseModel):
    """Series home: catch-up after marking watched + upcoming episode air dates."""

    nextUp: BackendMediaListResponse
    upcomingEpisodes: BackendMediaListResponse


class StashGameEventResponse(BaseModel):
    slug: str
    title: str
    startsAt: str
    description: str | None = None
    imageUrl: str | None = None
    stashUrl: str


class StashGameEventsListResponse(BaseModel):
    window: str
    items: list[StashGameEventResponse] = Field(default_factory=list)


class StashEventGameItemResponse(BaseModel):
    slug: str
    title: str
    imageUrl: str | None = None
    releaseLabel: str | None = None
    stashUrl: str
    mediaId: str | None = None


class StashGameEventDetailResponse(BaseModel):
    slug: str
    title: str
    startsAt: str
    description: str | None = None
    imageUrl: str | None = None
    stashUrl: str
    items: list[StashEventGameItemResponse] = Field(default_factory=list)


class MovieDetailMetric(BaseModel):
    label: str
    value: str


class MovieDetailPerson(BaseModel):
    personId: str | None = None
    name: str
    role: str | None = None
    imageUrl: str | None = None


class MovieDetailCrewGroup(BaseModel):
    title: str
    people: list[MovieDetailPerson]


class MovieDetailVideo(BaseModel):
    title: str
    subtitle: str | None = None
    imageUrl: str | None = None
    url: str | None = None


class MovieDetailLink(BaseModel):
    label: str
    url: str


class WatchedEpisodeResponse(BaseModel):
    seasonNumber: int
    episodeNumber: int
    watchedAt: str | None = None
    userRating: float | None = None
    userRatingRatedAt: str | None = None
    userWatchlist: bool | None = None
    userWatchlistedAt: str | None = None


class TvNextEpisodeCardResponse(BaseModel):
    seasonNumber: int
    episodeNumber: int
    name: str | None = None
    airDate: str | None = None
    stillUrl: str | None = None
    runtimeMinutes: int | None = None


class TvSeasonSummaryResponse(BaseModel):
    seasonNumber: int
    name: str
    episodeCount: int
    airDate: str | None = None
    overview: str | None = None
    posterUrl: str | None = None


class TvSeasonListResponse(BaseModel):
    items: list[TvSeasonSummaryResponse]


class TvEpisodeCatalogResponse(BaseModel):
    episodeNumber: int
    name: str
    overview: str | None = None
    airDate: str | None = None
    stillUrl: str | None = None
    runtimeMinutes: int | None = None
    voteAverage: float | None = None
    guestStars: list[MovieDetailPerson] = Field(default_factory=list)
    userRating: float | None = None
    userRatingRatedAt: str | None = None
    userWatchlist: bool | None = None
    userWatchlistedAt: str | None = None


class TvSeasonDetailResponse(BaseModel):
    seasonNumber: int
    name: str
    overview: str | None = None
    airDate: str | None = None
    posterUrl: str | None = None
    episodes: list[TvEpisodeCatalogResponse] = Field(default_factory=list)
    watchedEpisodes: list[WatchedEpisodeResponse] = Field(default_factory=list)
    cast: list[MovieDetailPerson] = Field(default_factory=list)
    ratings: list[MovieDetailMetric] = Field(default_factory=list)
    directors: list[MovieDetailPerson] = Field(default_factory=list)
    userSeasonRating: float | None = None
    userSeasonRatingRatedAt: str | None = None
    userSeasonWatchlist: bool | None = None
    userSeasonWatchlistedAt: str | None = None


class TvEpisodeDetailResponse(BaseModel):
    seasonNumber: int
    episodeNumber: int
    name: str
    overview: str | None = None
    airDate: str | None = None
    stillUrl: str | None = None
    runtimeMinutes: int | None = None
    voteAverage: float | None = None
    cast: list[MovieDetailPerson] = Field(default_factory=list)
    guestStars: list[MovieDetailPerson] = Field(default_factory=list)
    ratings: list[MovieDetailMetric] = Field(default_factory=list)
    directors: list[MovieDetailPerson] = Field(default_factory=list)
    watchedAt: str | None = None
    userRating: float | None = None
    userRatingRatedAt: str | None = None
    userWatchlist: bool | None = None
    userWatchlistedAt: str | None = None


class TvEpisodeWatchListResponse(BaseModel):
    items: list[WatchedEpisodeResponse]


class WatchedTvEpisodeLibraryItem(BaseModel):
    """One TV episode marked watched for the cross-show library Watched list."""

    media: BackendMediaResponse
    seasonNumber: int
    episodeNumber: int
    watchedAt: str


class WatchedTvEpisodeLibraryListResponse(BaseModel):
    items: list[WatchedTvEpisodeLibraryItem]


class TvEpisodeWatchPutRequest(BaseModel):
    username: str
    mediaId: str
    seasonNumber: int
    episodeNumber: int
    watched: bool = True
    watchedAt: str | None = None
    userRating: float | None = None
    userRatingRatedAt: str | None = None
    userWatchlist: bool | None = None
    userWatchlistedAt: str | None = None


class TvEpisodeWatchPutResponse(BaseModel):
    seasonNumber: int
    episodeNumber: int
    watched: bool
    watchedAt: str | None = None


class TvEpisodeWatchMarkThroughRequest(BaseModel):
    username: str
    mediaId: str
    throughSeasonNumber: int
    throughEpisodeNumber: int
    watchedAt: str | None = None
    onlySeasonNumber: int | None = Field(
        default=None,
        description="When set, only episodes in this season are updated (no other seasons touched).",
    )


class TvEpisodeWatchMarkThroughResponse(BaseModel):
    markedCount: int
    throughSeasonNumber: int
    throughEpisodeNumber: int


class TvEpisodeWatchClearSeasonRequest(BaseModel):
    username: str
    mediaId: str
    seasonNumber: int


class TvEpisodeWatchClearSeasonResponse(BaseModel):
    removedCount: int


class GameCompanyRef(BaseModel):
    companyId: str
    name: str


class BookEditFieldInfo(BaseModel):
    key: str
    label: str
    multiline: bool = False
    currentValue: str = ""
    source: str = "current"


class BookEditFieldsResponse(BaseModel):
    mediaId: str
    fields: list[BookEditFieldInfo]


class BookFieldOption(BaseModel):
    provider: str
    label: str
    displayValue: str
    value: Any | None = None
    metadataPatch: dict[str, Any] | None = None


class BookFieldOptionsResponse(BaseModel):
    field: str
    label: str
    multiline: bool = False
    currentValue: str = ""
    options: list[BookFieldOption] = Field(default_factory=list)


class BookEditPatchRequest(BaseModel):
    fields: dict[str, Any] = Field(default_factory=dict)
    fieldSources: dict[str, str] | None = None
    metadataPatches: list[dict[str, Any]] = Field(default_factory=list)
    lookupSource: str | None = None
    lookupExternalId: str | None = None


class BookEditSearchHit(BaseModel):
    source: str
    externalId: str
    title: str
    subtitle: str | None = None
    authors: str | None = None
    isbn: str | None = None
    imageUrl: str | None = None


class BookEditSearchResponse(BaseModel):
    query: str
    results: list[BookEditSearchHit] = Field(default_factory=list)


class BookPublisherRef(BaseModel):
    publisherId: str
    name: str


class GameTimeToBeat(BaseModel):
    main: str | None = None
    extras: str | None = None
    completion: str | None = None


class GameFranchiseRef(BaseModel):
    franchiseId: str
    name: str
    slug: str | None = None
    seriesKind: str | None = None


class GameCollectionRef(BaseModel):
    collectionId: str
    name: str
    slug: str | None = None


class IgdbFilterOptionResponse(BaseModel):
    id: str
    name: str


class GameCatalogFiltersResponse(BaseModel):
    platforms: list[IgdbFilterOptionResponse] = Field(default_factory=list)
    genres: list[IgdbFilterOptionResponse] = Field(default_factory=list)
    gameModes: list[IgdbFilterOptionResponse] = Field(default_factory=list)
    playerPerspectives: list[IgdbFilterOptionResponse] = Field(default_factory=list)
    gameTypes: list[IgdbFilterOptionResponse] = Field(default_factory=list)


class MovieCatalogDetailResponse(BaseModel):
    media: BackendMediaResponse
    overview: str | None = None
    backdropUrl: str | None = None
    galleryUrls: list[str] = Field(default_factory=list)
    genres: list[str] = Field(default_factory=list)
    keywords: list[str] = Field(default_factory=list)
    ratings: list[MovieDetailMetric] = Field(default_factory=list)
    facts: list[MovieDetailMetric] = Field(default_factory=list)
    cast: list[MovieDetailPerson] = Field(default_factory=list)
    crew: list[MovieDetailCrewGroup] = Field(default_factory=list)
    videos: list[MovieDetailVideo] = Field(default_factory=list)
    recommendations: list[BackendMediaResponse] = Field(default_factory=list)
    links: list[MovieDetailLink] = Field(default_factory=list)
    gamePublishers: list[GameCompanyRef] = Field(default_factory=list)
    gameDevelopers: list[GameCompanyRef] = Field(default_factory=list)
    bookPublishers: list[BookPublisherRef] = Field(default_factory=list)
    gameTimeToBeat: GameTimeToBeat | None = None
    gameFranchise: GameFranchiseRef | None = None
    gameCollections: list[GameCollectionRef] = Field(default_factory=list)
    gameType: str | None = None
    gameModes: list[str] = Field(default_factory=list)
    playerPerspectives: list[str] = Field(default_factory=list)
    tracking: BackendTrackingResponse | None = None
    watchedEpisodes: list[WatchedEpisodeResponse] = Field(default_factory=list)
    nextEpisodeCard: TvNextEpisodeCardResponse | None = None
    catalogPending: bool = False
    importSource: str | None = None


class PersonFilmographyItem(BaseModel):
    media: BackendMediaResponse
    role: str | None = None
    mediaType: str = "movie"
    creditKind: str = "cast"
    department: str | None = None
    genreIds: list[int] = Field(default_factory=list)
    genreNames: list[str] = Field(default_factory=list)
    voteAverage: float | None = None
    episodeCount: int | None = None


class GameCompanyCatalogItem(BaseModel):
    media: BackendMediaResponse
    roles: list[str] = Field(default_factory=list)


class GameCompanyCatalogDetailResponse(BaseModel):
    companyId: str
    name: str
    description: str | None = None
    primaryRole: str | None = None
    imageUrl: str | None = None
    catalog: list[GameCompanyCatalogItem] = Field(default_factory=list)
    popularCatalog: list[GameCompanyCatalogItem] = Field(default_factory=list)
    links: list[MovieDetailLink] = Field(default_factory=list)


class PersonCatalogDetailResponse(BaseModel):
    personId: str
    name: str
    biography: str | None = None
    knownForDepartment: str | None = None
    imageUrl: str | None = None
    gender: str | None = None
    birthday: str | None = None
    placeOfBirth: str | None = None
    filmography: list[PersonFilmographyItem] = Field(default_factory=list)
    popularFilmography: list[PersonFilmographyItem] = Field(default_factory=list)
    links: list[MovieDetailLink] = Field(default_factory=list)


class BookmoryImportEntryPayload(BaseModel):
    sourceFile: str
    title: str
    authors: str | None = None
    isbn: str | None = None
    status: str = "To read"
    wishlist: bool = False
    score: float | None = None
    completedAt: str | None = None
    startedAt: str | None = None
    droppedAt: str | None = None
    collected: bool = False
    collectedPrice: str | None = None
    lentBorrower: str | None = None
    lentAt: str | None = None


class BookmoryImportBatchRequest(BaseModel):
    username: str
    entries: list[BookmoryImportEntryPayload]


class BookmoryImportItemError(BaseModel):
    sourceFile: str
    title: str
    reason: str
    message: str


class BookmoryImportBatchResponse(BaseModel):
    imported: int
    pending: int = 0
    skipped: int
    errors: list[BookmoryImportItemError] = Field(default_factory=list)


class HardcoverListSummaryResponse(BaseModel):
    listId: int
    name: str
    booksCount: int
    description: str | None = None
    public: bool = True


class HardcoverImportSourceResponse(BaseModel):
    sourceKey: str
    kind: str
    name: str
    booksCount: int
    description: str | None = None
    public: bool | None = None
    defaultCulturTarget: str


class HardcoverImportPreviewResponse(BaseModel):
    hardcoverUserId: int
    hardcoverUsername: str
    sources: list[HardcoverImportSourceResponse] = Field(default_factory=list)
    lists: list[HardcoverListSummaryResponse] = Field(default_factory=list)


class HardcoverImportMappingPayload(BaseModel):
    sourceKey: str
    culturTarget: str


class HardcoverImportBatchRequest(BaseModel):
    username: str
    hardcoverUsername: str
    mappings: list[HardcoverImportMappingPayload] = Field(default_factory=list)
    listIds: list[int] = Field(default_factory=list)


class HardcoverCustomListAssignment(BaseModel):
    listName: str
    mediaId: str
    title: str
    source: str = "hardcover"
    externalId: str = ""


class HardcoverImportBatchResponse(BaseModel):
    imported: int
    pending: int = 0
    skipped: int
    errors: list[BookmoryImportItemError] = Field(default_factory=list)
    customListAssignments: list[HardcoverCustomListAssignment] = Field(default_factory=list)


class StashImportEntryPayload(BaseModel):
    sourceFile: str
    title: str
    imageUrl: str | None = None
    artist: str | None = None
    flags: list[str] = Field(default_factory=list)
    score: float | None = None
    review: str | None = None
    completedAt: str | None = None


class StashImportBatchRequest(BaseModel):
    username: str
    entries: list[StashImportEntryPayload]


class StashCollectionPathPayload(BaseModel):
    key: str
    path: str


class StashProfileImportRequest(BaseModel):
    username: str
    stashUsername: str
    collectionPaths: list[StashCollectionPathPayload] = Field(default_factory=list)
    includeReviews: bool = True
    includeLibraryTabs: bool = True


class MusicboardListPathPayload(BaseModel):
    key: str
    path: str
    sourceFile: str | None = None


class MusicboardImportSourceResponse(BaseModel):
    sourceKey: str
    kind: str
    name: str
    path: str
    defaultCulturTarget: str


class MusicboardImportPreviewResponse(BaseModel):
    musicboardUsername: str
    sources: list[MusicboardImportSourceResponse] = Field(default_factory=list)


class MusicboardImportMappingPayload(BaseModel):
    sourceKey: str
    culturTarget: str


class MusicboardCustomListAssignment(BaseModel):
    listName: str
    mediaId: str
    title: str
    source: str = "discogs"
    externalId: str = ""


class MusicboardImportBatchResponse(BaseModel):
    imported: int
    pending: int = 0
    skipped: int
    errors: list[StashImportItemError] = Field(default_factory=list)
    customListAssignments: list[MusicboardCustomListAssignment] = Field(default_factory=list)


class MusicboardProfileImportRequest(BaseModel):
    username: str
    musicboardUsername: str
    listPaths: list[MusicboardListPathPayload] = Field(default_factory=list)
    mappings: list[MusicboardImportMappingPayload] = Field(default_factory=list)
    includeWantlist: bool = True
    includeAlbums: bool = True
    includeReviews: bool = True
    includeHistory: bool = True


class StashImportItemError(BaseModel):
    sourceFile: str
    title: str
    reason: str
    message: str


class StashImportBatchResponse(BaseModel):
    imported: int
    pending: int = 0
    skipped: int
    errors: list[StashImportItemError] = Field(default_factory=list)


class ResolvePendingCatalogRequest(BaseModel):
    username: str
    pendingMediaId: str
    igdbExternalId: str | None = None
    tmdbId: str | None = None
    resolvedMediaId: str | None = None
    resolvedSource: str | None = None
    resolvedExternalId: str | None = None


class ApplyBookCatalogLookupRequest(BaseModel):
    username: str
    source: str
    externalId: str
    isbn: str | None = None
    title: str | None = None
    authors: str | None = None


class ApplyBookCatalogLookupResponse(BaseModel):
    mediaId: str


class ResolvePendingCatalogResponse(BaseModel):
    pendingMediaId: str
    resolvedMediaId: str
    resolvedExternalId: str


class CreateManualLibraryItemRequest(BaseModel):
    username: str
    mediaType: str
    title: str
    subtitle: str | None = None
    description: str | None = None
    imageUrl: str | None = None


class CreateManualLibraryItemResponse(BaseModel):
    mediaId: str


class BggCollectionImportRequest(BaseModel):
    username: str
    bggUsername: str


class BggCollectionImportResponse(BaseModel):
    imported: int
    skipped: int
    total: int = 0


class BackendTrackingUpsertRequest(BaseModel):
    username: str
    mediaId: str
    status: str = "In progress"
    progress: int | None = None
    score: float | None = None
    notes: str | None = None
    completedAt: str | None = None
    startedAt: str | None = None
    droppedAt: str | None = None
    collectedAt: str | None = None


class BackendTrackingResponse(BaseModel):
    id: str
    username: str
    media: BackendMediaResponse
    status: str
    progress: int | None = None
    score: float | None = None
    notes: str | None = None
    completedAt: str | None = None
    startedAt: str | None = None
    droppedAt: str | None = None
    collectedAt: str | None = None
    createdAt: str | None = None
    updatedAt: str | None = None
    episodeWatchedCount: int = Field(
        default=0,
        description="For TV media: number of episode watch rows (library watched tab).",
    )
    tvFullyWatched: bool = Field(
        default=False,
        description="For TV: every aired episode (all seasons) is marked watched.",
    )
    tvAiredEpisodeTotal: int | None = Field(
        default=None,
        description="For TV: aired episode count when progress was last computed.",
    )


class BackendTrackingListResponse(BaseModel):
    items: list[BackendTrackingResponse]
