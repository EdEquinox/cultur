library;

import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/media/books/book_detail/book_detail_page.dart';
import 'package:yamtrack/src/screens/media/books/book_edit/book_edit_page.dart';
import 'package:yamtrack/src/screens/media/books/publisher_detail/book_publisher_detail_page.dart';
import 'package:yamtrack/src/screens/media/books/series_detail/book_series_detail_page.dart';

import '../page_transitions.dart';

List<GoRoute> buildBookRoutes() {
  return [
    GoRoute(
      path: '/books/series/:seriesId',
      pageBuilder: (context, state) {
        final seriesId = Uri.decodeComponent(
          state.pathParameters['seriesId'] ?? '',
        );
        final name = state.uri.queryParameters['name'];
        return buildAppRouteTransitionPage(
          state: state,
          child: BookSeriesDetailPage(
            seriesId: seriesId,
            initialName: name,
          ),
        );
      },
    ),
    GoRoute(
      path: '/books/publishers/:publisherId',
      pageBuilder: (context, state) {
        final publisherId = Uri.decodeComponent(
          state.pathParameters['publisherId'] ?? '',
        );
        final name = state.uri.queryParameters['name'];
        return buildAppRouteTransitionPage(
          state: state,
          child: BookPublisherDetailPage(
            publisherId: publisherId,
            initialName: name,
          ),
        );
      },
    ),
    GoRoute(
      path: '/books/:mediaId/edit',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: BookEditPage(mediaId: mediaId),
        );
      },
    ),
    GoRoute(
      path: '/books/:mediaId',
      pageBuilder: (context, state) {
        final mediaId = state.pathParameters['mediaId'] ?? '';
        return buildAppRouteTransitionPage(
          state: state,
          child: BookDetailPage(mediaId: mediaId),
        );
      },
    ),
  ];
}
