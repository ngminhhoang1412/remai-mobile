import {
  appendParagraph,
  applyBackspaceOnEmpty,
  applyReturn,
  applyTextChange,
  BLOCK_TYPES,
  isReturnAtEnd,
  numberLabels,
  toggleTodo,
  turnInto,
} from '../blocks';
import type { Block, BlockType } from '../types';

let seq = 0;
const makeId = () => `id-${++seq}`;
const b = (id: string, type: BlockType, text = '', checked = false): Block => ({ id, type, text, checked });

beforeEach(() => {
  seq = 0;
});

describe('Keyboard block editing (return / backspace)', () => {
  test('Continue a list: return at the end of a bulleted block adds an empty bulleted block below with focus', () => {
    const blocks = [b('a', 'bulleted', 'milk')];
    const res = applyTextChange(blocks, 0, 'milk\n', makeId);
    expect(res.blocks).toHaveLength(2);
    expect(res.blocks[0]).toEqual(b('a', 'bulleted', 'milk'));
    expect(res.blocks[1]).toMatchObject({ type: 'bulleted', text: '', checked: false });
    expect(res.focus).toEqual({ id: res.blocks[1].id, atEnd: false });
  });

  test.each<BlockType>(['todo', 'numbered'])('return at the end of a %s keeps the type', (type) => {
    const res = applyReturn([b('a', type, 'x', true)], 0, makeId);
    expect(res.blocks[1]).toMatchObject({ type, text: '', checked: false });
  });

  test.each<BlockType>(['paragraph', 'heading1', 'heading2', 'heading3', 'quote', 'code'])(
    'return at the end of a %s creates a paragraph',
    (type) => {
      const res = applyReturn([b('a', type, 'x'), b('z', 'paragraph', 'after')], 0, makeId);
      expect(res.blocks.map((x) => x.type)).toEqual([type, 'paragraph', 'paragraph']);
      expect(res.blocks[1].text).toBe('');
      expect(res.blocks[2].id).toBe('z');
    },
  );

  test.each<BlockType>(['bulleted', 'numbered', 'todo'])(
    'Leave a list: return in an empty %s turns it into a paragraph',
    (type) => {
      const res = applyTextChange([b('p', 'paragraph', 'x'), b('a', type, '', true)], 1, '\n', makeId);
      expect(res.blocks).toHaveLength(2);
      expect(res.blocks[1]).toEqual(b('a', 'paragraph', '', false));
      expect(res.focus).toEqual({ id: 'a', atEnd: true });
    },
  );

  test('a newline typed in the middle of the text stays a line break inside the block', () => {
    const res = applyTextChange([b('a', 'code', 'ab')], 0, 'a\nb', makeId);
    expect(res.blocks).toEqual([b('a', 'code', 'a\nb')]);
    expect(res.focus).toBeNull();
  });

  test('return detection: autocorrect committing a word with the return still counts as return at end', () => {
    expect(isReturnAtEnd('helo', 'hello\n')).toBe(true);
    expect(isReturnAtEnd('abc', 'abc\n')).toBe(true);
    expect(isReturnAtEnd('abc\n', 'abc\n\n')).toBe(true);
    expect(isReturnAtEnd('abc\n', 'a\nbc\n')).toBe(false);
    expect(isReturnAtEnd('abc', 'ab')).toBe(false);
    const res = applyTextChange([b('a', 'paragraph', 'helo')], 0, 'hello\n', makeId);
    expect(res.blocks[0].text).toBe('hello');
    expect(res.blocks).toHaveLength(2);
  });

  test('Remove empty block: backspace in an empty paragraph (not first) removes it and focuses the end of the previous block', () => {
    const res = applyBackspaceOnEmpty([b('a', 'paragraph', 'hi'), b('e', 'paragraph')], 1);
    expect(res).not.toBeNull();
    expect(res!.blocks).toEqual([b('a', 'paragraph', 'hi')]);
    expect(res!.focus).toEqual({ id: 'a', atEnd: true });
  });

  test('backspace does nothing in the first block or in a non-empty block', () => {
    expect(applyBackspaceOnEmpty([b('e', 'paragraph')], 0)).toBeNull();
    expect(applyBackspaceOnEmpty([b('a', 'paragraph', 'x'), b('b', 'paragraph', 'y')], 1)).toBeNull();
  });

  test('backspace after a divider focuses the nearest previous editable block', () => {
    const res = applyBackspaceOnEmpty([b('a', 'heading1', 'T'), b('d', 'divider'), b('e', 'todo')], 2);
    expect(res!.blocks.map((x) => x.id)).toEqual(['a', 'd']);
    expect(res!.focus).toEqual({ id: 'a', atEnd: true });
  });
});

