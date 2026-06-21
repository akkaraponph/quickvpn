import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single profile row: selectable, with an optional credentials shortcut and
/// a remove action. Works the same on desktop and mobile (no swipe-only gestures).
class ProfileTile extends StatelessWidget {
  final String name;
  final bool selected;
  final bool requiresAuth;
  final bool hasCredentials;

  /// This profile is the one currently connected — removal is blocked.
  final bool connected;

  final VoidCallback? onTap;
  final VoidCallback? onEditCredentials;
  final VoidCallback? onDelete;

  const ProfileTile({
    super.key,
    required this.name,
    required this.selected,
    required this.requiresAuth,
    required this.hasCredentials,
    required this.connected,
    this.onTap,
    this.onEditCredentials,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.brandBlue;
    final borderColor = selected ? accent : context.hairline;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected ? context.panelHi : context.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Leading icon badge.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    gradient: selected ? AppColors.brandGradient : null,
                    color: selected ? null : context.panelHi,
                  ),
                  child: Icon(
                    Icons.vpn_lock_rounded,
                    size: 20,
                    color: selected ? Colors.white : context.muted,
                  ),
                ),
                const SizedBox(width: 12),
                // Name + connected hint.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: context.scheme.onSurface,
                        ),
                      ),
                      if (connected)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.connected,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Connected',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.connected,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Credentials shortcut.
                if (requiresAuth)
                  IconButton(
                    tooltip: 'Set username & password',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      hasCredentials
                          ? Icons.vpn_key_rounded
                          : Icons.vpn_key_outlined,
                      size: 20,
                      color: hasCredentials ? accent : context.muted,
                    ),
                    onPressed: onEditCredentials,
                  ),
                // Selected check.
                if (selected)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.check_circle_rounded,
                        color: accent, size: 20),
                  ),
                // Remove — disabled while this profile is connected.
                IconButton(
                  tooltip: connected
                      ? 'Disconnect before removing'
                      : 'Remove profile',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: connected
                        ? context.muted.withValues(alpha: 0.4)
                        : AppColors.danger.withValues(alpha: 0.85),
                  ),
                  onPressed: connected ? null : onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
