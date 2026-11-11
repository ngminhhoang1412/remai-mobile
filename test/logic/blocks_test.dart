import 'package:flutter_test/flutter_test.dart';
import 'package:remai/logic/blocks.dart';
import 'package:remai/models/models.dart';

void main() {
  var seq = 0;
  String makeId() => 'id-${++seq}';
  Block b(String id, BlockType type, [String text = '', bool checked = false]) =>
      Block(id: id, type: type, text: text, checked: checked);

  setUp(() => seq = 0);

  group('Keyboard block editing (return / backspace)', () {
    test('Continue a list: return at the end of a bulleted block adds an empty bulleted block below with focus', () {
      final res = applyTextChange([b('a', BlockType.bulleted, 'milk')], 0, 'milk\n', makeId);
      expect(res.blocks, hasLength(2));
      expect(res.blocks[0], b('a', BlockType.bulleted, 'milk'));
      expect(res.blocks[1].type, BlockType.bulleted);
      expect(res.blocks[1].text, '');
      expect(res.blocks[1].checked, isFalse);
      expect(res.focus, FocusTarget(res.blocks[1].id, atEnd: false));
    });

    for (final type in [BlockType.todo, BlockType.numbered]) {
      test('return at the end of a ${type.name} keeps the type', () {
        final res = applyReturn([b('a', type, 'x', true)], 0, makeId);
        expect(res.blocks[1].type, type);
        expect(res.blocks[1].text, '');
        expect(res.blocks[1].checked, isFalse);
      });
    }

    for (final type in [
      BlockType.paragraph,
      BlockType.heading1,
      BlockType.heading2,
      BlockType.heading3,
      BlockType.quote,
      BlockType.code,
    ]) {
      test('return at the end of a ${type.name} creates a paragraph', () {
        final res = applyReturn([b('a', type, 'x'), b('z', BlockType.paragraph, 'after')], 0, makeId);
        expect(res.blocks.map((x) => x.type), [type, BlockType.paragraph, BlockType.paragraph]);
        expect(res.blocks[1].text, '');
        expect(res.blocks[2].id, 'z');
      });
    }

    for (final type in [BlockType.bulleted, BlockType.numbered, BlockType.todo]) {
      test('Leave a list: return in an empty ${type.name} turns it into a paragraph', () {
        final res = applyTextChange([b('p', BlockType.paragraph, 'x'), b('a', type, '', true)], 1, '\n', makeId);
        expect(res.blocks, hasLength(2));
        expect(res.blocks[1], b('a', BlockType.paragraph, '', false));
        expect(res.focus, const FocusTarget('a', atEnd: true));
      });
    }

    test('a newline typed in the middle of the text stays a line break inside the block', () {
      final res = applyTextChange([b('a', BlockType.code, 'ab')], 0, 'a\nb', makeId);
      expect(res.blocks, [b('a', BlockType.code, 'a\nb')]);
      expect(res.focus, isNull);
    });

    test('return detection: autocorrect committing a word with the return still counts as return at end', () {
      expect(isReturnAtEnd('helo', 'hello\n'), isTrue);
      expect(isReturnAtEnd('abc', 'abc\n'), isTrue);
      expect(isReturnAtEnd('abc\n', 'abc\n\n'), isTrue);
      expect(isReturnAtEnd('abc\n', 'a\nbc\n'), isFalse);
      expect(isReturnAtEnd('abc', 'ab'), isFalse);
      final res = applyTextChange([b('a', BlockType.paragraph, 'helo')], 0, 'hello\n', makeId);
      expect(res.blocks[0].text, 'hello');
      expect(res.blocks, hasLength(2));
    });

    test('Remove empty block: backspace in an empty paragraph (not first) removes it and focuses the end of the previous block', () {
      final res = applyBackspaceOnEmpty([b('a', BlockType.paragraph, 'hi'), b('e', BlockType.paragraph)], 1);
      expect(res, isNotNull);
      expect(res!.blocks, [b('a', BlockType.paragraph, 'hi')]);
      expect(res.focus, const FocusTarget('a', atEnd: true));
    });

    test('backspace does nothing in the first block or in a non-empty block', () {
      expect(applyBackspaceOnEmpty([b('e', BlockType.paragraph)], 0), isNull);
      expect(applyBackspaceOnEmpty([b('a', BlockType.paragraph, 'x'), b('b', BlockType.paragraph, 'y')], 1), isNull);
    });

    test('backspace after a divider focuses the nearest previous editable block', () {
      final res =
          applyBackspaceOnEmpty([b('a', BlockType.heading1, 'T'), b('d', BlockType.divider), b('e', BlockType.todo)], 2);
      expect(res!.blocks.map((x) => x.id), ['a', 'd']);
      expect(res.focus, const FocusTarget('a', atEnd: true));
    });
  });

  group('Backspace on empty: zero-width sentinel', () {
    test('field text is the sentinel followed by the block text', () {
      expect(withSentinel(''), '​');
      expect(withSentinel('hi'), '​hi');
    });

    test('a soft-keyboard backspace in an empty block deletes the sentinel and is detected', () {
      final read = readSentinel('');
      expect(read.deletedSentinel, isTrue);
      expect(read.text, '');
    });

    test('normal typing keeps the sentinel and reports the text without it', () {
      final read = readSentinel('​hello');
      expect(read.deletedSentinel, isFalse);
      expect(read.text, 'hello');
    });

    test('backspace at the start of a non-empty block is detected but keeps the text', () {
      final read = readSentinel('hello');
      expect(read.deletedSentinel, isTrue);
      expect(read.text, 'hello');
    });

    test('pasted zero-width spaces never reach the block text', () {
      expect(readSentinel('​a​b').text, 'ab');
    });

    test('the caret is kept after the sentinel', () {
      expect(clampSelection('​abc', 0, 0), (base: 1, extent: 1));
      expect(clampSelection('​abc', 0, 3), (base: 1, extent: 3));
      expect(clampSelection('​abc', 2, 2), isNull);
      expect(clampSelection('abc', 0, 0), isNull); // sentinel already gone: onChanged handles it
    });
  });

  group('Touch block editing', () {
    test('Change block type: a paragraph turned into a To-do keeps its text and gets a checkbox', () {
      final res = turnInto([b('a', BlockType.paragraph, 'Ship it')], 0, BlockType.todo, makeId);
      expect(res.blocks[0], b('a', BlockType.todo, 'Ship it', false));
      expect(res.focus, const FocusTarget('a', atEnd: true));
    });

    test('turning a checked to-do into another type clears checked', () {
      final res = turnInto([b('a', BlockType.todo, 'x', true)], 0, BlockType.quote, makeId);
      expect(res.blocks[0], b('a', BlockType.quote, 'x', false));
    });

    test('the picker lists all 10 block types', () {
      expect(BlockType.values.map((t) => t.name), [
        'paragraph',
        'heading1',
        'heading2',
        'heading3',
        'todo',
        'bulleted',
        'numbered',
        'quote',
        'code',
        'divider',
      ]);
    });

    test('turning an empty block into a divider focuses a new paragraph after it', () {
      final res = turnInto([b('a', BlockType.paragraph)], 0, BlockType.divider, makeId);
      expect(res.blocks[0], b('a', BlockType.divider));
      expect(res.blocks[1].type, BlockType.paragraph);
      expect(res.blocks[1].text, '');
      expect(res.focus, FocusTarget(res.blocks[1].id, atEnd: false));
    });

    test('turning a block with text into a divider inserts the divider above and keeps the text', () {
      final res = turnInto([b('a', BlockType.paragraph, 'keep me')], 0, BlockType.divider, makeId);
      expect(res.blocks.map((x) => x.type), [BlockType.divider, BlockType.paragraph]);
      expect(res.blocks[1], b('a', BlockType.paragraph, 'keep me'));
    });

    test('Add a block at the end: tapping below the last block adds a focused paragraph', () {
      final res = appendParagraph([b('a', BlockType.heading1, 'Plan')], makeId);
      expect(res.blocks, hasLength(2));
      expect(res.blocks[1].type, BlockType.paragraph);
      expect(res.blocks[1].text, '');
      expect(res.focus, FocusTarget(res.blocks[1].id, atEnd: false));
    });

    test('Add a block at the end: an empty trailing paragraph is focused instead of adding another', () {
      final blocks = [b('a', BlockType.paragraph)];
      final res = appendParagraph(blocks, makeId);
      expect(res.blocks, same(blocks));
      expect(res.focus, const FocusTarget('a', atEnd: true));
    });

    test('Toggle a to-do: tapping the checkbox flips checked', () {
      final once = toggleTodo([b('a', BlockType.todo, 'x')], 0);
      expect(once[0].checked, isTrue);
      expect(toggleTodo(once, 0)[0].checked, isFalse);
      final para = [b('p', BlockType.paragraph, 'x')];
      expect(toggleTodo(para, 0), same(para));
    });

    test('divider text cannot be edited', () {
      final blocks = [b('d', BlockType.divider)];
      expect(applyTextChange(blocks, 0, 'x', makeId).blocks, same(blocks));
    });

    test('a divider can be removed (long press)', () {
      expect(removeBlock([b('a', BlockType.paragraph, 'x'), b('d', BlockType.divider)], 1), [b('a', BlockType.paragraph, 'x')]);
    });
  });

  group('Block rendering', () {
    test('Numbered list restarts: numbered, numbered, paragraph, numbered shows 1, 2, (paragraph), 1', () {
      final blocks = [
        b('1', BlockType.numbered),
        b('2', BlockType.numbered),
        b('3', BlockType.paragraph),
        b('4', BlockType.numbered),
      ];
      expect(numberLabels(blocks), [1, 2, null, 1]);
    });

    test('numbering restarts after any non-numbered type, including bulleted', () {
      final blocks = [
        b('1', BlockType.numbered),
        b('2', BlockType.bulleted),
        b('3', BlockType.numbered),
        b('4', BlockType.numbered),
      ];
      expect(numberLabels(blocks), [1, null, 1, 2]);
    });
  });

  group('Wire format', () {
    test('a block serialises to exactly the BlockInput fields', () {
      expect(b('x', BlockType.todo, 'Ship', true).toJson(), {'id': 'x', 'type': 'todo', 'text': 'Ship', 'checked': true});
    });

    test('an unknown type from a newer server falls back to paragraph', () {
      expect(Block.fromJson({'id': 'x', 'type': 'table', 'text': 't', 'checked': false}).type, BlockType.paragraph);
    });
  });
}
