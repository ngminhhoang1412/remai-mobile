// Autosave protocol (add-notion-core design D10), shared by the block list and the page title/icon:
// - edits update local state immediately and call update(); a save starts 800 ms after the last edit
// - only one save is in flight; edits made meanwhile mark the value dirty and another save follows
// - a failed save shows "Couldn't save – retrying" and retries with backoff 2 s → 4 s → … → 30 s,
//   always sending the latest value
// - a non-retryable failure (the caller decides, e.g. 400/401/404/413) shows "Couldn't save" and
//   stops retrying until the next edit
// - flush() saves anything pending right away (leaving the page, app going to the background)
import 'dart:async';

enum SaveStatus { idle, pending, saving, saved, error, failed }

typedef SaveFn<T> = Future<void> Function(T value);

class AutosaveController<T> {
  AutosaveController({
    required SaveFn<T> save,
    this.debounce = const Duration(milliseconds: 800),
    this.retryInitial = const Duration(seconds: 2),
    this.retryMax = const Duration(seconds: 30),
    bool Function(Object error)? isRetryable,
    this.onStatusChange,
  })  : _save = save,
        _isRetryable = isRetryable ?? ((_) => true),
        _retryDelay = retryInitial;

  final SaveFn<T> _save;
  final bool Function(Object error) _isRetryable;
  final Duration debounce;
  final Duration retryInitial;
  final Duration retryMax;
  final void Function(SaveStatus status)? onStatusChange;

  T? _latest;
  bool _dirty = false;
  Future<void>? _inFlight;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  Duration _retryDelay;
  bool _disposed = false;
  SaveStatus _status = SaveStatus.idle;

  SaveStatus get status => _status;

  /// True while there is an unsaved value or a save in flight.
  bool get hasPendingChanges => _dirty || _inFlight != null;

  bool get _failedState => _status == SaveStatus.error || _status == SaveStatus.failed;

  /// Records the latest value and (re)starts the debounce.
  void update(T value) {
    if (_disposed) return;
    _latest = value;
    _dirty = true;
    // While a retry is scheduled it will pick up this newest value; keep the failure visible.
    if (_retryTimer != null) return;
    _clearDebounce();
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(_run());
    });
    if (_inFlight == null) _setStatus(SaveStatus.pending);
  }

  /// Saves pending changes now and completes once they are saved (or the attempt failed).
  Future<void> flush() async {
    _clearDebounce();
    _clearRetry();
    while (!_disposed) {
      final inFlight = _inFlight;
      if (inFlight != null) {
        await inFlight;
        if (_failedState) return;
        continue;
      }
      if (!_dirty) return;
      await _run();
      if (_failedState) return;
    }
  }

  /// Stops timers and ignores any in-flight result. Call after a final flush().
  void dispose() {
    _disposed = true;
    _clearDebounce();
    _clearRetry();
  }

  Future<void> _run() {
    if (_disposed) return Future.value();
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight; // the completion handler re-saves if still dirty
    if (!_dirty) return Future.value();

    _clearRetry();
    final value = _latest as T;
    _dirty = false;
    _setStatus(SaveStatus.saving);

    final attempt = Future<void>.sync(() => _save(value)).then<void>(
      (_) => _onSaved(),
      onError: (Object e) => _onFailed(e),
    );
    _inFlight = attempt;
    return attempt;
  }

  void _onSaved() {
    _inFlight = null;
    _retryDelay = retryInitial;
    if (_disposed) return;
    if (!_dirty) {
      _setStatus(SaveStatus.saved);
    } else if (_debounceTimer != null) {
      _setStatus(SaveStatus.pending); // the running debounce will save the newer edits
    } else {
      unawaited(_run());
    }
  }

  void _onFailed(Object error) {
    _inFlight = null;
    if (_disposed) return;
    _dirty = true; // the value we tried (or a newer one) still needs saving
    _clearDebounce();
    if (!_isRetryable(error)) {
      // Retrying the same request can't succeed. The next edit starts a fresh attempt.
      _retryDelay = retryInitial;
      _setStatus(SaveStatus.failed);
      return;
    }
    _setStatus(SaveStatus.error);
    final delay = _retryDelay;
    final doubled = _retryDelay * 2;
    _retryDelay = doubled > retryMax ? retryMax : doubled;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_run());
    });
  }

  void _clearDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _clearRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _setStatus(SaveStatus status) {
    if (_status == status) return;
    _status = status;
    onStatusChange?.call(status);
  }
}

const Map<SaveStatus, int> _priority = {
  SaveStatus.idle: 0,
  SaveStatus.saved: 1,
  SaveStatus.pending: 2,
  SaveStatus.saving: 3,
  SaveStatus.error: 4,
  SaveStatus.failed: 5,
};

/// One indicator for several controllers (blocks + title): the "worst" state wins.
SaveStatus combineStatus(Iterable<SaveStatus> statuses) =>
    statuses.fold(SaveStatus.idle, (acc, s) => _priority[s]! > _priority[acc]! ? s : acc);

String statusLabel(SaveStatus status) => switch (status) {
      SaveStatus.pending || SaveStatus.saving => 'Saving…',
      SaveStatus.saved => 'Saved',
      SaveStatus.error => 'Couldn’t save – retrying',
      SaveStatus.failed => 'Couldn’t save',
      SaveStatus.idle => '',
    };
