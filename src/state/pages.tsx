import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';

import { errorMessage } from '@/lib/api';
import { subtreeIds } from '@/lib/tree';
import type { Page } from '@/lib/types';

import { useSession } from './session';

type LoadState = 'idle' | 'loading' | 'ready' | 'error';

interface PagesValue {
  pages: Page[];
  loadState: LoadState;
  error: string | null;
  expanded: ReadonlySet<string>;
  refresh: () => Promise<void>;
  /** Insert or replace a page in the local cache (after create / rename / restore). */
  upsert: (page: Page) => void;
  /** Merge fields into a cached page (live title/icon edits). */
  patch: (id: string, fields: Partial<Page>) => void;
  /** Drop a page and its descendants from the cache (after moving it to the trash). */
  removeSubtree: (id: string) => void;
  toggleExpanded: (id: string) => void;
  expand: (id: string) => void;
}

const PagesContext = createContext<PagesValue | null>(null);

/** Page list cache shared by Home and the Page screen so renames show up without a refetch. */
export function PagesProvider({ children }: Readonly<{ children: ReactNode }>) {
  const { api, user } = useSession();
  const [pages, setPages] = useState<Page[]>([]);
  const [loadState, setLoadState] = useState<LoadState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const requestSeq = useRef(0);
  const userId = user?.id ?? null;

  // Clear the cache on sign-out so the next account never sees the previous user's tree.
  // (Only on the transition to signed-out: Home is unmounted then, so no refresh can race it.)
  useEffect(() => {
    if (userId !== null) return;
    requestSeq.current++;
    setPages([]);
    setLoadState('idle');
    setError(null);
    setExpanded(new Set());
  }, [userId]);

  const refresh = useCallback(async () => {
    const seq = ++requestSeq.current;
    setLoadState((s) => (s === 'ready' ? s : 'loading'));
    try {
      const list = await api.listPages();
      if (seq !== requestSeq.current) return;
      setPages(list);
      setError(null);
      setLoadState('ready');
    } catch (e) {
      if (seq !== requestSeq.current) return;
      setError(errorMessage(e));
      setLoadState((s) => (s === 'ready' ? s : 'error'));
    }
  }, [api]);

  const upsert = useCallback((page: Page) => {
    setPages((prev) => {
      const i = prev.findIndex((p) => p.id === page.id);
      if (i === -1) return [...prev, page];
      const copy = prev.slice();
      copy[i] = page;
      return copy;
    });
  }, []);

  const patch = useCallback((id: string, fields: Partial<Page>) => {
    setPages((prev) => prev.map((p) => (p.id === id ? { ...p, ...fields } : p)));
  }, []);

  const removeSubtree = useCallback((id: string) => {
    setPages((prev) => {
      const ids = subtreeIds(prev, id);
      return prev.filter((p) => !ids.has(p.id));
    });
  }, []);

  const toggleExpanded = useCallback((id: string) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const expand = useCallback((id: string) => {
    setExpanded((prev) => (prev.has(id) ? prev : new Set(prev).add(id)));
  }, []);

  const value = useMemo<PagesValue>(
    () => ({ pages, loadState, error, expanded, refresh, upsert, patch, removeSubtree, toggleExpanded, expand }),
    [pages, loadState, error, expanded, refresh, upsert, patch, removeSubtree, toggleExpanded, expand],
  );

  return <PagesContext.Provider value={value}>{children}</PagesContext.Provider>;
}

export function usePages(): PagesValue {
  const ctx = useContext(PagesContext);
  if (!ctx) throw new Error('usePages must be used inside PagesProvider');
  return ctx;
}
