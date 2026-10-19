import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Alert,
  AppState,
  Keyboard,
  KeyboardAvoidingView,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
  type LayoutChangeEvent,
  type ScrollViewInstance,
  type TextInputInstance,
  type NativeScrollEvent,
  type NativeSyntheticEvent,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BlockRow } from '@/components/BlockRow';
import { EmojiPicker } from '@/components/EmojiPicker';
import { MenuSheet } from '@/components/MenuSheet';
import { TurnIntoBar } from '@/components/TurnIntoBar';
import { BackButton, IconButton, LoadingState, MessageState, ScreenHeader, showError } from '@/components/ui';
import { useKeyboardVisible } from '@/hooks/useKeyboardVisible';
import { errorMessage, isApiError } from '@/lib/api';
import { AutosaveController, combineStatus, statusLabel, type SaveStatus } from '@/lib/autosave';
import {
  appendParagraph,
  applyBackspaceOnEmpty,
  applyTextChange,
  createBlock,
  numberLabels,
  removeBlock,
  toggleTodo,
  turnInto,
  type EditResult,
  type FocusTarget,
} from '@/lib/blocks';
import type { Block, BlockType } from '@/lib/types';
import { newId } from '@/lib/uuid';
import { usePages } from '@/state/pages';
import { useSession } from '@/state/session';
import { colors, fontSize, spacing } from '@/theme';

type LoadState = 'loading' | 'ready' | 'notFound' | 'error';
interface Meta {
  title: string;
  icon: string;
}

const SCROLL_MARGIN = 32;