describe('Touch block editing', () => {
  test('Change block type: a paragraph turned into a To-do keeps its text and gets a checkbox', () => {
    const res = turnInto([b('a', 'paragraph', 'Ship it')], 0, 'todo', makeId);
    expect(res.blocks[0]).toEqual(b('a', 'todo', 'Ship it', false));
    expect(res.focus).toEqual({ id: 'a', atEnd: true });
  });

  test('turning a checked to-do into another type clears checked', () => {
    const res = turnInto([b('a', 'todo', 'x', true)], 0, 'quote', makeId);
    expect(res.blocks[0]).toEqual(b('a', 'quote', 'x', false));
  });

  test('the picker lists all 10 block types', () => {
    expect(BLOCK_TYPES.map((t) => t.type)).toEqual([
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

  test('turning an empty block into a divider focuses a new paragraph after it', () => {
    const res = turnInto([b('a', 'paragraph')], 0, 'divider', makeId);
    expect(res.blocks[0]).toEqual(b('a', 'divider'));
    expect(res.blocks[1]).toMatchObject({ type: 'paragraph', text: '' });
    expect(res.focus).toEqual({ id: res.blocks[1].id, atEnd: false });
  });

  test('turning a block with text into a divider inserts the divider above and keeps the text', () => {
    const res = turnInto([b('a', 'paragraph', 'keep me')], 0, 'divider', makeId);
    expect(res.blocks.map((x) => x.type)).toEqual(['divider', 'paragraph']);
    expect(res.blocks[1]).toEqual(b('a', 'paragraph', 'keep me'));
  });

  test('Add a block at the end: tapping below the last block adds a focused paragraph', () => {
    const res = appendParagraph([b('a', 'heading1', 'Plan')], makeId);
    expect(res.blocks).toHaveLength(2);
    expect(res.blocks[1]).toMatchObject({ type: 'paragraph', text: '' });
    expect(res.focus).toEqual({ id: res.blocks[1].id, atEnd: false });
  });

  test('tapping below an empty trailing paragraph focuses it instead of stacking another', () => {
    const res = appendParagraph([b('a', 'paragraph')], makeId);
    expect(res.blocks).toHaveLength(1);
    expect(res.focus).toEqual({ id: 'a', atEnd: true });
  });

  test('Toggle a to-do: tapping the checkbox flips checked', () => {
    const once = toggleTodo([b('a', 'todo', 'x')], 0);
    expect(once[0].checked).toBe(true);
    expect(toggleTodo(once, 0)[0].checked).toBe(false);
    const para = [b('p', 'paragraph', 'x')];
    expect(toggleTodo(para, 0)).toBe(para);
  });

  test('divider text cannot be edited', () => {
    const blocks = [b('d', 'divider')];
    expect(applyTextChange(blocks, 0, 'x', makeId).blocks).toBe(blocks);
  });
});

describe('Block rendering', () => {
  test('Numbered list restarts: numbered, numbered, paragraph, numbered shows 1, 2, (paragraph), 1', () => {
    const blocks = [b('1', 'numbered'), b('2', 'numbered'), b('3', 'paragraph'), b('4', 'numbered')];
    expect(numberLabels(blocks)).toEqual([1, 2, null, 1]);
  });

  test('numbering restarts after any non-numbered type, including bulleted', () => {
    const blocks = [b('1', 'numbered'), b('2', 'bulleted'), b('3', 'numbered'), b('4', 'numbered')];
    expect(numberLabels(blocks)).toEqual([1, null, 1, 2]);
  });
});
