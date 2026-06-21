import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum LogLevel { info, success, warning, error }

/// One timestamped line in the activity log.
class LogEntry {
  final DateTime time;
  final String message;
  final LogLevel level;

  LogEntry(this.message, {this.level = LogLevel.info, DateTime? time})
      : time = time ?? DateTime.now();

  String get clock {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}

/// A collapsible "Activity" panel that surfaces what the app is doing. Collapsed
/// it shows the latest line; expanded it reveals the scrollable history and
/// auto-scrolls as new entries arrive.
class ActivityLog extends StatefulWidget {
  final List<LogEntry> entries;

  const ActivityLog({super.key, required this.entries});

  @override
  State<ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<ActivityLog> {
  bool _expanded = false;
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ActivityLog old) {
    super.didUpdateWidget(old);
    if (_expanded && widget.entries.length != old.entries.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.success:
        return AppColors.connected;
      case LogLevel.warning:
        return AppColors.warning;
      case LogLevel.error:
        return AppColors.danger;
      case LogLevel.info:
        return context.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final latest = entries.isEmpty ? null : entries.last;

    return Container(
      decoration: BoxDecoration(
        color: context.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header — tap to expand/collapse.
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (_expanded) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded, size: 18, color: context.muted),
                  const SizedBox(width: 10),
                  Text(
                    'Activity',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: context.scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Inline preview of the latest line when collapsed.
                  if (!_expanded && latest != null)
                    Expanded(
                      child: Text(
                        latest.message,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _color(context, latest.level),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: context.muted,
                  ),
                ],
              ),
            ),
          ),
          // Expanded history.
          if (_expanded)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.hairline)),
              ),
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No activity yet.',
                        style: TextStyle(color: context.muted, fontSize: 12.5),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.clock,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: context.muted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.message,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.3,
                                    color: _color(context, e.level),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
