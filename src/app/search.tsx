import Ionicons from '@expo/vector-icons/Ionicons';
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BackButton, IconButton, LoadingState, MessageState, ScreenHeader } from '@/components/ui';
import { useDebouncedValue } from '@/hooks/useDebouncedValue';
import { errorMessage } from '@/lib/api';
import { displayTitle, type SearchResult } from '@/lib/types';
import { useSession } from '@/state/session';
import { colors, radius, spacing } from '@/theme';

type State =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'done'; query: string; results: SearchResult[] }
  | { kind: 'error'; message: string };

const SEARCH_DEBOUNCE_MS = 300; // page-search spec: ~300 ms after the last keystroke

export default function SearchScreen() {
  const { api } = useSession();
  const insets = useSafeAreaInsets();
  const [query, setQuery] = useState('');
  const [attempt, setAttempt] = useState(0);
  const debounced = useDebouncedValue(query.trim(), SEARCH_DEBOUNCE_MS);
  const [state, setState] = useState<State>({ kind: 'idle' });

  useEffect(() => {
    if (debounced === '') {
      setState({ kind: 'idle' });
      return;
    }
    let cancelled = false; // drop responses for older queries
    setState({ kind: 'loading' });
    api
      .search(debounced)
      .then((results) => {
        if (!cancelled) setState({ kind: 'done', query: debounced, results });
      })
      .catch((e: unknown) => {
        if (!cancelled) setState({ kind: 'error', message: errorMessage(e) });
      });
    return () => {
      cancelled = true;
    };
  }, [api, debounced, attempt]);

  let body;
  if (state.kind === 'idle') {
    body = <MessageState icon="search-outline" title="Search your pages" message="Find words in titles and text." />;
  } else if (state.kind === 'loading') {
    body = <LoadingState />;
  } else if (state.kind === 'error') {
    body = (
      <MessageState
        icon="cloud-offline-outline"
        title="Search failed"
        message={state.message}
        actionLabel="Try again"
        onAction={() => setAttempt((n) => n + 1)}
      />
    );
  } else if (state.results.length === 0) {
    body = <MessageState icon="document-outline" title="No results" message={`Nothing matches “${state.query}”.`} />;
  } else {
    body = (
      <FlatList
        data={state.results}
        keyExtractor={(r) => r.id}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="on-drag"
        contentContainerStyle={{ paddingVertical: spacing.sm, paddingBottom: insets.bottom + spacing.lg }}
        renderItem={({ item }) => (
          <Pressable
            onPress={() => router.push(`/page/${item.id}`)}
            accessibilityRole="button"
            style={({ pressed }) => [styles.result, pressed && { backgroundColor: colors.pressed }]}
          >
            <View style={styles.icon}>
              {item.icon ? (
                <Text style={styles.emoji}>{item.icon}</Text>
              ) : (
                <Ionicons name="document-text-outline" size={19} color={colors.muted} />
              )}
            </View>
            <View style={styles.resultText}>
              <Text style={[styles.title, !item.title.trim() && { color: colors.muted }]} numberOfLines={1}>
                {displayTitle(item.title)}
              </Text>
              {item.snippet ? (
                <Text style={styles.snippet} numberOfLines={2}>
                  {item.snippet}
                </Text>
              ) : null}
            </View>
          </Pressable>
        )}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <ScreenHeader left={<BackButton />}>
        <View style={styles.searchBox}>
          <Ionicons name="search" size={18} color={colors.muted} />
          <TextInput
            value={query}
            onChangeText={setQuery}
            autoFocus
            placeholder="Search"
            placeholderTextColor={colors.faint}
            returnKeyType="search"
            autoCapitalize="none"
            autoCorrect={false}
            maxLength={100}
            style={styles.searchInput}
            accessibilityLabel="Search pages"
          />
          {query ? <IconButton name="close-circle" size={18} color={colors.faint} label="Clear" onPress={() => setQuery('')} /> : null}
        </View>
      </ScreenHeader>
      {body}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  searchBox: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    paddingLeft: spacing.md,
    marginRight: spacing.sm,
    minHeight: 40,
    gap: spacing.sm,
  },
  searchInput: { flex: 1, fontSize: 16, color: colors.text, paddingVertical: spacing.sm },
  result: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  icon: { width: 26, alignItems: 'center', marginRight: spacing.md, paddingTop: 1 },
  emoji: { fontSize: 18 },
  resultText: { flex: 1 },
  title: { fontSize: 16, fontWeight: '600', color: colors.text },
  snippet: { fontSize: 14, color: colors.muted, marginTop: 2, lineHeight: 20 },
});
