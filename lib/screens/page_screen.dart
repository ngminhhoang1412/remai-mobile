import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart' show GoRouterHelper;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../logic/autosave.dart';
import '../logic/blocks.dart';
import '../logic/ids.dart';
import '../models/models.dart';
import '../router.dart';
import '../state/pages.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/block_row.dart';
import '../widgets/common.dart';
import '../widgets/emoji_picker.dart';
import '../widgets/turn_into_bar.dart';

enum _Load { loading, ready, notFound, error }

enum _PageAction { addSubpage, trash }

typedef _Meta = ({String title, String icon});

/// Page editor: icon, title and blocks, autosaved (blocks via PUT, title/icon via PATCH).
class PageScreen extends StatefulWidget {
  const PageScreen({super.key, required this.pageId, this.makeId = newId});

  final String pageId;

  /// Block id generator (tests inject a deterministic one).
  final MakeId makeId;

  @override
  State<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<PageScreen> {
  late final SessionState _session = context.read<SessionState>();
  late final PagesState _pages = context.read<PagesState>();

  _Load _load = _Load.loading;
  String? _loadError;
  int _loadSeq = 0;

  _Meta _meta = (title: '', icon: '');
  List<Block> _blocks = const [];
  final _controllers = <String, BlockTextController>{};
  final _focusNodes = <String, FocusNode>{};
  String? _focusedId;

  final _titleController = TextEditingController();
  final _titleFocus = FocusNode();

  late final AutosaveController<List<Block>> _blockSaver;
  late final AutosaveController<_Meta> _metaSaver;
  SaveStatus _blockStatus = SaveStatus.idle;
  SaveStatus _metaStatus = SaveStatus.idle;
  late final AppLifecycleListener _lifecycle;
  bool _busy = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final api = _session.api;
    final id = widget.pageId;
    _blockSaver = AutosaveController<List<Block>>(
      save: (blocks) => api.saveBlocks(id, blocks),
      isRetryable: isRetryableSaveError,
      onStatusChange: (s) => _setIfMounted(() => _blockStatus = s),
    );
    _metaSaver = AutosaveController<_Meta>(
      save: (m) async {
        await api.updatePage(id, title: m.title, icon: m.icon);
      },
      isRetryable: isRetryableSaveError,
      onStatusChange: (s) => _setIfMounted(() => _metaStatus = s),
    );
    // App going to the background (or being covered): save now.
    _lifecycle = AppLifecycleListener(
      onInactive: _flushAll,
      onHide: _flushAll,
      onPause: _flushAll,
    );
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    // Leaving the page: save anything pending, then stop retrying.
    unawaited(_blockSaver.flush().whenComplete(_blockSaver.dispose));
    unawaited(_metaSaver.flush().whenComplete(_metaSaver.dispose));
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _setIfMounted(VoidCallback fn) {
    if (mounted && !_disposed) setState(fn);
  }

  void _flushAll() {
    unawaited(_blockSaver.flush());
    unawaited(_metaSaver.flush());
  }

  Future<void> _flushAllAndWait() => Future.wait([_blockSaver.flush(), _metaSaver.flush()]);

  // ---------------------------------------------------------------- load

  Future<void> _loadPage() async {
    final seq = ++_loadSeq;
    setState(() => _load = _Load.loading);
    try {
      final res = await _session.api.getPage(widget.pageId);
      if (!mounted || seq != _loadSeq) return;
      // Empty pages get one local paragraph to type into; it isn't saved until edited.
      final blocks = res.blocks.isNotEmpty ? res.blocks : [createBlock(widget.makeId)];
      _titleController.text = res.page.title;
      setState(() {
        _meta = (title: res.page.title, icon: res.page.icon);
        _blocks = blocks;
        _syncFieldState(null);
        _load = _Load.ready;
      });
      _pages.upsert(res.page);
    } on ApiException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        if (e.status == 404) {
          _load = _Load.notFound;
        } else {
          _loadError = e.message;
          _load = _Load.error;
        }
      });
    }
  }

  // ---------------------------------------------------------------- field bookkeeping

  BlockTextController _controllerFor(Block b) => _controllers.putIfAbsent(b.id, () => BlockTextController(b.text));

  FocusNode _focusNodeFor(String id) => _focusNodes.putIfAbsent(id, () {
        final node = FocusNode(debugLabel: 'block-$id');
        node.addListener(() => _onFocusChange(id, node));
        return node;
      });

  void _onFocusChange(String id, FocusNode node) {
    if (!mounted) return;
    if (node.hasFocus) {
      if (_focusedId != id) setState(() => _focusedId = id);
    } else if (_focusedId == id) {
      setState(() => _focusedId = null);
    }
  }

  /// Makes every field show its block's text, creates fields for new blocks and drops fields of
  /// removed ones (after this frame, so a field that is unmounting never sees a disposed node).
  void _syncFieldState(FocusTarget? focus) {
    final ids = <String>{};
    for (final b in _blocks) {
      ids.add(b.id);
      if (b.type == BlockType.divider) continue;
      final c = _controllerFor(b);
      _focusNodeFor(b.id);
      if (c.blockText != b.text || !c.text.startsWith(sentinel)) {
        c.setBlockText(b.text, atEnd: focus?.id != b.id || focus!.atEnd);
      }
    }
    final gone = [for (final id in _controllers.keys) if (!ids.contains(id)) id];
    final goneNodes = [for (final id in _focusNodes.keys) if (!ids.contains(id)) id];
    if (gone.isEmpty && goneNodes.isEmpty) return;
    final controllers = [for (final id in gone) _controllers.remove(id)!];
    final nodes = [for (final id in goneNodes) _focusNodes.remove(id)!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in controllers) {
        c.dispose();
      }
      for (final n in nodes) {
        n.dispose();
      }
    });
  }

  /// Applies an edit: new block list (saved by the debounced autosave) and an optional caret move.
  void _commit(EditResult res) {
    final changed = !identical(res.blocks, _blocks);
    setState(() {
      _blocks = res.blocks;
      _syncFieldState(res.focus);
    });
    if (changed) _blockSaver.update(res.blocks);
    final focus = res.focus;
    if (focus != null) _focusAfterFrame(focus);
  }

  /// Moves focus to a block. An already-mounted field is focused right away, so focus passes
  /// straight from field to field (a removed field never holds focus when it unmounts, which would
  /// close and reopen the keyboard). A field created by this edit is focused after the frame that
  /// mounts it.
  void _focusAfterFrame(FocusTarget target) {
    bool apply() {
      if (!mounted) return true;
      final node = _focusNodes[target.id];
      final c = _controllers[target.id];
      if (node == null || c == null) return true;
      if (node.context == null) return false; // not mounted yet
      node.requestFocus();
      c.moveCaret(atEnd: target.atEnd);
      return true;
    }

    if (apply()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  int _indexOf(String id) => _blocks.indexWhere((b) => b.id == id);

  // ---------------------------------------------------------------- block editing

  void _onBlockChanged(String id, String raw) {
    final index = _indexOf(id);
    if (index < 0) return;
    final read = readSentinel(raw);
    if (read.deletedSentinel && _blocks[index].text.isEmpty) {
      // Backspace in an empty block.
      final res = applyBackspaceOnEmpty(_blocks, index);
      if (res == null) {
        _controllers[id]?.setBlockText(''); // first block: nothing to remove, restore the sentinel
        return;
      }
      if (res.focus == null) FocusManager.instance.primaryFocus?.unfocus();
      _commit(res);
      return;
    }
    // Typing, a return at the end, or a backspace at the start of a non-empty block (the sentinel
    // is put back by _syncFieldState and the text is unchanged).
    _commit(applyTextChange(_blocks, index, read.text, widget.makeId));
  }

  void _onToggle(String id) => _commit(EditResult(toggleTodo(_blocks, _indexOf(id))));

  Future<void> _onDividerLongPress(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete divider?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _commit(EditResult(removeBlock(_blocks, _indexOf(id))));
  }

  void _onTurnInto(BlockType type) {
    final id = _focusedId;
    if (id == null) return;
    final index = _indexOf(id);
    if (index < 0) return;
    _commit(turnInto(_blocks, index, type, widget.makeId));
  }

  void _onTapBelow() => _commit(appendParagraph(_blocks, widget.makeId));

  // ---------------------------------------------------------------- title / icon

  void _updateMeta(_Meta next) {
    setState(() => _meta = next);
    _pages.patch(widget.pageId, title: next.title, icon: next.icon); // Home shows it right away
    _metaSaver.update(next);
  }

  void _onTitleChanged(String text) {
    var title = text;
    if (title.contains('\n')) {
      title = title.replaceAll('\n', ' ');
      _titleController.value = TextEditingValue(text: title, selection: TextSelection.collapsed(offset: title.length));
    }
    _updateMeta((title: title, icon: _meta.icon));
  }

  void _onTitleSubmitted(String _) {
    for (final b in _blocks) {
      if (b.type != BlockType.divider) {
        _focusAfterFrame(FocusTarget(b.id, atEnd: true));
        return;
      }
    }
    _onTapBelow();
  }

  Future<void> _pickIcon() async {
    final picked = await showEmojiPicker(context, hasIcon: _meta.icon.isNotEmpty);
    if (picked == null || !mounted) return;
    _updateMeta((title: _meta.title, icon: picked));
    unawaited(_metaSaver.flush()); // icon changes are discrete: save now
  }

  // ---------------------------------------------------------------- page actions

  Future<void> _onAction(_PageAction action) async {
    switch (action) {
      case _PageAction.addSubpage:
        await _addSubpage();
      case _PageAction.trash:
        await _moveToTrash();
    }
  }

  Future<void> _addSubpage() async {
    setState(() => _busy = true);
    try {
      _flushAll();
      final child = await _session.api.createPage(parentId: widget.pageId);
      _pages
        ..upsert(child)
        ..expand(widget.pageId);
      if (mounted) unawaited(context.push(Routes.page(child.id)));
    } on ApiException catch (e) {
      if (mounted) showErrorSnack(context, 'Couldn’t add subpage', e);
    } finally {
      _setIfMounted(() => _busy = false);
    }
  }

  Future<void> _moveToTrash() async {
    setState(() => _busy = true);
    try {
      await _flushAllAndWait();
      await _session.api.trashPage(widget.pageId);
      _blockSaver.dispose();
      _metaSaver.dispose();
      _pages.removeSubtree(widget.pageId);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.home);
      }
    } on ApiException catch (e) {
      _setIfMounted(() => _busy = false);
      if (mounted) showErrorSnack(context, 'Couldn’t move to trash', e);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final status = combineStatus([_blockStatus, _metaStatus]);
    final failed = status == SaveStatus.error || status == SaveStatus.failed;
    return Scaffold(
      appBar: AppBar(
        actions: _load != _Load.ready
            ? null
            : [
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      statusLabel(status),
                      key: const ValueKey('save-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: failed ? AppColors.danger : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<_PageAction>(
                  tooltip: 'Page actions',
                  icon: const Icon(Icons.more_horiz),
                  enabled: !_busy,
                  onSelected: (a) => unawaited(_onAction(a)),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _PageAction.addSubpage,
                      child: ListTile(leading: Icon(Icons.add_circle_outline), title: Text('Add subpage')),
                    ),
                    PopupMenuItem(
                      value: _PageAction.trash,
                      child: ListTile(
                        leading: Icon(Icons.delete_outline, color: AppColors.danger),
                        title: Text('Move to trash', style: TextStyle(color: AppColors.danger)),
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: SafeArea(top: false, child: _body()),
    );
  }

  Widget _body() {
    switch (_load) {
      case _Load.loading:
        return const LoadingState();
      case _Load.notFound:
        return const MessageState(
          icon: Icons.description_outlined,
          title: 'Page not found',
          message: 'It may have been moved to the trash or deleted.',
        );
      case _Load.error:
        return MessageState(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn’t open this page',
          message: _loadError,
          actionLabel: 'Try again',
          onAction: () => unawaited(_loadPage()),
        );
      case _Load.ready:
        break;
    }

    final numbers = numberLabels(_blocks);
    final focusedIndex = _focusedId == null ? -1 : _indexOf(_focusedId!);
    final focusedBlock = focusedIndex >= 0 ? _blocks[focusedIndex] : null;

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            key: const ValueKey('page-scroll'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _iconRow(),
                      _titleField(),
                      const SizedBox(height: Space.s3),
                      // Not lazy: every block keeps its field mounted, so focus can move to any block.
                      for (var i = 0; i < _blocks.length; i++) _blockRow(_blocks[i], numbers[i]),
                    ],
                  ),
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Semantics(
                  button: true,
                  label: 'Add a block at the end',
                  child: GestureDetector(
                    key: const ValueKey('tap-below'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTapBelow,
                    child: const SizedBox(height: 160, width: double.infinity),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (focusedBlock != null)
          TurnIntoBar(
            current: focusedBlock.type,
            onPick: _onTurnInto,
            onDone: () => FocusManager.instance.primaryFocus?.unfocus(),
          ),
      ],
    );
  }

  /// Callbacks capture the block id (not its index), so a stale closure can't hit another block.
  Widget _blockRow(Block block, int? number) {
    final id = block.id;
    return BlockRow(
      key: ValueKey('block-$id'),
      block: block,
      number: number,
      controller: _controllerFor(block),
      focusNode: _focusNodeFor(id),
      showPlaceholder: id == _focusedId || _blocks.length == 1,
      onChanged: (raw) => _onBlockChanged(id, raw),
      onToggle: () => _onToggle(id),
      onDividerLongPress: () => unawaited(_onDividerLongPress(id)),
    );
  }

  Widget _iconRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: _meta.icon.isNotEmpty
          ? Semantics(
              button: true,
              label: 'Change icon',
              child: InkWell(
                key: const ValueKey('page-icon'),
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => unawaited(_pickIcon()),
                child: Padding(
                  padding: const EdgeInsets.all(Space.s1),
                  child: Text(_meta.icon, style: const TextStyle(fontSize: 48, height: 1.2)),
                ),
              ),
            )
          : TextButton.icon(
              key: const ValueKey('page-icon'),
              onPressed: () => unawaited(_pickIcon()),
              style: TextButton.styleFrom(foregroundColor: AppColors.textFaint),
              icon: const Icon(Icons.emoji_emotions_outlined, size: 18),
              label: const Text('Add icon'),
            ),
    );
  }

  Widget _titleField() {
    return TextField(
      key: const ValueKey('page-title'),
      controller: _titleController,
      focusNode: _titleFocus,
      onChanged: _onTitleChanged,
      onSubmitted: _onTitleSubmitted,
      onEditingComplete: () {}, // keep focus handling in onSubmitted
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.next,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [LengthLimitingTextInputFormatter(200)],
      style: const TextStyle(fontSize: FontSizes.title, height: 1.25, fontWeight: FontWeight.w600, color: AppColors.text),
      decoration: const InputDecoration.collapsed(
        hintText: 'Untitled',
        hintStyle: TextStyle(fontSize: FontSizes.title, fontWeight: FontWeight.w600, color: AppColors.textFaint),
      ),
    );
  }
}
