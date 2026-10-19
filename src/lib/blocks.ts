// Pure block-editing rules (page-content "Block rendering" + web-client "Keyboard block editing",
// which the mobile-client spec reuses for return/backspace). No React / native imports here so the
// rules are unit-testable; callers inject the id generator.
import type { Block, BlockType } from './types';

export type MakeId = () => string;

export const BLOCK_TYPES: readonly { type: BlockType; label: string }[] = [
  { type: 'paragraph', label: 'Text' },
  { type: 'heading1', label: 'Heading 1' },
  { type: 'heading2', label: 'Heading 2' },
  { type: 'heading3', label: 'Heading 3' },
  { type: 'todo', label: 'To-do' },
  { type: 'bulleted', label: 'Bulleted list' },
  { type: 'numbered', label: 'Numbered list' },
  { type: 'quote', label: 'Quote' },
  { type: 'code', label: 'Code' },
  { type: 'divider', label: 'Divider' },
];

/** Types whose "next block" keeps the same type on return. */
const LIST_TYPES: ReadonlySet<BlockType> = new Set<BlockType>(['todo', 'bulleted', 'numbered']);

export function isListType(type: BlockType): boolean {
  return LIST_TYPES.has(type);
}

export function createBlock(makeId: MakeId, type: BlockType = 'paragraph', text = ''): Block {
  return { id: makeId(), type, text: type === 'divider' ? '' : text, checked: false };
}

/** Where the editor should put the caret after an edit. */
export interface FocusTarget {
  id: string;
  /** Put the caret at the end of the block's text. */
  atEnd: boolean;
}

export interface EditResult {
  blocks: Block[];
  focus: FocusTarget | null;
}

/**
 * True when `next` is `prev` with a return typed at the very end. Multiline TextInputs insert
 * "\n" on return on both iOS and Android and always report it through onChangeText, so this is
 * how "return at the end of a block" is detected. The text before the newline may differ from
 * `prev` (keyboard autocorrect commits the current word together with the return key).
 * A newline typed in the middle of the text is kept as a line break inside the block.
 */
export function isReturnAtEnd(prev: string, next: string): boolean {
  if (next.length <= prev.length || !next.endsWith('\n')) return false;
  // If the old text already ended with a newline, only an append counts as "at the end".
  if (prev.endsWith('\n')) return next.startsWith(prev);
  return true;
}

function replaceAt(blocks: Block[], index: number, block: Block): Block[] {
  const copy = blocks.slice();
  copy[index] = block;
  return copy;
}

/**
 * Return at the end of block `index` (its text already has the newline removed):
 * - empty to-do / bulleted / numbered → becomes a paragraph (leave the list)
 * - otherwise a new block is inserted below and focused; it keeps the type for
 *   to-do / bulleted / numbered and is a paragraph for every other type.
 */
export function applyReturn(blocks: Block[], index: number, makeId: MakeId): EditResult {
  const block = blocks[index];
  if (!block) return { blocks, focus: null };
  if (isListType(block.type) && block.text === '') {
    return {
      blocks: replaceAt(blocks, index, { ...block, type: 'paragraph', checked: false }),
      focus: { id: block.id, atEnd: true },
    };
  }
  const next = createBlock(makeId, isListType(block.type) ? block.type : 'paragraph');
  const copy = blocks.slice();
  copy.splice(index + 1, 0, next);
  return { blocks: copy, focus: { id: next.id, atEnd: false } };
}

/** onChangeText handler: plain text update, or the return rules when a return was typed at the end. */
export function applyTextChange(blocks: Block[], index: number, nextText: string, makeId: MakeId): EditResult {
  const block = blocks[index];
  if (!block || block.type === 'divider') return { blocks, focus: null };
  if (isReturnAtEnd(block.text, nextText)) {
    const withText = replaceAt(blocks, index, { ...block, text: nextText.slice(0, -1) });
    return applyReturn(withText, index, makeId);
  }
  if (nextText === block.text) return { blocks, focus: null };
  return { blocks: replaceAt(blocks, index, { ...block, text: nextText }), focus: null };
}

