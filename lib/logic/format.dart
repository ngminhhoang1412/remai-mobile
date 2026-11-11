/// Short relative time for trash rows ("2 h ago"). Falls back to the date after a week.
String relativeTime(String iso, DateTime now) {
  final then = DateTime.tryParse(iso);
  if (then == null) return '';
  final diff = now.toUtc().difference(then.toUtc());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  final local = then.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
