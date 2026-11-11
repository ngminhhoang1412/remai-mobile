// Page tree helpers: GET /pages returns a flat list (createdAt ascending) and clients build the
// tree from parentId (page-management "List the page tree").
import '../models/models.dart';

class TreeNode {
  TreeNode(this.page);

  final PageInfo page;
  final List<TreeNode> children = [];
}

class TreeRow {
  const TreeRow({required this.page, required this.depth, required this.hasChildren, required this.expanded});

  final PageInfo page;
  final int depth;
  final bool hasChildren;
  final bool expanded;
}

/// Builds the forest. Siblings are ordered oldest first. A page whose parent is not in the list
/// (shouldn't happen for live pages, but be defensive) is shown at the top level.
List<TreeNode> buildTree(List<PageInfo> pages) {
  // List.sort isn't guaranteed stable, so break ties on the server order explicitly.
  final indexed = [for (var i = 0; i < pages.length; i++) (i, pages[i])];
  indexed.sort((a, b) {
    final c = a.$2.createdAt.compareTo(b.$2.createdAt);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  final sorted = [for (final e in indexed) e.$2];

  final nodes = <String, TreeNode>{for (final p in sorted) p.id: TreeNode(p)};
  final roots = <TreeNode>[];
  for (final page in sorted) {
    final node = nodes[page.id]!;
    final parent = page.parentId == null ? null : nodes[page.parentId];
    if (parent != null && !identical(parent, node)) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

/// Depth-first rows for a list view; children are only included under expanded pages.
List<TreeRow> flattenVisible(List<TreeNode> roots, Set<String> expanded) {
  final rows = <TreeRow>[];
  final seen = <String>{};
  void visit(TreeNode node, int depth) {
    if (!seen.add(node.page.id)) return; // cycle guard
    final isExpanded = expanded.contains(node.page.id);
    rows.add(TreeRow(page: node.page, depth: depth, hasChildren: node.children.isNotEmpty, expanded: isExpanded));
    if (isExpanded) {
      for (final child in node.children) {
        visit(child, depth + 1);
      }
    }
  }

  for (final root in roots) {
    visit(root, 0);
  }
  return rows;
}

/// Ids of [id] and all of its descendants in a flat page list (used after trashing a subtree).
Set<String> subtreeIds(List<PageInfo> pages, String id) {
  final ids = {id};
  var grew = true;
  while (grew) {
    grew = false;
    for (final p in pages) {
      if (p.parentId != null && ids.contains(p.parentId) && !ids.contains(p.id)) {
        ids.add(p.id);
        grew = true;
      }
    }
  }
  return ids;
}
