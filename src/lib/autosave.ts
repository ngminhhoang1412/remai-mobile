// Autosave protocol (design.md D10), shared by the block list and the page title/icon:
// - edits update local state immediately and call update(); a save starts 800 ms after the last edit
// - only one save is in flight; edits made meanwhile mark the value dirty and another save follows
// - a failed save shows "Couldn't save – retrying" and retries with backoff 2 s → 4 s → … → 30 s,
//   always sending the latest value
// - flush() saves anything pending right away (leaving the screen, app going to background)

export type SaveStatus = 'idle' | 'pending' | 'saving' | 'saved' | 'error';

export interface AutosaveOptions<T> {
  save: (value: T) => Promise<unknown>;
  debounceMs?: number;
  retryInitialMs?: number;
  retryMaxMs?: number;
  onStatusChange?: (status: SaveStatus) => void;
}

type Timer = ReturnType<typeof setTimeout>;

export class AutosaveController<T> {
  private readonly saveFn: (value: T) => Promise<unknown>;
  private readonly debounceMs: number;
  private readonly retryInitialMs: number;
  private readonly retryMaxMs: number;
  private readonly onStatusChange?: (status: SaveStatus) => void;

  private latest: T | undefined;
  private dirty = false;
  private inFlight: Promise<void> | null = null;
  private debounceTimer: Timer | null = null;
  private retryTimer: Timer | null = null;
  private retryDelay: number;
  private disposed = false;
  private currentStatus: SaveStatus = 'idle';

  constructor(opts: AutosaveOptions<T>) {
    this.saveFn = opts.save;
    this.debounceMs = opts.debounceMs ?? 800;
    this.retryInitialMs = opts.retryInitialMs ?? 2000;
    this.retryMaxMs = opts.retryMaxMs ?? 30000;
    this.onStatusChange = opts.onStatusChange;
    this.retryDelay = this.retryInitialMs;
  }

  get status(): SaveStatus {
    return this.currentStatus;
  }

  /** True while there is an unsaved value or a save in flight. */
  get hasPendingChanges(): boolean {
    return this.dirty || this.inFlight !== null;
  }

  /** Records the latest value and (re)starts the debounce. */
  update(value: T): void {
    if (this.disposed) return;
    this.latest = value;
    this.dirty = true;
    // While a retry is scheduled it will pick up this newest value; keep the failure visible.
    if (this.retryTimer) return;
    this.clearDebounce();
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.run();
    }, this.debounceMs);
    if (!this.inFlight) this.setStatus('pending');
  }

  /** Saves pending changes now and resolves once they are saved (or the attempt failed). */
  async flush(): Promise<void> {
    this.clearDebounce();
    this.clearRetry();
    while (!this.disposed) {
      if (this.inFlight) {
        await this.inFlight;
        if (this.currentStatus === 'error') return;
        continue;
      }
      if (!this.dirty) return;
      await this.run();
      if (this.currentStatus === 'error') return;
    }
  }

  /** Stops timers and ignores any in-flight result. Call after a final flush(). */
  dispose(): void {
    this.disposed = true;
    this.clearDebounce();
    this.clearRetry();
  }

  private run(): Promise<void> {
    if (this.disposed) return Promise.resolve();
    if (this.inFlight) return this.inFlight; // the completion handler re-saves if still dirty
    if (!this.dirty) return Promise.resolve();

    this.clearRetry();
    const value = this.latest as T;
    this.dirty = false;
    this.setStatus('saving');

    const attempt = Promise.resolve()
      .then(() => this.saveFn(value))
      .then(
        () => this.onSaved(),
        () => this.onFailed(),
      );
    this.inFlight = attempt;
    return attempt;
  }

  private onSaved(): void {
    this.inFlight = null;
    this.retryDelay = this.retryInitialMs;
    if (this.disposed) return;
    if (!this.dirty) {
      this.setStatus('saved');
    } else if (this.debounceTimer) {
      this.setStatus('pending'); // the running debounce will save the newer edits
    } else {
      void this.run();
    }
  }

  private onFailed(): void {
    this.inFlight = null;
    if (this.disposed) return;
    this.dirty = true; // the value we tried (or a newer one) still needs saving
    this.clearDebounce();
    this.setStatus('error');
    const delay = this.retryDelay;
    this.retryDelay = Math.min(this.retryDelay * 2, this.retryMaxMs);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.run();
    }, delay);
  }

  private clearDebounce(): void {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = null;
  }

  private clearRetry(): void {
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
  }

  private setStatus(status: SaveStatus): void {
    if (this.currentStatus === status) return;
    this.currentStatus = status;
    this.onStatusChange?.(status);
  }
}

const PRIORITY: Record<SaveStatus, number> = { idle: 0, saved: 1, pending: 2, saving: 3, error: 4 };

/** One indicator for several controllers (blocks + title): the "worst" state wins. */
export function combineStatus(...statuses: SaveStatus[]): SaveStatus {
  return statuses.reduce<SaveStatus>((acc, s) => (PRIORITY[s] > PRIORITY[acc] ? s : acc), 'idle');
}

export function statusLabel(status: SaveStatus): string {
  switch (status) {
    case 'pending':
    case 'saving':
      return 'Saving…';
    case 'saved':
      return 'Saved';
    case 'error':
      return 'Couldn’t save – retrying';
    default:
      return '';
  }
}
