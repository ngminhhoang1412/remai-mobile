import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../logic/tree.dart';
import '../router.dart';
import '../state/pages.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Home: the page tree with expand/collapse, New page, Search, and a menu with Trash and Sign out.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MenuAction { trash, signOut }

class _HomeScreenState extends State<HomeScreen> {
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: refresh() notifies listeners, which mustn't happen during a build.
    final pages = context.read<PagesState>();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(pages.refresh()));
  }

  Future<void> _newPage() async {
    if (_creating) return;
    setState(() => _creating = true);
    final session = context.read<SessionState>();
    final pages = context.read<PagesState>();
    try {
      final page = await session.api.createPage();
      pages.upsert(page);
      if (mounted) unawaited(context.push(Routes.page(page.id)));
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, 'Couldn’t create page', e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _onMenu(_MenuAction action) {
    switch (action) {
      case _MenuAction.trash:
        unawaited(context.push(Routes.trash));
      case _MenuAction.signOut:
        unawaited(context.read<SessionState>().signOut());
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = context.watch<PagesState>();
    final name = context.select<SessionState, String>((s) => s.user?.name.trim() ?? '');
    final rows = pages.rows;

    Widget body;
    if (pages.loadState == LoadState.error && pages.pages.isEmpty) {
      body = MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn’t load your pages',
        message: pages.error,
        actionLabel: 'Try again',
        onAction: () => unawaited(pages.refresh()),
      );
    } else if (pages.loadState != LoadState.ready && pages.pages.isEmpty) {
      body = const LoadingState();
    } else if (rows.isEmpty) {
      body = const MessageState(
        icon: Icons.note_add_outlined,
        title: 'No pages yet',
        message: 'Tap “New page” to create your first page.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: pages.refresh,
        child: ListView.builder(
          padding: const EdgeInsets.only(top: Space.s2, bottom: 96),
          itemCount: rows.length,
          itemBuilder: (context, i) => _TreeRowTile(
            row: rows[i],
            onOpen: () => unawaited(context.push(Routes.page(rows[i].page.id))),
            onToggle: () => pages.toggleExpanded(rows[i].page.id),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgSidebar,
      appBar: AppBar(
        backgroundColor: AppColors.bgSidebar,
        title: Text(name.isEmpty ? 'remai' : '$name’s remai'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => unawaited(context.push(Routes.search)),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'Menu',
            icon: const Icon(Icons.more_horiz),
            onSelected: _onMenu,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MenuAction.trash,
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Trash')),
              ),
              PopupMenuItem(
                value: _MenuAction.signOut,
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(top: false, child: body),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creating ? null : _newPage,
        icon: const Icon(Icons.add),
        label: const Text('New page'),
      ),
    );
  }
}

class _TreeRowTile extends StatelessWidget {
  const _TreeRowTile({required this.row, required this.onOpen, required this.onToggle});

  final TreeRow row;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('tree-row-${row.page.id}'),
      onTap: onOpen,
      child: Padding(
        padding: EdgeInsets.only(left: Space.s2 + row.depth * 20.0, right: Space.s4),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: row.hasChildren
                    ? IconButton(
                        key: ValueKey('tree-toggle-${row.page.id}'),
                        tooltip: row.expanded ? 'Collapse' : 'Expand',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        color: AppColors.textMuted,
                        icon: Icon(row.expanded ? Icons.expand_more : Icons.chevron_right),
                        onPressed: onToggle,
                      )
                    : null,
              ),
              SizedBox(width: 26, child: Center(child: PageIcon(row.page.icon))),
              const SizedBox(width: Space.s2),
              Expanded(child: PageTitleText(row.page.title)),
            ],
          ),
        ),
      ),
    );
  }
}
