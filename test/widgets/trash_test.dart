import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_backend.dart';

void main() {
  late FakeBackend backend;

  Future<void> openTrash(WidgetTester tester) async {
    await pumpApp(tester, backend, MemoryTokenStorage(validToken));
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    backend = FakeBackend()..addPage('live', title: 'Live page');
    backend.trash.add({'id': 'old', 'title': 'Old meeting notes', 'icon': '📌', 'trashedAt': '2026-01-01T00:00:00Z'});
  });

  testWidgets('Confirm before delete forever: Cancel keeps the page, confirming deletes it', (tester) async {
    await openTrash(tester);
    expect(find.text('Old meeting notes'), findsOneWidget);

    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    expect(find.text('Delete forever?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.requestsTo('DELETE', '/api/v1/trash/'), isEmpty);
    expect(find.text('Old meeting notes'), findsOneWidget);

    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-forever')));
    await tester.pumpAndSettle();
    expect(backend.requestsTo('DELETE', '/api/v1/trash/old'), hasLength(1));
    expect(find.text('Old meeting notes'), findsNothing);
    expect(find.text('Trash is empty'), findsOneWidget);
  });

  testWidgets('Restore a page: it leaves the trash and reappears in the page tree', (tester) async {
    await openTrash(tester);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(backend.requestsTo('POST', '/api/v1/trash/old/restore'), hasLength(1));
    expect(find.text('Trash is empty'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Old meeting notes'), findsOneWidget);
    expect(find.text('Live page'), findsOneWidget);
  });
}
