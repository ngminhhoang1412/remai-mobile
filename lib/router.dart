import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/launch_screen.dart';
import 'screens/page_screen.dart';
import 'screens/search_screen.dart';
import 'screens/trash_screen.dart';
import 'state/session.dart';

abstract final class Routes {
  static const home = '/';
  static const launch = '/launch';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const search = '/search';
  static const trash = '/trash';
  static String page(String id) => '/page/${Uri.encodeComponent(id)}';
}

/// Stack navigation (mobile-client "Navigation model"). The session drives the redirect, so a
/// sign-in, a sign-out or any 401 swaps the whole stack without per-screen code.
GoRouter createRouter(SessionState session) => GoRouter(
      initialLocation: Routes.home,
      refreshListenable: session,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        final onAuth = loc == Routes.signIn || loc == Routes.signUp;
        switch (session.status) {
          case SessionStatus.loading:
          case SessionStatus.unreachable:
            return loc == Routes.launch ? null : Routes.launch;
          case SessionStatus.signedOut:
            return onAuth ? null : Routes.signIn;
          case SessionStatus.signedIn:
            return onAuth || loc == Routes.launch ? Routes.home : null;
        }
      },
      routes: [
        GoRoute(path: Routes.launch, builder: (context, state) => const LaunchScreen()),
        GoRoute(path: Routes.signIn, builder: (context, state) => const AuthScreen(mode: AuthMode.signIn)),
        GoRoute(path: Routes.signUp, builder: (context, state) => const AuthScreen(mode: AuthMode.signUp)),
        GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: Routes.search, builder: (context, state) => const SearchScreen()),
        GoRoute(path: Routes.trash, builder: (context, state) => const TrashScreen()),
        GoRoute(
          path: '/page/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return PageScreen(key: ValueKey('page-$id'), pageId: id);
          },
        ),
      ],
    );
