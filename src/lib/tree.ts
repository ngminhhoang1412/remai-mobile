// Page tree helpers: GET /pages returns a flat list (createdAt ascending) and clients build the
// tree from parentId (page-management "List the page tree").
import type { Page } from './types';

export interface TreeNode {
  page: Page;
  children: TreeNode[];
}

export interface TreeRow {
  page: Page;
  depth: number;
  hasChildren: boolean;
  expanded: boolean;
}

function byCreatedAt(a: Page, b: Page): number {
  if (a.createdAt < b.createdAt) return -1;
  if (a.createdAt > b.createdAt) return 1;
  return 0;
}

/**
 * Builds the forest. Siblings are ordered oldest first. A page whose parent is not in the list
 * (shouldn't happen for live pages, but be defensive) is shown at the top level.
 */
export function buildTree(pages: readonly Page[]): TreeNode[] {
  const sorted = pages.slice().sort(byCreatedAt); // Array#sort is stable: equal timestamps keep server order.
  const nodes = new Map<string, TreeNode>();
  for (const page of sorted) nodes.set(page.id, { page, children: [] });

  const roots: TreeNode[] = [];
  for (const page of sorted) {
    const node = nodes.get(page.id)!;
    const parent = page.parentId ? nodes.get(page.parentId) : undefined;
    if (parent && parent !== node) parent.children.push(node);
    else roots.push(node);
  }
  return roots;
}

/** Depth-first rows for a list view; children are only included under expanded pages. */
export function flattenVisible(roots: readonly TreeNode[], expanded: ReadonlySet<string>): TreeRow[] {
  const rows: TreeRow[] = [];
  const visit = (node: TreeNode, depth: number, seen: Set<string>) => {
    if (seen.has(node.page.id)) return; // cycle guard
    seen.add(node.page.id);
    const isExpanded = expanded.has(node.page.id);
    rows.push({ page: node.page, depth, hasChildren: node.children.length > 0, expanded: isExpanded });
    if (isExpanded) for (const child of node.children) visit(child, depth + 1, seen);
  };
  const seen = new Set<string>();
  for (const root of roots) visit(root, 0, seen);
  return rows;
}

/** Ids of `id` and all of its descendants in a flat page list (used after trashing a subtree). */
export function subtreeIds(pages: readonly Page[], id: string): Set<string> {
  const ids = new Set<string>([id]);
  let grew = true;
  while (grew) {
    grew = false;
    for (const p of pages) {
      if (p.parentId && ids.has(p.parentId) && !ids.has(p.id)) {
        ids.add(p.id);
        grew = true;
      }
    }
  }
  return ids;
}