/**
 * Backspace in an empty block removes it and moves the caret to the end of the previous
 * (editable) block. Returns null when nothing should happen: the block isn't empty, or it is
 * the first block.
 */
export function applyBackspaceOnEmpty(blocks: Block[], index: number): EditResult | null {
  const block = blocks[index];
  if (!block || block.text !== '' || index === 0) return null;
  const copy = blocks.slice();
  copy.splice(index, 1);
  for (let i = index - 1; i >= 0; i--) {
    if (copy[i].type !== 'divider') return { blocks: copy, focus: { id: copy[i].id, atEnd: true } };
  }
  return { blocks: copy, focus: null };
}

/**
 * "Turn into": changes the block's type and keeps its text. `checked` survives only on to-do.
 * Dividers carry no text, so turning an empty block into a divider converts it and moves focus to
 * the next editable block (adding a paragraph when there is none); turning a block that has text
 * into a divider inserts the divider above it instead, so no text is lost.
 */
export function turnInto(blocks: Block[], index: number, type: BlockType, makeId: MakeId): EditResult {
  const block = blocks[index];
  if (!block) return { blocks, focus: null };
  if (type !== 'divider') {
    const changed: Block = { ...block, type, checked: type === 'todo' ? block.checked : false };
    return { blocks: replaceAt(blocks, index, changed), focus: { id: block.id, atEnd: true } };
  }
  if (block.text !== '') {
    const copy = blocks.slice();
    copy.splice(index, 0, createBlock(makeId, 'divider'));
    return { blocks: copy, focus: { id: block.id, atEnd: true } };
  }
  const copy = replaceAt(blocks, index, { ...block, type: 'divider', text: '', checked: false });
  for (let i = index + 1; i < copy.length; i++) {
    if (copy[i].type !== 'divider') return { blocks: copy, focus: { id: copy[i].id, atEnd: false } };
  }
  const para = createBlock(makeId);
  copy.push(para);
  return { blocks: copy, focus: { id: para.id, atEnd: false } };
}

export function toggleTodo(blocks: Block[], index: number): Block[] {
  const block = blocks[index];
  if (!block || block.type !== 'todo') return blocks;
  return replaceAt(blocks, index, { ...block, checked: !block.checked });
}

export function removeBlock(blocks: Block[], index: number): Block[] {
  if (index < 0 || index >= blocks.length) return blocks;
  const copy = blocks.slice();
  copy.splice(index, 1);
  return copy;
}

/**
 * Tapping the empty area below the last block: focus a new paragraph at the end. If the last
 * block already is an empty paragraph it is focused instead of stacking another empty one.
 */
export function appendParagraph(blocks: Block[], makeId: MakeId): EditResult {
  const last = blocks[blocks.length - 1];
  if (last && last.type === 'paragraph' && last.text === '') {
    return { blocks, focus: { id: last.id, atEnd: true } };
  }
  const para = createBlock(makeId);
  return { blocks: [...blocks, para], focus: { id: para.id, atEnd: false } };
}

/**
 * Display numbers for numbered blocks: a running count that restarts at 1 after any
 * non-numbered block. Non-numbered blocks get null.
 */
export function numberLabels(blocks: readonly Block[]): (number | null)[] {
  let n = 0;
  return blocks.map((b) => {
    if (b.type !== 'numbered') {
      n = 0;
      return null;
    }
    n += 1;
    return n;
  });
}

export function placeholderFor(type: BlockType): string {
  switch (type) {
    case 'heading1':
      return 'Heading 1';
    case 'heading2':
      return 'Heading 2';
    case 'heading3':
      return 'Heading 3';
    case 'todo':
      return 'To-do';
    case 'bulleted':
    case 'numbered':
      return 'List';
    case 'quote':
      return 'Quote';
    case 'code':
      return 'Code';
    default:
      return 'Type something…';
  }
}
