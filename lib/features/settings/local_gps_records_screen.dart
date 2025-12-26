import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../service/providers/settings_provider.dart';
import '../../theme/colors.dart';

final localGpsDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

// pending/sent only (as you confirmed)
final localGpsStatusFilterProvider = StateProvider<Set<String>>(
      (ref) => <String>{'pending', 'sent'},
);

enum _ListItemType { header, record }

class _ListItem {
  final _ListItemType type;
  final String? headerText;
  final int? headerCount;
  final Map<String, dynamic>? record;
  final DateTime? recordTime;

  const _ListItem.header(this.headerText, this.headerCount)
      : type = _ListItemType.header,
        record = null,
        recordTime = null;

  const _ListItem.record(this.record, this.recordTime)
      : type = _ListItemType.record,
        headerText = null,
        headerCount = null;
}

class LocalGpsRecordsScreen extends ConsumerWidget {
  const LocalGpsRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(localDbLogsProvider);
    final range = ref.watch(localGpsDateRangeProvider);
    final statusSet = ref.watch(localGpsStatusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Local GPS Records', style: TextStyle(color: Colors.white)),
        backgroundColor: TWCColors.coffeeDark,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(localDbLogsProvider),
          ),
        ],
      ),
      backgroundColor: TWCColors.latteBg,
      body: Column(
        children: [
          _FiltersBar(
            range: range,
            statusSet: statusSet,
            onPickSingleDate: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
                initialDate: DateTime.now(),
              );
              if (picked == null) return;

              final start = DateTime(picked.year, picked.month, picked.day);
              final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999);
              ref.read(localGpsDateRangeProvider.notifier).state =
                  DateTimeRange(start: start, end: end);
            },
            onPickDateRange: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
                initialDateRange: range,
              );
              if (picked == null) return;

              // normalize to full days
              final start = DateTime(picked.start.year, picked.start.month, picked.start.day);
              final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
              ref.read(localGpsDateRangeProvider.notifier).state =
                  DateTimeRange(start: start, end: end);
            },
            onClearDate: () => ref.read(localGpsDateRangeProvider.notifier).state = null,
            onToggleStatus: (s) {
              final cur = {...ref.read(localGpsStatusFilterProvider)};
              if (cur.contains(s)) {
                cur.remove(s);
              } else {
                cur.add(s);
              }
              // prevent empty set (always keep at least one selected)
              if (cur.isEmpty) return;
              ref.read(localGpsStatusFilterProvider.notifier).state = cur;
            },
            onResetStatus: () => ref.read(localGpsStatusFilterProvider.notifier).state = {'pending', 'sent'},
          ),
          const SizedBox(height: 6),
          Expanded(
            child: async.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('No local records'));
                }

                // Filter
                final filtered = <Map<String, dynamic>>[];
                for (final raw in list) {
                  final e = Map<String, dynamic>.from(raw as Map);

                  final status = (e['status'] ?? 'pending').toString();
                  if (!statusSet.contains(status)) continue;

                  final t = _tryParseTimestamp(e['timestamp']?.toString());
                  if (range != null && t != null) {
                    if (t.isBefore(range.start) || t.isAfter(range.end)) continue;
                  }
                  // If range is set but timestamp is unparsable, we skip it (so filter stays correct)
                  if (range != null && t == null) continue;

                  filtered.add(e);
                }

                if (filtered.isEmpty) {
                  return const Center(child: Text('No records match the filter'));
                }

                // Sort by time desc (unparsable go last)
                filtered.sort((a, b) {
                  final ta = _tryParseTimestamp(a['timestamp']?.toString());
                  final tb = _tryParseTimestamp(b['timestamp']?.toString());
                  if (ta == null && tb == null) return 0;
                  if (ta == null) return 1;
                  if (tb == null) return -1;
                  return tb.compareTo(ta);
                });

                // Group by date (yyyy-mm-dd). Unparsable -> "Unknown date"
                final groups = <String, List<Map<String, dynamic>>>{};
                for (final e in filtered) {
                  final t = _tryParseTimestamp(e['timestamp']?.toString());
                  final key = t == null ? 'Unknown date' : _ymd(t);
                  groups.putIfAbsent(key, () => []).add(e);
                }

                final keys = groups.keys.toList();
                // Keep Unknown date last
                keys.sort((a, b) {
                  if (a == 'Unknown date' && b == 'Unknown date') return 0;
                  if (a == 'Unknown date') return 1;
                  if (b == 'Unknown date') return -1;
                  return b.compareTo(a); // ymd strings sort OK
                });

                // Flatten for a single ListView
                final items = <_ListItem>[];
                for (final k in keys) {
                  final chunk = groups[k]!;
                  items.add(_ListItem.header(k, chunk.length));
                  for (final e in chunk) {
                    items.add(_ListItem.record(e, _tryParseTimestamp(e['timestamp']?.toString())));
                  }
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(localDbLogsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.black12),
                    itemBuilder: (_, i) {
                      final it = items[i];

                      if (it.type == _ListItemType.header) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                it.headerText!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: TWCColors.coffeeDark,
                                ),
                              ),
                              Text(
                                '${it.headerCount} records',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      }

                      final e = it.record!;
                      final status = (e['status'] ?? 'pending').toString();
                      final statusColor = status == 'sent' ? Colors.green : Colors.orange;

                      final tsText = e['timestamp']?.toString() ?? '';
                      final t = it.recordTime;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t == null ? tsText : '${_ymd(t)} ${_hm(t)}'),
                        subtitle: Text(
                          'Lat: ${e['latitude']}, Lon: ${e['longitude']}\n'
                              'Acc: ${e['accuracy']}m, Battery: ${e['battery_level']}%',
                          style: const TextStyle(height: 1.3),
                        ),
                        trailing: Text(
                          status.toUpperCase(),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                        dense: true,
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final DateTimeRange? range;
  final Set<String> statusSet;
  final VoidCallback onPickSingleDate;
  final VoidCallback onPickDateRange;
  final VoidCallback onClearDate;
  final void Function(String) onToggleStatus;
  final VoidCallback onResetStatus;

  const _FiltersBar({
    required this.range,
    required this.statusSet,
    required this.onPickSingleDate,
    required this.onPickDateRange,
    required this.onClearDate,
    required this.onToggleStatus,
    required this.onResetStatus,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = range == null
        ? 'All dates'
        : '${_ymd(range!.start)} → ${_ymd(range!.end)}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date controls
          Row(
            children: [
              Expanded(
                child: Text(
                  dateText,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.calendar_month),
                onSelected: (v) {
                  if (v == 'single') onPickSingleDate();
                  if (v == 'range') onPickDateRange();
                  if (v == 'clear') onClearDate();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'single', child: Text('Single date')),
                  PopupMenuItem(value: 'range', child: Text('Date range')),
                  PopupMenuItem(value: 'clear', child: Text('Clear date filter')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Status chips
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              FilterChip(
                label: const Text('Pending'),
                selected: statusSet.contains('pending'),
                onSelected: (_) => onToggleStatus('pending'),
              ),
              FilterChip(
                label: const Text('Sent'),
                selected: statusSet.contains('sent'),
                onSelected: (_) => onToggleStatus('sent'),
              ),
              TextButton(
                onPressed: onResetStatus,
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Robust timestamp parsing:
/// - Works with ISO strings if your DB stores ISO
/// - Works with "yyyy-MM-dd HH:mm:ss" (common sqlite)
/// If it can’t parse, returns null (we still display raw timestamp).
DateTime? _tryParseTimestamp(String? s) {
  if (s == null || s.trim().isEmpty) return null;

  // 1) Native parse (handles ISO, some others)
  final direct = DateTime.tryParse(s);
  if (direct != null) return direct;

  // 2) Basic "yyyy-MM-dd HH:mm:ss"
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(s);
  if (m != null) {
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  return null;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _hm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';