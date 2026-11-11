import 'package:flutter_test/flutter_test.dart';
import 'package:remai/logic/format.dart';
import 'package:remai/logic/tree.dart';
import 'package:remai/models/models.dart';

PageInfo page(String id, String? parentId, String createdAt, [String? title]) => PageInfo(
      id: id,
      parentId: parentId,
      title: title ?? id,
      icon: '',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

void main() {
  final a = page('A', null, '2026-01-01T00:00:00.000Z');
  final b = page('B', 'A', '2026-01-02T00:00:00.000Z');
  final c = page('C', null, '2026-01-03T00:00:00.000Z');
  final d = page('D', 'B', '2026-01-04T00:00:00.000Z');

  group('List the page tree', () {
    test('Tree listing: B is a child of A, and A comes before C', () {
      final roots = buildTree([c, b, a]);
      expect(roots.map((n) => n.page.id), ['A', 'C']);
      expect(roots[0].children.map((n) => n.page.id), ['B']);
    });

    test('a page whose parent is missing is shown at the top level', () {
      final orphan = page('O', 'gone', '2026-01-05T00:00:00.000Z');
      expect(buildTree([a, orphan]).map((n) => n.page.id), ['A', 'O']);
    });

    test('pages with equal timestamps keep the server order', () {
      final x = page('X', null, '2026-01-01T00:00:00.000Z');
      final y = page('Y', null, '2026-01-01T00:00:00.000Z');
      expect(buildTree([y, x]).map((n) => n.page.id), ['Y', 'X']);
    });
  });

  group('Home tree with expand/collapse', () {
    test('collapsed pages hide their children', () {
      final rows = flattenVisible(buildTree([a, b, c, d]), {});
      expect(rows.map((r) => (r.page.id, r.depth, r.hasChildren, r.expanded)), [
        ('A', 0, true, false),
        ('C', 0, false, false),
      ]);
    });

    test('Drill into a subpage: expanding A shows child B indented under it', () {
      final rows = flattenVisible(buildTree([a, b, c, d]), {'A'});
      expect(rows.map((r) => (r.page.id, r.depth)), [('A', 0), ('B', 1), ('C', 0)]);
    });

    test('nested expansion shows grandchildren at depth 2', () {
      final rows = flattenVisible(buildTree([a, b, c, d]), {'A', 'B'});
      expect(rows.map((r) => (r.page.id, r.depth)), [('A', 0), ('B', 1), ('D', 2), ('C', 0)]);
    });

    test('descendants of a collapsed page stay hidden even if they are expanded', () {
      final rows = flattenVisible(buildTree([a, b, c, d]), {'B'});
      expect(rows.map((r) => r.page.id), ['A', 'C']);
    });
  });

  group('Trashed pages hidden (client cache)', () {
    test('trashing A removes A and all its descendants', () {
      expect(subtreeIds([a, b, c, d], 'A'), {'A', 'B', 'D'});
    });
  });

  group('Untitled display', () {
    test('an empty title shows as "Untitled"', () {
      expect(displayTitle(''), 'Untitled');
      expect(displayTitle('   '), 'Untitled');
      expect(displayTitle('Roadmap'), 'Roadmap');
    });
  });

  group('Trash row time', () {
    final now = DateTime.utc(2026, 10, 19, 12);
    test('relative times', () {
      expect(relativeTime('2026-10-19T11:59:30Z', now), 'just now');
      expect(relativeTime('2026-10-19T11:45:00Z', now), '15 min ago');
      expect(relativeTime('2026-10-19T10:00:00Z', now), '2 h ago');
      expect(relativeTime('2026-10-16T12:00:00Z', now), '3 d ago');
      expect(relativeTime('not a date', now), '');
    });
  });
}
