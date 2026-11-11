import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../router.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Search (page-search "Search from clients"): results as you type, 300 ms after the last keystroke.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  static const debounce = Duration(milliseconds: 300);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  String _searched = '';
  List<SearchResult>? _results;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _seq++;
      setState(() {
        _searched = '';
        _results = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(SearchScreen.debounce, () => unawaited(_run(q)));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await context.read<SessionState>().api.search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _searched = q;
        _results = results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('search-field'),
          controller: _query,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          decoration: const InputDecoration(
            hintText: 'Search pages',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 17, color: AppColors.text),
        ),
        bottom: _loading
            ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return MessageState(icon: Icons.error_outline, title: 'Search failed', message: _error);
    }
    final results = _results;
    if (results == null) {
      return const MessageState(icon: Icons.search, title: 'Search your pages', message: 'Matches titles and text.');
    }
    if (results.isEmpty) {
      return MessageState(icon: Icons.search_off, title: 'No results for “$_searched”');
    }
    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: Space.s4),
      itemBuilder: (context, i) {
        final r = results[i];
        return ListTile(
          key: ValueKey('search-result-${r.id}'),
          leading: SizedBox(width: 28, child: Center(child: PageIcon(r.icon, size: 20))),
          title: PageTitleText(r.title),
          subtitle: r.snippet.isEmpty
              ? null
              : Text(
                  r.snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: FontSizes.small, color: AppColors.textMuted),
                ),
          onTap: () => unawaited(context.push(Routes.page(r.id))),
        );
      },
    );
  }
}
