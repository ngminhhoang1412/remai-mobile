import { AutosaveController, combineStatus, statusLabel, type SaveStatus } from '../autosave';

interface Deferred {
  resolve: () => void;
  reject: (e: Error) => void;
}

const controllers: AutosaveController<string>[] = [];

function setup() {
  const saved: string[] = [];
  const pending: Deferred[] = [];
  const statuses: SaveStatus[] = [];
  const save = jest.fn(
    (value: string) =>
      new Promise<void>((resolve, reject) => {
        saved.push(value);
        pending.push({ resolve, reject });
      }),
  );
  const ctrl = new AutosaveController<string>({ save, onStatusChange: (s) => statuses.push(s) });
  controllers.push(ctrl);
  return { ctrl, save, saved, pending, statuses };
}

beforeEach(() => {
  jest.useFakeTimers();
});

afterEach(() => {
  controllers.splice(0).forEach((c) => c.dispose());
  jest.useRealTimers();
});

describe('Autosave', () => {
  test('Edit then pause: content is saved 800 ms after the last edit and shows "Saved"', async () => {
    const { ctrl, save, saved, pending } = setup();
    ctrl.update('a');
    await jest.advanceTimersByTimeAsync(500);
    ctrl.update('ab');
    await jest.advanceTimersByTimeAsync(799);
    expect(save).not.toHaveBeenCalled();
    expect(ctrl.status).toBe('pending');
    await jest.advanceTimersByTimeAsync(1);
    expect(saved).toEqual(['ab']);
    expect(ctrl.status).toBe('saving');
    pending[0].resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(ctrl.status).toBe('saved');
    expect(statusLabel(ctrl.status)).toBe('Saved');
  });

  test('only one save is in flight; edits made during it trigger one more save with the latest value', async () => {
    const { ctrl, save, saved, pending } = setup();
    ctrl.update('v1');
    await jest.advanceTimersByTimeAsync(800);
    expect(save).toHaveBeenCalledTimes(1);

    ctrl.update('v2');
    ctrl.update('v3');
    await jest.advanceTimersByTimeAsync(5000); // debounce fires while v1 is still in flight
    expect(save).toHaveBeenCalledTimes(1);

    pending[0].resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(saved).toEqual(['v1', 'v3']);
    pending[1].resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(save).toHaveBeenCalledTimes(2);
    expect(ctrl.status).toBe('saved');
  });

  test('Save failure surfaced: a failed save shows the error state and retries with backoff 2s, 4s … up to 30s', async () => {
    const { ctrl, save, pending } = setup();
    ctrl.update('x');
    await jest.advanceTimersByTimeAsync(800);
    pending[0].reject(new Error('network down'));
    await jest.advanceTimersByTimeAsync(0);
    expect(ctrl.status).toBe('error');
    expect(statusLabel(ctrl.status)).toBe('Couldn’t save – retrying');

    const expectedDelays = [2000, 4000, 8000, 16000, 30000, 30000];
    for (let i = 0; i < expectedDelays.length; i++) {
      const calls = save.mock.calls.length;
      await jest.advanceTimersByTimeAsync(expectedDelays[i] - 1);
      expect(save).toHaveBeenCalledTimes(calls);
      await jest.advanceTimersByTimeAsync(1);
      expect(save).toHaveBeenCalledTimes(calls + 1);
      pending[pending.length - 1].reject(new Error('still down'));
      await jest.advanceTimersByTimeAsync(0);
      expect(ctrl.status).toBe('error');
    }
  });

  test('a retry sends the newest edits and recovers to "Saved"', async () => {
    const { ctrl, saved, pending } = setup();
    ctrl.update('old');
    await jest.advanceTimersByTimeAsync(800);
    pending[0].reject(new Error('offline'));
    await jest.advanceTimersByTimeAsync(0);
    ctrl.update('new'); // user keeps typing; edits stay on screen
    expect(ctrl.status).toBe('error');
    await jest.advanceTimersByTimeAsync(2000);
    expect(saved).toEqual(['old', 'new']);
    pending[1].resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(ctrl.status).toBe('saved');
  });

  test('leaving the page flushes a pending save immediately', async () => {
    const { ctrl, saved, pending } = setup();
    ctrl.update('draft');
    const flushed = ctrl.flush();
    await jest.advanceTimersByTimeAsync(0);
    expect(saved).toEqual(['draft']);
    pending[0].resolve();
    await flushed;
    expect(ctrl.status).toBe('saved');
    expect(ctrl.hasPendingChanges).toBe(false);
  });

  test('flush waits for the in-flight save, then saves newer edits', async () => {
    const { ctrl, saved, pending } = setup();
    ctrl.update('one');
    await jest.advanceTimersByTimeAsync(800);
    ctrl.update('two');
    const flushed = ctrl.flush();
    pending[0].resolve();
    await jest.advanceTimersByTimeAsync(0);
    expect(saved).toEqual(['one', 'two']);
    pending[1].resolve();
    await flushed;
    expect(ctrl.status).toBe('saved');
  });

  test('flush with nothing pending does not save', async () => {
    const { ctrl, save } = setup();
    await ctrl.flush();
    expect(save).not.toHaveBeenCalled();
    expect(ctrl.status).toBe('idle');
  });

  test('dispose cancels scheduled saves', async () => {
    const { ctrl, save } = setup();
    ctrl.update('x');
    ctrl.dispose();
    await jest.advanceTimersByTimeAsync(5000);
    expect(save).not.toHaveBeenCalled();
  });

  test('combined indicator: error beats saving beats saved', () => {
    expect(combineStatus('saved', 'error')).toBe('error');
    expect(combineStatus('saving', 'saved')).toBe('saving');
    expect(combineStatus('idle', 'saved')).toBe('saved');
    expect(combineStatus('idle', 'idle')).toBe('idle');
  });
});
