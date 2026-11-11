// Pure block-editing rules: page-content "Block rendering" plus web-client "Keyboard block editing",
// which the mobile-client spec reuses for return/backspace. No Flutter imports, so the rules are
// unit-testable. Callers inject the id generator.
import '../models/models.dart';

typedef MakeId = String Function();

/// Types whose "next block" keeps the same type on return.
const Set<BlockType> listTypes = {BlockType.todo, BlockType.bulleted, BlockType.numbered};

bool isListType(BlockType type) => listTypes.contains(type);

Block createBlock(MakeId makeId, [BlockType type = BlockType.paragraph, String text = '']) =>
    Block(id: makeId(), type: type, text: type == BlockType.divider ? '' : text);

/// Where the editor should put the caret after an edit.
class FocusTarget {
  const FocusTarget(this.id, {required this.atEnd});

  final String id;

  /// Put the caret at the end of the block's text (otherwise at the start).
  final bool atEnd;

  @override
  bool operator ==(Object other) => other is FocusTarget && other.id == id && other.atEnd == atEnd;

  @override
  int get hashCode => Object.hash(id, atEnd);

  @override
  String toString() => 'FocusTarget($id, atEnd: $atEnd)';
}

class EditResult {
  const EditResult(this.blocks, [this.focus]);

  final List<Block> blocks;
  final FocusTarget? focus;
}

/// True when [next] is [prev] with a return typed at the very end. A multiline TextField inserts
/// "\n" on return (TextInputAction.newline) on both platforms and reports it through onChanged, so
/// this is how "return at the end of a block" is detected. The text before the newline may differ
/// from [prev] (keyboard autocorrect commits the current word together with the return key).
/// A newline typed in the middle of the text is kept as a line break inside the block.
bool isReturnAtEnd(String prev, String next) {
  if (next.length <= prev.length || !next.endsWith('\n')) return false;
  // If the old text already ended with a newline, only an append counts as "at the end".
  if (prev.endsWith('\n')) return next.startsWith(prev);
  return true;
}

List<Block> _replaceAt(List<Block> blocks, int index, Block block) => [...blocks]..[index] = block;

bool _valid(List<Block> blocks, int index) => index >= 0 && index < blocks.length;

/// Return at the end of block [index] (its text already has the newline removed):
/// - empty to-do / bulleted / numbered: becomes a paragraph (leave the list)
/// - otherwise a new block is inserted below and focused; it keeps the type for
///   to-do / bulleted / numbered and is a paragraph for every other type.
EditResult applyReturn(List<Block> blocks, int index, MakeId makeId) {
  if (!_valid(blocks, index)) return EditResult(blocks);
  final block = blocks[index];
  if (isListType(block.type) && block.text.isEmpty) {
    return EditResult(
      _replaceAt(blocks, index, block.copyWith(type: BlockType.paragraph, checked: false)),
      FocusTarget(block.id, atEnd: true),
    );
  }
  final next = createBlock(makeId, isListType(block.type) ? block.type : BlockType.paragraph);
  return EditResult([...blocks]..insert(index + 1, next), FocusTarget(next.id, atEnd: false));
}

/// onChanged handler: plain text update, or the return rules when a return was typed at the end.
EditResult applyTextChange(List<Block> blocks, int index, String nextText, MakeId makeId) {
  if (!_valid(blocks, index)) return EditResult(blocks);
  final block = blocks[index];
  if (block.type == BlockType.divider) return EditResult(blocks);
  if (isReturnAtEnd(block.text, nextText)) {
    final withText = _replaceAt(blocks, index, block.copyWith(text: nextText.substring(0, nextText.length - 1)));
    return applyReturn(withText, index, makeId);
  }
  if (nextText == block.text) return EditResult(blocks);
  return EditResult(_replaceAt(blocks, index, block.copyWith(text: nextText)));
}

/// Backspace in an empty block removes it and moves the caret to the end of the previous
/// (editable) block. Returns null when nothing should happen: the block isn't empty, or it is
/// the first block.
EditResult? applyBackspaceOnEmpty(List<Block> blocks, int index) {
  if (!_valid(blocks, index) || index == 0 || blocks[index].text.isNotEmpty) return null;
  final copy = [...blocks]..removeAt(index);
  for (var i = index - 1; i >= 0; i--) {
    if (copy[i].type != BlockType.divider) return EditResult(copy, FocusTarget(copy[i].id, atEnd: true));
  }
  return EditResult(copy);
}

