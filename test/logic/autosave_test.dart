import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remai/api/api_client.dart';
import 'package:remai/logic/autosave.dart';

class _Harness {
  _Harness() {
    ctrl = AutosaveController<String>(
      save: (value) {
        saved.add(value);
        final c = Completer<void>();
        pending.add(c);
        return c.future;
      },
      isRetryable: isRetryableSaveError,
      onStatusChange: statuses.add,
    );
  }

  late final AutosaveController<String> ctrl;
  final saved = <String>[];
  final pending = <Completer<void>>[];
  final statuses = <SaveStatus>[];
}

const ms = Duration(milliseconds: 1);

void main() {
  group('Autosave', () {
    test('Edit then pause: content is saved 800 ms after the last edit and shows "Saved"', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('a');
        async.elapse(ms * 500);
        h.ctrl.update('ab');
        async.elapse(ms * 799);
        expect(h.saved, isEmpty);
        expect(h.ctrl.status, SaveStatus.pending);
        expect(statusLabel(h.ctrl.status), 'Saving…');
        async.elapse(ms);
        expect(h.saved, ['ab']);
        expect(h.ctrl.status, SaveStatus.saving);
        h.pending[0].complete();
        async.flushMicrotasks();
        expect(h.ctrl.status, SaveStatus.saved);
        expect(statusLabel(h.ctrl.status), 'Saved');
        h.ctrl.dispose();
      });
    });

    test('only one save is in flight; edits made during it trigger one more save with the latest value', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('v1');
        async.elapse(ms * 800);
        expect(h.saved, ['v1']);

        h.ctrl.update('v2');
        h.ctrl.update('v3');
        async.elapse(const Duration(seconds: 5)); // debounce fires while v1 is still in flight
        expect(h.saved, ['v1']);

        h.pending[0].complete();
        async.flushMicrotasks();
        expect(h.saved, ['v1', 'v3']);
        h.pending[1].complete();
        async.flushMicrotasks();
        expect(h.saved, hasLength(2));
        expect(h.ctrl.status, SaveStatus.saved);
        h.ctrl.dispose();
      });
    });

    test('Save failure surfaced: a failed save shows the error state and retries with backoff 2s, 4s … up to 30s', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('x');
        async.elapse(ms * 800);
        h.pending[0].completeError(const ApiException(0, 'network_error', 'offline'));
        async.flushMicrotasks();
        expect(h.ctrl.status, SaveStatus.error);
        expect(statusLabel(h.ctrl.status), 'Couldn’t save – retrying');

        const expectedSeconds = [2, 4, 8, 16, 30, 30];
        for (final seconds in expectedSeconds) {
          final calls = h.saved.length;
          async.elapse(Duration(seconds: seconds) - ms);
          expect(h.saved, hasLength(calls), reason: 'no retry before ${seconds}s');
          async.elapse(ms);
          expect(h.saved, hasLength(calls + 1), reason: 'retry after ${seconds}s');
          h.pending.last.completeError(const ApiException(503, 'http_error', 'down'));
          async.flushMicrotasks();
          expect(h.ctrl.status, SaveStatus.error);
        }
        h.ctrl.dispose();
      });
    });

    test('a retry sends the newest edits and recovers to "Saved"', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('old');
        async.elapse(ms * 800);
        h.pending[0].completeError(const ApiException(0, 'network_error', 'offline'));
        async.flushMicrotasks();
        h.ctrl.update('new'); // the user keeps typing; edits stay on screen
        expect(h.ctrl.status, SaveStatus.error);
        async.elapse(const Duration(seconds: 2));
        expect(h.saved, ['old', 'new']);
        h.pending[1].complete();
        async.flushMicrotasks();
        expect(h.ctrl.status, SaveStatus.saved);
        h.ctrl.dispose();
      });
    });

    test('429 (slow down, non-envelope body) is retried with backoff', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('x');
        async.elapse(ms * 800);
        h.pending[0].completeError(const ApiException(429, 'rate_limited', 'slow down'));
        async.flushMicrotasks();
        expect(h.ctrl.status, SaveStatus.error);
        async.elapse(const Duration(seconds: 2));
        expect(h.saved, ['x', 'x']);
        h.ctrl.dispose();
      });
    });

    for (final status in [400, 401, 404, 413]) {
      test('a $status response is not retried and shows "Couldn’t save" until the next edit', () {
        fakeAsync((async) {
          final h = _Harness();
          h.ctrl.update('x');
          async.elapse(ms * 800);
          h.pending[0].completeError(ApiException(status, 'validation_error', 'bad'));
          async.flushMicrotasks();
          expect(h.ctrl.status, SaveStatus.failed);
          expect(statusLabel(h.ctrl.status), 'Couldn’t save');
          async.elapse(const Duration(minutes: 5));
          expect(h.saved, ['x']);

          h.ctrl.update('fixed');
          expect(h.ctrl.status, SaveStatus.pending);
          async.elapse(ms * 800);
          expect(h.saved, ['x', 'fixed']);
          h.pending[1].complete();
          async.flushMicrotasks();
          expect(h.ctrl.status, SaveStatus.saved);
          h.ctrl.dispose();
        });
      });
    }

    test('leaving the page flushes a pending save immediately', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('draft');
        var done = false;
        unawaited(h.ctrl.flush().then((_) => done = true));
        async.flushMicrotasks();
        expect(h.saved, ['draft']);
        h.pending[0].complete();
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(h.ctrl.status, SaveStatus.saved);
        expect(h.ctrl.hasPendingChanges, isFalse);
        h.ctrl.dispose();
      });
    });

    test('flush waits for the in-flight save, then saves newer edits', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('one');
        async.elapse(ms * 800);
        h.ctrl.update('two');
        var done = false;
        unawaited(h.ctrl.flush().then((_) => done = true));
        h.pending[0].complete();
        async.flushMicrotasks();
        expect(h.saved, ['one', 'two']);
        expect(done, isFalse);
        h.pending[1].complete();
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(h.ctrl.status, SaveStatus.saved);
        h.ctrl.dispose();
      });
    });

    test('flush with nothing pending does not save', () {
      fakeAsync((async) {
        final h = _Harness();
        var done = false;
        unawaited(h.ctrl.flush().then((_) => done = true));
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(h.saved, isEmpty);
        expect(h.ctrl.status, SaveStatus.idle);
      });
    });

    test('dispose cancels scheduled saves', () {
      fakeAsync((async) {
        final h = _Harness();
        h.ctrl.update('x');
        h.ctrl.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(h.saved, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('combined indicator: failed beats error beats saving beats saved', () {
      expect(combineStatus([SaveStatus.error, SaveStatus.failed]), SaveStatus.failed);
      expect(combineStatus([SaveStatus.saved, SaveStatus.error]), SaveStatus.error);
      expect(combineStatus([SaveStatus.saving, SaveStatus.saved]), SaveStatus.saving);
      expect(combineStatus([SaveStatus.idle, SaveStatus.saved]), SaveStatus.saved);
      expect(combineStatus([SaveStatus.idle, SaveStatus.idle]), SaveStatus.idle);
    });
  });
}
