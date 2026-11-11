import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../logic/format.dart';
import '../models/models.dart';
import '../state/pages.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Trash (page-trash "Trash in clients"): Restore, or Delete forever after a confirmation.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<TrashedPage>? _items;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await context.read<SessionState>().api.listTrash();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _restore(TrashedPage item) async {
    setState(() => _busy.add(item.id));
    final api = context.read<SessionState>().api;
    final pages = context.read<PagesState>();
    try {
      await api.restorePage(item.id);
      if (!mounted) return;
      setState(() => _items = _items?.where((p) => p.id != item.id).toList());
      unawaited(pages.refresh()); // the restored subtree reappears in the tree
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored “${displayTitle(item.title)}”')));
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, 'Couldn’t restore', e);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  Future<void> _deleteForever(TrashedPage item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: Text('“${displayTitle(item.title)}” and its subpages will be permanently deleted. '
            'This can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            key: const ValueKey('confirm-delete-forever'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy.add(item.id));
    try {
      await context.read<SessionState>().api.deleteForever(item.id);
      if (mounted) setState(() => _items = _items?.where((p) => p.id != item.id).toList());
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, 'Couldn’t delete', e);
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    final items = _items;
    if (_error != null && items == null) {
      return MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn’t load the trash',
        message: _error,
        actionLabel: 'Try again',
        onAction: () => unawaited(_load()),
      );
    }
    if (items == null) return const LoadingState();
    if (items.isEmpty) {
      return const MessageState(
        icon: Icons.delete_outline,
        title: 'Trash is empty',
        message: 'Pages you move to the trash show up here.',
      );
    }
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, i) {
          final item = items[i];
          final busy = _busy.contains(item.id);
          return Padding(
            key: ValueKey('trash-item-${item.id}'),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, Space.s2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PageIcon(item.icon),
                    const SizedBox(width: Space.s2),
                    Flexible(child: PageTitleText(item.title)),
                    Text(
                      ' · ${relativeTime(item.trashedAt, now)}',
                      style: const TextStyle(fontSize: FontSizes.small, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s1),
                Row(
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => unawaited(_restore(item)),
                      child: const Text('Restore'),
                    ),
                    const SizedBox(width: Space.s2),
                    TextButton(
                      onPressed: busy ? null : () => unawaited(_deleteForever(item)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      child: const Text('Delete forever'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
