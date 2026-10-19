import Ionicons from '@expo/vector-icons/Ionicons';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { MenuSheet } from '@/components/MenuSheet';
import { IconButton, LoadingState, MessageState, ScreenHeader, showError } from '@/components/ui';
import { buildTree, flattenVisible, type TreeRow } from '@/lib/tree';
import { displayTitle } from '@/lib/types';
import { usePages } from '@/state/pages';
import { useSession } from '@/state/session';
import { colors, radius, spacing } from '@/theme';

const INDENT = 18;

export default function HomeScreen() {
  const { api, user, signOut } = useSession();
  const { pages, loadState, error, expanded, refresh, upsert, toggleExpanded } = usePages();
  const insets = useSafeAreaInsets();
  const [menuOpen, setMenuOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  // Refetch whenever Home comes back into view (pages may have been created, trashed or restored).
  useFocusEffect(
    useCallback(() => {
      void refresh();
    }, [refresh]),
  );

  const rows = useMemo(() => flattenVisible(buildTree(pages), expanded), [pages, expanded]);

  const newPage = async () => {
    if (creating) return;
    setCreating(true);
    try {
      const page = await api.createPage({});
      upsert(page);
      router.push(`/page/${page.id}`);
    } catch (e) {
      showError('Couldn’t create page', e);
    } finally {
      setCreating(false);
    }
  };

  const onPullRefresh = async () => {
    setRefreshing(true);
    await refresh();
    setRefreshing(false);
  };

  const renderRow = ({ item }: { item: TreeRow }) => (
    <Pressable
      onPress={() => router.push(`/page/${item.page.id}`)}
      accessibilityRole="button"
      accessibilityLabel={`Open ${displayTitle(item.page.title)}`}
      style={({ pressed }) => [styles.row, { paddingLeft: spacing.sm + item.depth * INDENT }, pressed && styles.pressed]}
    >
      {item.hasChildren ? (
        <Pressable
          onPress={() => toggleExpanded(item.page.id)}
          hitSlop={10}
          accessibilityRole="button"
          accessibilityLabel={item.expanded ? 'Collapse' : 'Expand'}
          style={styles.chevron}
        >
          <Ionicons name={item.expanded ? 'chevron-down' : 'chevron-forward'} size={16} color={colors.muted} />
        </Pressable>
      ) : (
        <View style={styles.chevron} />
      )}
      <View style={styles.icon}>
        {item.page.icon ? (
          <Text style={styles.emoji}>{item.page.icon}</Text>
        ) : (
          <Ionicons name="document-text-outline" size={19} color={colors.muted} />
        )}
      </View>
      <Text style={[styles.title, !item.page.title.trim() && styles.untitled]} numberOfLines={1}>
        {displayTitle(item.page.title)}
      </Text>
    </Pressable>
  );

  let body;
  if (pages.length === 0 && (loadState === 'idle' || loadState === 'loading')) {
    body = <LoadingState />;
  } else if (pages.length === 0 && loadState === 'error') {
    body = (
      <MessageState
        icon="cloud-offline-outline"
        title="Couldn’t load your pages"
        message={error ?? undefined}
        actionLabel="Try again"
        onAction={() => void refresh()}
      />
    );
  } else if (pages.length === 0) {
    body = (
      <MessageState
        icon="document-outline"
        title="No pages yet"
        message="Create your first page to start writing."
        actionLabel="New page"
        onAction={() => void newPage()}
      />
    );
  } else {
    body = (
      <FlatList
        data={rows}
        keyExtractor={(r) => r.page.id}
        renderItem={renderRow}
        contentContainerStyle={{ paddingVertical: spacing.sm, paddingBottom: insets.bottom + 96 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void onPullRefresh()} />}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <ScreenHeader
        right={
          <>
            <IconButton name="search" label="Search" onPress={() => router.push('/search')} />
            <IconButton name="ellipsis-horizontal" label="More" onPress={() => setMenuOpen(true)} />
          </>
        }
      >
        <View style={styles.headerTitleBox}>
          <Text style={styles.headerTitle} numberOfLines={1}>
            {user?.name ? `${user.name}’s notes` : 'remai'}
          </Text>
        </View>
      </ScreenHeader>

      {body}

      {pages.length > 0 ? (
        <Pressable
          onPress={() => void newPage()}
          disabled={creating}
          accessibilityRole="button"
          accessibilityLabel="New page"
          style={({ pressed }) => [styles.fab, { bottom: insets.bottom + spacing.lg }, pressed && { opacity: 0.85 }]}
        >
          {creating ? (
            <ActivityIndicator color={colors.accentText} />
          ) : (
            <>
              <Ionicons name="add" size={22} color={colors.accentText} />
              <Text style={styles.fabText}>New page</Text>
            </>
          )}
        </Pressable>
      ) : null}

      <MenuSheet
        visible={menuOpen}
        onClose={() => setMenuOpen(false)}
        items={[
          { label: 'Trash', icon: 'trash-outline', onPress: () => router.push('/trash') },
          { label: 'Sign out', icon: 'log-out-outline', onPress: () => void signOut(), destructive: true },
        ]}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  headerTitleBox: { flex: 1, paddingHorizontal: spacing.sm },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.text },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: 44,
    paddingRight: spacing.lg,
    marginHorizontal: spacing.xs,
    borderRadius: radius.md,
  },
  pressed: { backgroundColor: colors.pressed },
  chevron: { width: 24, height: 24, alignItems: 'center', justifyContent: 'center' },
  icon: { width: 26, alignItems: 'center', marginRight: spacing.sm },
  emoji: { fontSize: 18 },
  title: { flex: 1, fontSize: 16, color: colors.text },
  untitled: { color: colors.muted },
  fab: {
    position: 'absolute',
    right: spacing.lg,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    minHeight: 48,
    minWidth: 130,
    justifyContent: 'center',
    paddingHorizontal: spacing.lg,
    borderRadius: 24,
    backgroundColor: colors.accent,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 3 },
    elevation: 4,
  },
  fabText: { color: colors.accentText, fontSize: 16, fontWeight: '600' },
});
