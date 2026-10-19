import { buildTree, flattenVisible, subtreeIds } from '../tree';
import { displayTitle, type Page } from '../types';

const page = (id: string, parentId: string | null, createdAt: string, title = id): Page => ({
  id,
  parentId,
  title,
  icon: '',
  createdAt,
  updatedAt: createdAt,
});

const A = page('A', null, '2026-01-01T00:00:00.000Z');
const B = page('B', 'A', '2026-01-02T00:00:00.000Z');
const C = page('C', null, '2026-01-03T00:00:00.000Z');
const D = page('D', 'B', '2026-01-04T00:00:00.000Z');

describe('List the page tree', () => {
  test('Tree listing: B is a child of A, and A comes before C', () => {
    const roots = buildTree([C, B, A]);
    expect(roots.map((n) => n.page.id)).toEqual(['A', 'C']);
    expect(roots[0].children.map((n) => n.page.id)).toEqual(['B']);
  });

  test('a page whose parent is missing is shown at the top level', () => {
    const orphan = page('O', 'gone', '2026-01-05T00:00:00.000Z');
    expect(buildTree([A, orphan]).map((n) => n.page.id)).toEqual(['A', 'O']);
  });
});

describe('Home tree with expand/collapse', () => {
  test('collapsed pages hide their children', () => {
    const rows = flattenVisible(buildTree([A, B, C, D]), new Set());
    expect(rows.map((r) => [r.page.id, r.depth, r.hasChildren, r.expanded])).toEqual([
      ['A', 0, true, false],
      ['C', 0, false, false],
    ]);
  });

  test('Drill into a subpage: expanding A shows child B indented under it', () => {
    const rows = flattenVisible(buildTree([A, B, C, D]), new Set(['A']));
    expect(rows.map((r) => [r.page.id, r.depth])).toEqual([
      ['A', 0],
      ['B', 1],
      ['C', 0],
    ]);
  });

  test('nested expansion shows grandchildren at depth 2', () => {
    const rows = flattenVisible(buildTree([A, B, C, D]), new Set(['A', 'B']));
    expect(rows.map((r) => [r.page.id, r.depth])).toEqual([
      ['A', 0],
      ['B', 1],
      ['D', 2],
      ['C', 0],
    ]);
  });

  test('expanding a collapsed ancestor only: descendants of a collapsed child stay hidden', () => {
    const rows = flattenVisible(buildTree([A, B, C, D]), new Set(['B']));
    expect(rows.map((r) => r.page.id)).toEqual(['A', 'C']);
  });
});

describe('Trashed pages hidden (client cache)', () => {
  test('trashing A removes A and all its descendants', () => {
    expect([...subtreeIds([A, B, C, D], 'A')].sort()).toEqual(['A', 'B', 'D']);
  });
});

describe('Untitled display', () => {
  test('an empty title shows as "Untitled"', () => {
    expect(displayTitle('')).toBe('Untitled');
    expect(displayTitle('   ')).toBe('Untitled');
    expect(displayTitle('Roadmap')).toBe('Roadmap');
  });
});
