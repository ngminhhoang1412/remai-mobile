import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'router.dart';
import 'state/pages.dart';
import 'state/session.dart';
import 'theme.dart';

/// Root widget. The session is created by the caller (main.dart, or a test with a fake backend).
class RemaiApp extends StatefulWidget {
  const RemaiApp({super.key, required this.session});

  final SessionState session;

  @override
  State<RemaiApp> createState() => _RemaiAppState();
}

class _RemaiAppState extends State<RemaiApp> {
  late final PagesState _pages = PagesState(widget.session);
  late final GoRouter _router = createRouter(widget.session);

  @override
  void initState() {
    super.initState();
    unawaited(widget.session.checkStoredToken());
  }

  @override
  void dispose() {
    _router.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionState>.value(value: widget.session),
        ChangeNotifierProvider<PagesState>.value(value: _pages),
      ],
      child: MaterialApp.router(
        title: 'remai',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        themeMode: ThemeMode.light,
        routerConfig: _router,
      ),
    );
  }
}
