import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remai/logic/blocks.dart' show sentinel;
import 'package:remai/widgets/turn_into_bar.dart';

import '../support/fake_backend.dart';

Map<String, dynamic> blk(String id, String type, [String text = '', bool checked = false]) =>
    {'id': id, 'type': type, 'text': text, 'checked': checked};

/// All block fields currently on screen, top to bottom.
Finder allBlockFields() => find.byWidgetPredicate(
      (w) => w is TextField && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('block-field-'),
    );

String idOf(WidgetTester tester, Finder field) =>
    (tester.widget<TextField>(field).key! as ValueKey<String>).value.substring('block-field-'.length);

/// Decoded bodies of the PUT /blocks requests so far.
List<List<Map<String, dynamic>>> savedBlockLists(FakeBackend backend) => [
      for (final r in backend.requestsTo('PUT', '/api/v1/pages/'))
        ((jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['blocks'] as List<dynamic>)
            .cast<Map<String, dynamic>>(),
    ];

void main() {
  late FakeBackend backend;

  /// Signs in, opens page p1 holding [content].
  Future<void> openPage(WidgetTester tester, List<Map<String, dynamic>> content) async {
    backend = FakeBackend()..addPage('p1', title: 'Plan', content: content);
    await pumpApp(tester, backend, MemoryTokenStorage(validToken));
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-title')), findsOneWidget);
  }

  /// Focuses a block's field the way a tap does, with the caret at the end.
  Future<void> focusBlock(WidgetTester tester, String id) async {
    await tester.showKeyboard(blockField(id));
    final c = tester.widget<TextField>(blockField(id)).controller!;
    c.selection = TextSelection.collapsed(offset: c.text.length);
    await tester.pump();
  }

  group('Keyboard block editing on touch (return / backspace)', () {
    testWidgets('Continue a list: return at the end of a bulleted block adds a focused bulleted block below',
        (tester) async {
      await openPage(tester, [blk('a', 'bulleted', 'milk')]);
      await focusBlock(tester, 'a');

      // The soft keyboard's return key inserts "\n" at the caret.
      await tester.enterText(blockField('a'), '${sentinel}milk\n');
      await tester.pump();

      final fields = allBlockFields();
      expect(fields, findsNWidgets(2));
      final newId = idOf(tester, fields.at(1));
      expect(fieldText(tester, 'a'), '${sentinel}milk'); // the newline didn't stay in the block
      expect(fieldFocused(tester, newId), isTrue);
      expect(find.text('•'), findsNWidgets(2));

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(savedBlockLists(backend).last, [
        blk('a', 'bulleted', 'milk'),
        blk(newId, 'bulleted'),
      ]);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('Leave a list: return in an empty to-do turns it into a paragraph', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'x'), blk('t', 'todo')]);
      await focusBlock(tester, 't');
      await tester.enterText(blockField('t'), '$sentinel\n');
      await tester.pump();
      expect(allBlockFields(), findsNWidgets(2));
      expect(find.byKey(const ValueKey('todo-check-t')), findsNothing);
      expect(fieldFocused(tester, 't'), isTrue);
    });

    testWidgets('Remove empty block: a soft-keyboard backspace in an empty block removes it and puts the caret '
        'at the end of the previous block', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'hi'), blk('e', 'paragraph')]);
      await focusBlock(tester, 'e');

      // Soft keyboards send no key event: the IME deletes the character before the caret, which is
      // the zero-width sentinel, so the field reports empty text.
      await tester.enterText(blockField('e'), '');
      await tester.pump();

      expect(blockField('e'), findsNothing);
      expect(fieldFocused(tester, 'a'), isTrue);
      final c = tester.widget<TextField>(blockField('a')).controller!;
      expect(c.selection, const TextSelection.collapsed(offset: '${sentinel}hi'.length));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(savedBlockLists(backend).last, [blk('a', 'paragraph', 'hi')]);
    });

    testWidgets('Remove empty block: a hardware-keyboard backspace takes the same path', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'hi'), blk('e', 'paragraph')]);
      await focusBlock(tester, 'e');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(blockField('e'), findsNothing);
      expect(fieldFocused(tester, 'a'), isTrue);
    });

    testWidgets('backspace in the first (only) empty block keeps it and restores the sentinel', (tester) async {
      await openPage(tester, [blk('a', 'paragraph')]);
      await focusBlock(tester, 'a');
      await tester.enterText(blockField('a'), '');
      await tester.pump();
      expect(blockField('a'), findsOneWidget);
      expect(fieldText(tester, 'a'), sentinel);
      expect(backend.requestsTo('PUT', '/api/v1/pages/'), isEmpty);
    });

    testWidgets('backspace at the start of a non-empty block keeps its text', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'one'), blk('b', 'paragraph', 'two')]);
      await focusBlock(tester, 'b');
      await tester.enterText(blockField('b'), 'two'); // sentinel deleted, text intact
      await tester.pump();
      expect(allBlockFields(), findsNWidgets(2));
      expect(fieldText(tester, 'b'), '${sentinel}two');
    });

    testWidgets('typing never puts the caret before the sentinel', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'abc')]);
      await focusBlock(tester, 'a');
      final c = tester.widget<TextField>(blockField('a')).controller!;
      c.selection = const TextSelection.collapsed(offset: 0);
      expect(c.selection.baseOffset, 1);
    });
  });

  group('Touch block editing', () {
    testWidgets('Change block type: focus a paragraph, tap "Turn into" → To-do; it keeps its text and focus',
        (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'Ship it')]);
      expect(find.byType(TurnIntoBar), findsNothing);
      await focusBlock(tester, 'a');
      expect(find.byType(TurnIntoBar), findsOneWidget);
      for (final label in ['Text', 'Heading 1', 'Heading 2', 'Heading 3', 'To-do']) {
        expect(find.descendant(of: find.byType(TurnIntoBar), matching: find.text(label)), findsOneWidget);
      }
      final fieldBefore = tester.element(blockField('a'));

      await tester.ensureVisible(find.byKey(const ValueKey('turn-into-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('turn-into-todo')));
      await tester.pump();

      expect(find.byKey(const ValueKey('todo-check-a')), findsOneWidget);
      expect(fieldText(tester, 'a'), '${sentinel}Ship it');
      expect(fieldFocused(tester, 'a'), isTrue);
      expect(identical(tester.element(blockField('a')), fieldBefore), isTrue, reason: 'field re-styled, not remounted');

      // The bar scrolls sideways to the remaining types; the block keeps focus.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('turn-into-divider')),
        find.byKey(const ValueKey('turn-into-list')),
        const Offset(-200, 0),
      );
      expect(fieldFocused(tester, 'a'), isTrue);

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(savedBlockLists(backend).last, [blk('a', 'todo', 'Ship it')]);
    });

    testWidgets('Toggle a to-do: tapping the checkbox checks it, strikes the text through and saves', (tester) async {
      await openPage(tester, [blk('t', 'todo', 'Buy milk')]);
      await tester.tap(find.byKey(const ValueKey('todo-check-t')));
      await tester.pump();
      final style = tester.widget<TextField>(blockField('t')).style!;
      expect(style.decoration, TextDecoration.lineThrough);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(savedBlockLists(backend).last, [blk('t', 'todo', 'Buy milk', true)]);
    });

    testWidgets('Add a block at the end: tapping below adds a focused paragraph, tapping again only focuses it',
        (tester) async {
      await openPage(tester, [blk('h', 'heading1', 'Plan')]);
      await tester.tap(find.byKey(const ValueKey('tap-below')));
      await tester.pump();
      expect(allBlockFields(), findsNWidgets(2));
      final newId = idOf(tester, allBlockFields().at(1));
      expect(fieldFocused(tester, newId), isTrue);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tap-below')));
      await tester.pump();
      expect(allBlockFields(), findsNWidgets(2));
      expect(fieldFocused(tester, newId), isTrue);
    });

    testWidgets('Numbered list restarts: numbered, numbered, paragraph, numbered shows 1, 2, (paragraph), 1',
        (tester) async {
      await openPage(tester, [
        blk('1', 'numbered', 'a'),
        blk('2', 'numbered', 'b'),
        blk('3', 'paragraph', 'c'),
        blk('4', 'numbered', 'd'),
      ]);
      expect(find.text('1.'), findsNWidgets(2));
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets('a divider is not editable and is deleted by long press after confirming', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'x'), blk('d', 'divider')]);
      expect(blockField('d'), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('divider-d')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('divider-d')), findsNothing);
    });
  });

  group('Keyboard-safe layout', () {
    testWidgets('Typing near the bottom: the focused last block stays visible above the keyboard', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532); // 390 x 844 phone
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await openPage(tester, [for (var i = 0; i < 40; i++) blk('b$i', 'paragraph', 'Line $i')]);
      await tester.drag(find.byKey(const ValueKey('page-scroll')), const Offset(0, -5000)); // scroll to the end
      await tester.pumpAndSettle();
      await focusBlock(tester, 'b39');
      // Precondition: without scrolling, the keyboard would cover the block.
      expect(tester.getRect(blockField('b39')).bottom, greaterThan(844 - 300));

      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3); // the soft keyboard opens
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byKey(const ValueKey('page-scroll')));
      final field = tester.getRect(blockField('b39'));
      expect(viewport.bottom, lessThanOrEqualTo(844 - 300), reason: 'the editor shrinks above the keyboard');
      expect(field.top, greaterThanOrEqualTo(viewport.top));
      expect(field.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(find.byType(TurnIntoBar), findsOneWidget);
      expect(tester.getRect(find.byType(TurnIntoBar)).bottom, lessThanOrEqualTo(844 - 300));
    });
  });

  group('Autosave and page actions', () {
    testWidgets('leaving the page flushes a pending save immediately', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', '')]);
      await focusBlock(tester, 'a');
      await tester.enterText(blockField('a'), '${sentinel}draft');
      await tester.pump(const Duration(milliseconds: 100));
      expect(backend.requestsTo('PUT', '/api/v1/pages/'), isEmpty);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(savedBlockLists(backend).single, [blk('a', 'paragraph', 'draft')]);
    });

    testWidgets('Rename: the title is saved with PATCH and Home shows it', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', '')]);
      await tester.enterText(find.byKey(const ValueKey('page-title')), 'Roadmap');
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      final patch = backend.requestsTo('PATCH', '/api/v1/pages/p1').single;
      expect(jsonDecode(patch.body), {'title': 'Roadmap', 'icon': ''});
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Roadmap'), findsOneWidget);
    });

    testWidgets('page icon: pick an emoji, then remove it', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', '')]);
      await tester.tap(find.byKey(const ValueKey('page-icon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('emoji-🚀')));
      await tester.pumpAndSettle();
      expect(backend.pages['p1']!['icon'], '🚀');

      await tester.tap(find.byKey(const ValueKey('page-icon')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(backend.pages['p1']!['icon'], '');
    });

    testWidgets('Add a subpage: creates a child of this page and opens it', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'x')]);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add subpage'));
      await tester.pumpAndSettle();
      final post = backend.requestsTo('POST', '/api/v1/pages').single;
      expect(jsonDecode(post.body), {'parentId': 'p1'});
      expect(tester.widget<TextField>(find.byKey(const ValueKey('page-title'))).controller!.text, '');
    });

    testWidgets('Move to trash: the page leaves the tree and Home is shown', (tester) async {
      await openPage(tester, [blk('a', 'paragraph', 'x')]);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to trash'));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('DELETE', '/api/v1/pages/p1'), hasLength(1));
      expect(find.text('Ada’s remai'), findsOneWidget);
      expect(find.text('Plan'), findsNothing);
    });
  });
}
