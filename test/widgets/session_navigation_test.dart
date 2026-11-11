import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend()
      ..addPage('A', title: 'Project X', icon: '🚀')
      ..addPage('B', title: 'Weekly plan', parentId: 'A')
      ..addPage('C', title: 'Shopping');
  });

  group('Secure session storage', () {
    testWidgets('Sign-in redirect: with no stored token the app opens on the sign-in screen', (tester) async {
      await pumpApp(tester, backend, MemoryTokenStorage());
      expect(find.text('Sign in to your notes'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('Relaunch signed in: a valid stored token opens the page tree without asking to sign in',
        (tester) async {
      await pumpApp(tester, backend, MemoryTokenStorage(validToken));
      expect(find.text('Ada’s remai'), findsOneWidget);
      expect(find.text('Project X'), findsOneWidget);
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('Weekly plan'), findsNothing); // collapsed under Project X
      expect(backend.requestsTo('GET', '/api/v1/auth/me'), hasLength(1));
    });

    testWidgets('Token rejected at launch: the stored token is deleted and sign-in is shown', (tester) async {
      final storage = MemoryTokenStorage('stale-token');
      await pumpApp(tester, backend, storage);
      expect(find.text('Sign in to your notes'), findsOneWidget);
      expect(storage.token, isNull);
    });

    testWidgets('Token rejected: a 401 from any later call deletes the token and shows sign-in', (tester) async {
      final storage = MemoryTokenStorage(validToken);
      await pumpApp(tester, backend, storage);
      expect(find.text('Project X'), findsOneWidget);

      backend.revoked = true;
      await tester.tap(find.text('New page'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to your notes'), findsOneWidget);
      expect(storage.token, isNull);
    });

    testWidgets('Launch while offline shows "Can’t reach remai"; Retry recovers without signing out', (tester) async {
      backend.offline = true;
      final storage = MemoryTokenStorage(validToken);
      await pumpApp(tester, backend, storage);
      expect(find.text('Can’t reach remai'), findsOneWidget);
      expect(storage.token, validToken); // a possibly valid token is kept

      backend.offline = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Project X'), findsOneWidget);
    });

    testWidgets('Launch while offline: Sign out discards the token', (tester) async {
      backend.offline = true;
      final storage = MemoryTokenStorage(validToken);
      await pumpApp(tester, backend, storage);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your notes'), findsOneWidget);
      expect(storage.token, isNull);
    });

    testWidgets('Sign in: wrong credentials show an inline error; correct ones open Home and store the token',
        (tester) async {
      final storage = MemoryTokenStorage();
      await pumpApp(tester, backend, storage);

      await tester.enterText(find.byKey(const ValueKey('auth-email')), 'ada@example.com');
      await tester.enterText(find.byKey(const ValueKey('auth-password')), 'wrong-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('auth-error')), findsOneWidget);
      expect(storage.token, isNull);

      await tester.enterText(find.byKey(const ValueKey('auth-password')), 'correct-horse');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Project X'), findsOneWidget);
      expect(storage.token, validToken);
    });

    testWidgets('Sign out on a client: the token is deleted and sign-in is shown', (tester) async {
      final storage = MemoryTokenStorage(validToken);
      await pumpApp(tester, backend, storage);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to your notes'), findsOneWidget);
      expect(storage.token, isNull);
    });
  });

  group('Navigation model', () {
    testWidgets('Drill into a subpage: expand A, tap child B, and back returns to Home', (tester) async {
      await pumpApp(tester, backend, MemoryTokenStorage(validToken));
      await tester.tap(find.byKey(const ValueKey('tree-toggle-A')));
      await tester.pumpAndSettle();
      expect(find.text('Weekly plan'), findsOneWidget);

      await tester.tap(find.text('Weekly plan'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-title')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('page-title'))).controller!.text, 'Weekly plan');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Ada’s remai'), findsOneWidget);
    });

    testWidgets('Open from search: results appear 300 ms after typing and a result opens the page', (tester) async {
      backend.addPage('R', title: 'Quarterly Roadmap');
      await pumpApp(tester, backend, MemoryTokenStorage(validToken));
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('search-field')), 'road');
      await tester.pump(const Duration(milliseconds: 299));
      expect(backend.requestsTo('GET', '/api/v1/search'), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('GET', '/api/v1/search').single.url.queryParameters['q'], 'road');

      await tester.tap(find.byKey(const ValueKey('search-result-R')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('page-title'))).controller!.text, 'Quarterly Roadmap');
    });

    testWidgets('New page opens an empty page; its title shows as "Untitled" on Home', (tester) async {
      await pumpApp(tester, backend, MemoryTokenStorage(validToken));
      await tester.tap(find.text('New page'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-title')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Untitled'), findsOneWidget);
    });
  });
}
