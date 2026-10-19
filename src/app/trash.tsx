import Ionicons from '@expo/vector-icons/Ionicons';
import { useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Alert, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BackButton, LoadingState, MessageState, ScreenHeader, showError } from '@/components/ui';
import { errorMessage } from '@/lib/api';
import { displayTitle, type TrashedPage } from '@/lib/types';
import { usePages } from '@/state/pages';
import { useSession } from '@/state/session';
import { colors, radius, spacing } from '@/theme';

function formatTrashedAt(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return `Trashed ${d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}`;
}

export default function TrashScreen() {
  const { api } = useSession();
  const { refresh: refreshPages } = usePages();
  const insets = useSafeAreaInsets();
  const [items, setItems] = useState<TrashedPage[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const seq = useRef(0);

  const load = useCallback(async () => {
    const mine = ++seq.current;
    try {
      const list = await api.listTrash();
      if (mine !== seq.current) return;
      setItems(list);
      setError(null);
    } catch (e) {
      if (mine !== seq.current) return;
      setError(errorMessage(e));
    }
  }, [api]);

  useFocusEffect(
    useCallback(() => {
      void load();
    }, [load]),
  );

  const removeItem = (id: string) => setItems((prev) => (prev ? prev.filter((p) => p.id !== id) : prev));

  const restore = async (item: TrashedPage) => {
    setBusyId(item.id);
    try {
      await api.restorePage(item.id);
      removeItem(item.id);
      void refreshPages(); // the page and the subpages trashed with it are back in the tree
    } catch (e) {
      showError('Couldn’t restore page', e);
    } finally {
      setBusyId(null);
    }
  };

  const deleteForever = async (item: TrashedPage) => {
    setBusyId(item.id);
    try {
      await api.deleteForever(item.id);
      removeItem(item.id);
    } catch (e) {
      showError('Couldn’t delete page', e);
    } finally {
      setBusyId(null);
    }
  };

  // page-trash spec: ask before deleting forever; delete only on confirm.
  const confirmDelete = (item: TrashedPage) => {
    Alert.alert(
      'Delete forever?',
      `“${displayTitle(item.title)}” and its subpages will be permanently deleted. This can’t be undone.`,
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete forever', style: 'destructive', onPress: () => void deleteForever(item) },
      ],
    );
  };

  let body;
  if (items === null && error) {
    body = (
      <MessageState
        icon="cloud-offline-outline"
        title="Couldn’t load the trash"
        message={error}
        actionLabel="Try again"
        onAction={() => void load()}
      />
    );
  } else if (items === null) {
    body = <LoadingState />;
  } else if (items.length === 0) {
    body = <MessageState icon="trash-outline" title="Trash is empty" message="Pages you move to the trash show up here." />;
  } else {
    body = (
      <FlatList
        data={items}
        keyExtractor={(p) => p.id}
        contentContainerStyle={{ paddingVertical: spacing.sm, paddingBottom: insets.bottom + spacing.lg }}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              await load();
              setRefreshing(false);
            }}
          />
        }
        renderItem={({ item }) => {
          const busy = busyId === item.id;
          return (
            <View style={styles.row}>
              <View style={styles.icon}>
                {item.icon ? (
                  <Text style={styles.emoji}>{item.icon}</Text>
                ) : (
                  <Ionicons name="document-text-outline" size={19} color={colors.muted} />
                )}
              </View>
              <View style={styles.text}>
                <Text style={[styles.title, !item.title.trim() && { color: colors.muted }]} numberOfLines={1}>
                  {displayTitle(item.title)}
                </Text>
                <Text style={styles.meta}>{formatTrashedAt(item.trashedAt)}</Text>
              </View>
              {busy ? (
                <ActivityIndicator color={colors.muted} style={styles.spinner} />
              ) : (
                <View style={styles.actions}>
                  <Pressable
                    onPress={() => void restore(item)}
                    disabled={busyId !== null}
                    accessibilityRole="button"
                    accessibilityLabel={`Restore ${displayTitle(item.title)}`}
                    style={({ pressed }) => [styles.action, pressed && { backgroundColor: colors.pressed }]}
                  >
                    <Text style={styles.actionText}>Restore</Text>
                  </Pressable>
                  <Pressable
                    onPress={() => confirmDelete(item)}
                    disabled={busyId !== null}
                    accessibilityRole="button"
                    accessibilityLabel={`Delete ${displayTitle(item.title)} forever`}
                    style={({ pressed }) => [styles.action, pressed && { backgroundColor: colors.dangerBg }]}
                  >
                    <Text style={[styles.actionText, { color: colors.danger }]}>Delete forever</Text>
                  </Pressable>
                </View>
              )}
            </View>
          );
        }}
      />
    );
  }

  return (
    <View style={styles.screen}>
      <ScreenHeader left={<BackButton />} title="Trash" />
      {body}
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  icon: { width: 26, alignItems: 'center', marginRight: spacing.md },
  emoji: { fontSize: 18 },
  text: { flex: 1, minWidth: 120 },
  title: { fontSize: 16, color: colors.text, fontWeight: '500' },
  meta: { fontSize: 13, color: colors.faint, marginTop: 2 },
  actions: { flexDirection: 'row', gap: spacing.xs, marginLeft: 'auto' },
  action: { paddingHorizontal: spacing.sm, paddingVertical: 6, borderRadius: radius.sm },
  actionText: { fontSize: 14, fontWeight: '600', color: colors.accent },
  spinner: { marginLeft: 'auto', paddingHorizontal: spacing.lg },
});