export default function PageScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const pageId = String(id);
  const { api } = useSession();
  const { upsert, patch, removeSubtree, expand } = usePages();
  const insets = useSafeAreaInsets();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [loadError, setLoadError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);
  const [meta, setMeta] = useState<Meta>({ title: '', icon: '' });
  const [blocks, setBlocks] = useState<Block[]>([]);
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [pendingFocus, setPendingFocus] = useState<FocusTarget | null>(null);
  const [blockStatus, setBlockStatus] = useState<SaveStatus>('idle');
  const [metaStatus, setMetaStatus] = useState<SaveStatus>('idle');
  const [menuOpen, setMenuOpen] = useState(false);
  const [emojiOpen, setEmojiOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  // Latest values for stable callbacks (handlers are memoised so BlockRow can skip re-renders).
  const blocksRef = useRef<Block[]>([]);
  const metaRef = useRef<Meta>({ title: '', icon: '' });
  const focusedIdRef = useRef<string | null>(null);
  const inputs = useRef(new Map<string, TextInputInstance>());

  // ---- autosave (design.md D10): blocks via PUT, title/icon via PATCH, one controller each ----
  const blockSaver = useRef<AutosaveController<Block[]> | null>(null);
  const metaSaver = useRef<AutosaveController<Meta> | null>(null);

  useEffect(() => {
    const bs = new AutosaveController<Block[]>({
      save: (list) => api.saveBlocks(pageId, list),
      onStatusChange: setBlockStatus,
    });
    const ms = new AutosaveController<Meta>({
      save: (m) => api.updatePage(pageId, { title: m.title, icon: m.icon }),
      onStatusChange: setMetaStatus,
    });
    blockSaver.current = bs;
    metaSaver.current = ms;
    return () => {
      // Leaving the page: save anything pending, then stop retrying.
      void bs.flush().finally(() => bs.dispose());
      void ms.flush().finally(() => ms.dispose());
    };
  }, [api, pageId]);

  const flushAll = useCallback(
    () => Promise.all([blockSaver.current?.flush(), metaSaver.current?.flush()]).then(() => undefined),
    [],
  );

  // App going to the background: flush.
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state !== 'active') void flushAll();
    });
    return () => sub.remove();
  }, [flushAll]);

  // Navigating away (back, or forward to a subpage): flush.
  useFocusEffect(
    useCallback(
      () => () => {
        void flushAll();
      },
      [flushAll],
    ),
  );

  // ---- load ----
  useEffect(() => {
    let cancelled = false;
    setLoadState('loading');
    api
      .getPage(pageId)
      .then((page) => {
        if (cancelled) return;
        const { blocks: loaded, ...rest } = page;
        const initial = loaded.length > 0 ? loaded : [createBlock(newId)];
        blocksRef.current = initial;
        metaRef.current = { title: page.title, icon: page.icon };
        setBlocks(initial);
        setMeta(metaRef.current);
        setLoadState('ready');
        upsert(rest);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        if (isApiError(e) && e.status === 404) setLoadState('notFound');
        else {
          setLoadError(errorMessage(e));
          setLoadState('error');
        }
      });
    return () => {
      cancelled = true;
    };
  }, [api, pageId, reloadKey, upsert]);

  // ---- keeping the focused block visible above the keyboard ----
  const scrollRef = useRef<ScrollViewInstance>(null);
  const scrollY = useRef(0);
  const viewportH = useRef(0);
  const blocksTop = useRef(0);
  const layouts = useRef(new Map<string, { y: number; h: number }>());

  const ensureVisible = useCallback((blockId: string | null) => {
    if (!blockId) return;
    const l = layouts.current.get(blockId);
    if (!l || viewportH.current === 0) return;
    const top = blocksTop.current + l.y;
    const bottom = top + l.h;
    if (bottom + SCROLL_MARGIN > scrollY.current + viewportH.current) {
      scrollRef.current?.scrollTo({ y: Math.max(0, bottom + SCROLL_MARGIN - viewportH.current), animated: true });
    } else if (top - SCROLL_MARGIN < scrollY.current) {
      scrollRef.current?.scrollTo({ y: Math.max(0, top - SCROLL_MARGIN), animated: true });
    }
  }, []);

  const onKeyboardShown = useCallback(() => ensureVisible(focusedIdRef.current), [ensureVisible]);
  const keyboardVisible = useKeyboardVisible(onKeyboardShown);

  // ---- editing ----
  const commit = useCallback((res: EditResult) => {
    if (res.blocks !== blocksRef.current) {
      blocksRef.current = res.blocks;
      setBlocks(res.blocks);
      blockSaver.current?.update(res.blocks);
    }
    if (res.focus) setPendingFocus(res.focus);
  }, []);

  // Move the caret once the target input exists (new blocks mount in the same commit).
  useEffect(() => {
    if (!pendingFocus) return;
    const input = inputs.current.get(pendingFocus.id);
    if (input) {
      input.focus();
      if (pendingFocus.atEnd) {
        const len = blocksRef.current.find((b) => b.id === pendingFocus.id)?.text.length ?? 0;
        input.setSelection(len, len);
      }
    }
    setPendingFocus(null);
  }, [pendingFocus, blocks]);

  const indexOf = (blockId: string) => blocksRef.current.findIndex((b) => b.id === blockId);

  const handlers = useMemo(
    () => ({
      onChangeText: (blockId: string, text: string) =>
        commit(applyTextChange(blocksRef.current, indexOf(blockId), text, newId)),
      onBackspace: (blockId: string) => {
        const res = applyBackspaceOnEmpty(blocksRef.current, indexOf(blockId));
        if (!res) return;
        commit(res);
        if (!res.focus) Keyboard.dismiss();
      },
      onFocus: (blockId: string) => {
        focusedIdRef.current = blockId;
        setFocusedId(blockId);
        ensureVisible(blockId);
      },
      onBlur: (blockId: string) => {
        if (focusedIdRef.current !== blockId) return;
        focusedIdRef.current = null;
        setFocusedId(null);
      },
      onToggle: (blockId: string) => {
        const next = toggleTodo(blocksRef.current, indexOf(blockId));
        commit({ blocks: next, focus: null });
      },
      onDividerLongPress: (blockId: string) => {
        Alert.alert('Delete divider?', undefined, [
          { text: 'Cancel', style: 'cancel' },
          {
            text: 'Delete',
            style: 'destructive',
            onPress: () => commit({ blocks: removeBlock(blocksRef.current, indexOf(blockId)), focus: null }),
          },
        ]);
      },
      registerInput: (blockId: string, input: TextInputInstance | null) => {
        if (input) inputs.current.set(blockId, input);
        else inputs.current.delete(blockId);
      },
      onLayout: (blockId: string, y: number, h: number) => {
        const prev = layouts.current.get(blockId);
        layouts.current.set(blockId, { y, h });
        // The focused block grew (typing a new line): keep it in view.
        if (blockId === focusedIdRef.current && prev && prev.h !== h) ensureVisible(blockId);
      },
    }),
    [commit, ensureVisible],
  );

  const onTurnInto = (type: BlockType) => {
    const fid = focusedIdRef.current;
    if (!fid) return;
    commit(turnInto(blocksRef.current, indexOf(fid), type, newId));
  };

  const onTapBelow = () => commit(appendParagraph(blocksRef.current, newId));

  const updateMeta = (next: Meta) => {
    metaRef.current = next;
    setMeta(next);
    patch(pageId, next); // Home tree shows the new title/icon right away
    metaSaver.current?.update(next);
  };

  const onTitleChange = (text: string) => updateMeta({ ...metaRef.current, title: text.replace(/\n/g, ' ') });

  const onTitleSubmit = () => {
    const first = blocksRef.current.find((b) => b.type !== 'divider');
    if (first) setPendingFocus({ id: first.id, atEnd: true });
    else onTapBelow();
  };

  const setIcon = (icon: string) => {
    setEmojiOpen(false);
    updateMeta({ ...metaRef.current, icon });
    void metaSaver.current?.flush(); // icon changes are discrete: save now
  };

  // ---- page actions ----
  const addSubpage = async () => {
    setBusy(true);
    try {
      const child = await api.createPage({ parentId: pageId });
      upsert(child);
      expand(pageId);
      router.push(`/page/${child.id}`);
    } catch (e) {
      showError('Couldn’t add subpage', e);
    } finally {
      setBusy(false);
    }
  };

  const moveToTrash = async () => {
    setBusy(true);
    try {
      await flushAll();
      await api.trashPage(pageId);
      blockSaver.current?.dispose();
      metaSaver.current?.dispose();
      removeSubtree(pageId);
      if (router.canGoBack()) router.back();
      else router.replace('/');
    } catch (e) {
      setBusy(false);
      showError('Couldn’t move to trash', e);
    }
  };

  const status = combineStatus(blockStatus, metaStatus);
  const numbers = useMemo(() => numberLabels(blocks), [blocks]);
  const focusedBlock = focusedId ? blocks.find((b) => b.id === focusedId) : undefined;

  const header = (
    <ScreenHeader
      left={<BackButton />}
      right={
        loadState === 'ready' ? (
          <>
            <Text
              style={[styles.status, status === 'error' && styles.statusError]}
              numberOfLines={1}
              accessibilityLiveRegion="polite"
            >
              {statusLabel(status)}
            </Text>
            <IconButton name="ellipsis-horizontal" label="Page actions" onPress={() => setMenuOpen(true)} disabled={busy} />
          </>
        ) : undefined
      }
    >
      <View style={styles.headerSpacer} />
    </ScreenHeader>
  );

  if (loadState !== 'ready') {
    return (
      <View style={styles.screen}>
        {header}
        {loadState === 'loading' ? <LoadingState /> : null}
        {loadState === 'notFound' ? (
          <MessageState
            icon="document-outline"
            title="Page not found"
            message="It may have been moved to the trash or deleted."
          />
        ) : null}
        {loadState === 'error' ? (
          <MessageState
            icon="cloud-offline-outline"
            title="Couldn’t open this page"
            message={loadError ?? undefined}
            actionLabel="Try again"
            onAction={() => setReloadKey((k) => k + 1)}
          />
        ) : null}
      </View>
    );
  }

  return (
    <View style={styles.screen}>
      {header}
      <KeyboardAvoidingView style={styles.flex} behavior="padding">
        <ScrollView
          ref={scrollRef}
          style={styles.flex}
          contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.lg }]}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="none"
          scrollEventThrottle={32}
          onScroll={(e: NativeSyntheticEvent<NativeScrollEvent>) => {
            scrollY.current = e.nativeEvent.contentOffset.y;
          }}
          onLayout={(e: LayoutChangeEvent) => {
            viewportH.current = e.nativeEvent.layout.height;
            ensureVisible(focusedIdRef.current); // viewport shrank for the keyboard
          }}
        >
          <View style={styles.iconRow}>
            {meta.icon ? (
              <Pressable onPress={() => setEmojiOpen(true)} accessibilityRole="button" accessibilityLabel="Change icon">
                <Text style={styles.bigIcon}>{meta.icon}</Text>
              </Pressable>
            ) : (
              <Pressable
                onPress={() => setEmojiOpen(true)}
                accessibilityRole="button"
                style={({ pressed }) => [styles.addIcon, pressed && { backgroundColor: colors.pressed }]}
              >
                <Text style={styles.addIconText}>☺ Add icon</Text>
              </Pressable>
            )}
          </View>

          <TextInput
            value={meta.title}
            onChangeText={onTitleChange}
            placeholder="Untitled"
            placeholderTextColor={colors.faint}
            multiline
            scrollEnabled={false}
            submitBehavior="submit"
            returnKeyType="next"
            onSubmitEditing={onTitleSubmit}
            maxLength={200}
            style={styles.title}
            accessibilityLabel="Page title"
            textAlignVertical="top"
          />

          <View
            onLayout={(e) => {
              blocksTop.current = e.nativeEvent.layout.y;
            }}
          >
            {blocks.map((block, i) => (
              <BlockRow
                key={block.id}
                block={block}
                number={numbers[i]}
                showPlaceholder={block.id === focusedId || (blocks.length === 1 && block.text === '')}
                {...handlers}
              />
            ))}
          </View>

          <Pressable
            style={styles.tapBelow}
            onPress={onTapBelow}
            accessibilityRole="button"
            accessibilityLabel="Add a block at the end"
          />
        </ScrollView>

        {focusedBlock ? (
          <TurnIntoBar
            current={focusedBlock.type}
            onPick={onTurnInto}
            onDone={() => Keyboard.dismiss()}
            bottomInset={keyboardVisible ? 0 : insets.bottom}
          />
        ) : null}
      </KeyboardAvoidingView>

      <MenuSheet
        visible={menuOpen}
        onClose={() => setMenuOpen(false)}
        items={[
          { label: 'Add subpage', icon: 'add-circle-outline', onPress: () => void addSubpage() },
          { label: 'Move to trash', icon: 'trash-outline', onPress: () => void moveToTrash(), destructive: true },
        ]}
      />
      <EmojiPicker
        visible={emojiOpen}
        hasIcon={meta.icon !== ''}
        onSelect={setIcon}
        onRemove={() => setIcon('')}
        onClose={() => setEmojiOpen(false)}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  flex: { flex: 1 },
  headerSpacer: { flex: 1 },
  status: { fontSize: 13, color: colors.muted, maxWidth: 190 },
  statusError: { color: colors.danger },
  content: { flexGrow: 1, paddingHorizontal: 20, paddingTop: spacing.lg },
  iconRow: { flexDirection: 'row', marginBottom: spacing.xs },
  bigIcon: { fontSize: 52, lineHeight: 62 },
  addIcon: { paddingVertical: spacing.xs, paddingHorizontal: spacing.sm, marginLeft: -spacing.sm, borderRadius: 6 },
  addIconText: { fontSize: 14, color: colors.faint },
  title: {
    fontSize: fontSize.title,
    lineHeight: 40,
    fontWeight: '700',
    color: colors.text,
    padding: 0,
    marginBottom: spacing.md,
    includeFontPadding: false,
  },
  tapBelow: { flexGrow: 1, minHeight: 160 },
});
