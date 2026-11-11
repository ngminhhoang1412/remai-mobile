import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session.dart';
import '../widgets/common.dart';

/// Shown while the stored token is checked with GET /auth/me, and when that check couldn't reach
/// the server (the token is kept: it may still be valid).
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      body: SafeArea(
        child: session.status == SessionStatus.unreachable
            ? MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Can’t reach remai',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => unawaited(session.checkStoredToken()),
                secondaryLabel: 'Sign out',
                onSecondary: () => unawaited(session.signOut()),
              )
            : const LoadingState(),
      ),
    );
  }
}
