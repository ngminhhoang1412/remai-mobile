import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../logic/tree.dart';
import '../models/models.dart';
import 'session.dart';

enum LoadState { idle, loading, ready, error }

/// Page-list cache shared by Home and the Page screen, so renames show up without a refetch.
class PagesState extends ChangeNotifier {
  PagesState(this._session) {
    _session.addListener(_onSession);
  }

  final SessionState _session;

  List<PageInfo> _pages = const [];
  LoadState _loadState = LoadState.idle;
  String? _error;
  Set<String> _expanded = {};
  int _requestSeq = 0;
  bool _disposed = false;

  List<PageInfo> get pages => _pages;
  LoadState get loadState => _loadState;
  String? get error => _error;
  Set<String> get expanded => _expanded;

  List<TreeRow> get rows => flattenVisible(buildTree(_pages), _expanded);

  PageInfo? byId(String id) {
    for (final p in _pages) {
      if (p.id == id) return p;
    }
    return null;
  }

  // Clear the cache on sign-out so the next account never sees the previous user's tree.
  void _onSession() {
    if (_session.status != SessionStatus.signedOut || (_pages.isEmpty && _loadState == LoadState.idle)) return;
    _requestSeq++;
    _pages = const [];
    _loadState = LoadState.idle;
    _error = null;
    _expanded = {};
    _notify();
  }

  Future<void> refresh() async {
    final seq = ++_requestSeq;
    if (_loadState != LoadState.ready) {
      _loadState = LoadState.loading;
      _notify();
    }
    try {
      final list = await _session.api.listPages();
      if (seq != _requestSeq) return;
      _pages = list;
      _error = null;
      _loadState = LoadState.ready;
    } on ApiException catch (e) {
      if (seq != _requestSeq) return;
      _error = e.message;
      if (_loadState != LoadState.ready) _loadState = LoadState.error;
    }
    _notify();
  }

  /// Insert or replace a page (after create / open / restore).
  void upsert(PageInfo page) {
    final i = _pages.indexWhere((p) => p.id == page.id);
    _pages = i == -1 ? [..._pages, page] : ([..._pages]..[i] = page);
    _notify();
  }

  /// Live title/icon edits from the Page screen.
  void patch(String id, {String? title, String? icon}) {
    final i = _pages.indexWhere((p) => p.id == id);
    if (i == -1) return;
    _pages = [..._pages]..[i] = _pages[i].copyWith(title: title, icon: icon);
    _notify();
  }

  /// Drops a page and its descendants (after moving it to the trash).
  void removeSubtree(String id) {
    final ids = subtreeIds(_pages, id);
    _pages = _pages.where((p) => !ids.contains(p.id)).toList();
    _notify();
  }

  void toggleExpanded(String id) {
    _expanded = {..._expanded};
    if (!_expanded.remove(id)) _expanded.add(id);
    _notify();
  }

  void expand(String id) {
    if (_expanded.contains(id)) return;
    _expanded = {..._expanded, id};
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_onSession);
    super.dispose();
  }
}
