/// Local persistence keys for [SessionStorage].
///
/// Auth keys are global. List and favorite keys are per [username].
abstract final class StorageKeys {
  StorageKeys._();

  // --- Auth (session) ---

  static const serverApiBaseUrl = 'server_api_base_url';
  static const sessionToken = 'session_token';
  static const refreshToken = 'refresh_token';
  static const username = 'username';
  static const displayName = 'display_name';

  // --- UI preferences (device-local) ---

  static const appAccentColor = 'app_accent_color';
  static const movieSearchGridColumns = 'movie_search_grid_columns';
  static const movieSearchViewMode = 'movie_search_view_mode';
  static const gameSearchViewMode = 'game_search_view_mode';
  static const bookSearchViewMode = 'book_search_view_mode';
  static const tvSearchViewMode = 'tv_search_view_mode';

  // --- User-scoped data ---

  static const customMovieListsPrefix = 'custom_movie_lists';
  static const customTvListsPrefix = 'custom_tv_lists';
  static const customGameListsPrefix = 'custom_game_lists';
  static const customBoardgameListsPrefix = 'custom_boardgame_lists';
  static const customBookListsPrefix = 'custom_book_lists';
  static const customMusicListsPrefix = 'custom_music_lists';
  static const bggUsernamePrefix = 'bgg_username';
  static const favoritePeoplePrefix = 'favorite_people';
  static const favoriteCompaniesPrefix = 'favorite_companies';
  static const favoritePublishersPrefix = 'favorite_publishers';

  static String customMovieLists(String username) =>
      '$customMovieListsPrefix:$username';

  static String customTvLists(String username) => '$customTvListsPrefix:$username';

  static String customGameLists(String username) => '$customGameListsPrefix:$username';

  static String customBoardgameLists(String username) =>
      '$customBoardgameListsPrefix:$username';

  static String customBookLists(String username) => '$customBookListsPrefix:$username';

  static String customMusicLists(String username) => '$customMusicListsPrefix:$username';

  static String bggUsername(String username) => '$bggUsernamePrefix:$username';

  static String favoritePeople(String username) => '$favoritePeoplePrefix:$username';

  static String favoriteCompanies(String username) =>
      '$favoriteCompaniesPrefix:$username';

  static String favoritePublishers(String username) =>
      '$favoritePublishersPrefix:$username';
}
