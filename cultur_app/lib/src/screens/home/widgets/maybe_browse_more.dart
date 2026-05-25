import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/screens/home/home_shelf_list_page.dart';

Widget maybeBrowseMore(
  BuildContext context, {
  required String scope,
  required int itemCount,
  required Widget child,
}) {
  if (itemCount < HomeShelfListPage.backendShelfCap) {
    return child;
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(child: child),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: OutlinedButton(
          onPressed: () {
            if (scope == 'tv') {
              context.push('/category/series?section=on_the_air');
            } else {
              context.push('/category/movies?section=upcoming');
            }
          },
          child: const Text('Browse more in catalog'),
        ),
      ),
    ],
  );
}