/// "Turn into": changes the block's type and keeps its text. `checked` survives only on to-do.
/// Dividers carry no text, so turning an empty block into a divider converts it and moves focus to
/// the next editable block (adding a paragraph when there is none). Turning a block that has text
/// into a divider inserts the divider above it instead, so no text is lost.
EditResult turnInto(List<Block> blocks, int index, BlockType type, MakeId makeId) {
  if (!_valid(blocks, index)) return EditResult(blocks);
  final block = blocks[index];
  if (type != BlockType.divider) {
    final changed = block.copyWith(type: type, checked: type == BlockType.todo ? block.checked : false);
    return EditResult(_replaceAt(blocks, index, changed), FocusTarget(block.id, atEnd: true));
  }
  if (block.text.isNotEmpty) {
    return EditResult(
      [...blocks]..insert(index, createBlock(makeId, BlockType.divider)),
      FocusTarget(block.id, atEnd: true),
    );
  }
  final copy = _replaceAt(blocks, index, block.copyWith(type: BlockType.divider, text: '', checked: false));
  for (var i = index + 1; i < copy.length; i++) {
    if (copy[i].type != BlockType.divider) return EditResult(copy, FocusTarget(copy[i].id, atEnd: false));
  }
  final para = createBlock(makeId);
  return EditResult([...copy, para], FocusTarget(para.id, atEnd: false));
}

List<Block> toggleTodo(List<Block> blocks, int index) {
  if (!_valid(blocks, index) || blocks[index].type != BlockType.todo) return blocks;
  return _replaceAt(blocks, index, blocks[index].copyWith(checked: !blocks[index].checked));
}

List<Block> removeBlock(List<Block> blocks, int index) {
  if (!_valid(blocks, index)) return blocks;
  return [...blocks]..removeAt(index);
}

/// Tapping the empty area below the last block: focus a new paragraph at the end. If the last
/// block already is an empty paragraph it is focused instead of stacking another empty one.
EditResult appendParagraph(List<Block> blocks, MakeId makeId) {
  if (blocks.isNotEmpty) {
    final last = blocks.last;
    if (last.type == BlockType.paragraph && last.text.isEmpty) {
      return EditResult(blocks, FocusTarget(last.id, atEnd: true));
    }
  }
  final para = createBlock(makeId);
  return EditResult([...blocks, para], FocusTarget(para.id, atEnd: false));
}

/// Display numbers for numbered blocks: a running count that restarts at 1 after any
/// non-numbered block. Non-numbered blocks get null.
List<int?> numberLabels(List<Block> blocks) {
  var n = 0;
  final labels = <int?>[];
  for (final b in blocks) {
    if (b.type == BlockType.numbered) {
      n += 1;
      labels.add(n);
    } else {
      n = 0;
      labels.add(null);
    }
  }
  return labels;
}

String placeholderFor(BlockType type) => switch (type) {
      BlockType.heading1 => 'Heading 1',
      BlockType.heading2 => 'Heading 2',
      BlockType.heading3 => 'Heading 3',
      BlockType.todo => 'To-do',
      BlockType.bulleted || BlockType.numbered => 'List',
      BlockType.quote => 'Quote',
      BlockType.code => 'Code',
      _ => 'Type something…',
    };

// ---------------------------------------------------------------------------------------------
// Backspace on an empty block (zero-width sentinel technique, see AGENTS.md)
//
// Soft keyboards don't deliver key events to Flutter, and deleting in an already-empty TextField
// changes nothing, so onChanged never fires. Each block's field therefore holds an invisible
// U+200B ZERO WIDTH SPACE in front of the real text, and the caret is never allowed before it.
// The only way to remove the sentinel is a delete at the very start of the field, so its absence
// in onChanged means "backspace at the start of the block". When the block was empty that is
// "backspace in an empty block"; otherwise the sentinel is put back and nothing else happens.
// ---------------------------------------------------------------------------------------------

/// Invisible character kept at offset 0 of every block's TextField.
const String sentinel = '​';

/// Field text for a block's text.
String withSentinel(String text) => '$sentinel$text';

/// What a block field's raw text means.
class SentinelRead {
  const SentinelRead(this.text, {required this.deletedSentinel});

  /// The block text, with every sentinel character removed.
  final String text;

  /// True when the leading sentinel is gone: a delete happened at the start of the field.
  final bool deletedSentinel;
}

SentinelRead readSentinel(String raw) =>
    SentinelRead(raw.replaceAll(sentinel, ''), deletedSentinel: !raw.startsWith(sentinel));

/// Keeps both selection offsets of a field holding [raw] out of the sentinel (offset 0 sits before
/// it). Returns null when nothing needs to change.
({int base, int extent})? clampSelection(String raw, int base, int extent) {
  if (!raw.startsWith(sentinel) || base < 0 || extent < 0) return null;
  if (base >= 1 && extent >= 1) return null;
  return (base: base < 1 ? 1 : base, extent: extent < 1 ? 1 : extent);
}
