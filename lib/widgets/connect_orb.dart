import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The hero connect button: a large glowing orb whose look reflects the VPN
/// state — dimmed when nothing is selected, brand-gradient when ready, a pulsing
/// ring while connecting, and a steady green glow once connected.
class ConnectOrb extends StatefulWidget {
  /// A profile is selected, so the orb is actionable.
  final bool enabled;

  /// Tunnel is up.
  final bool connected;

  /// A transitional stage is in progress (connecting/authenticating/…).
  final bool busy;

  /// Short caption shown under the icon ("CONNECT", "CONNECTED", …).
  final String label;

  final VoidCallback? onTap;

  const ConnectOrb({
    super.key,
    required this.enabled,
    required this.connected,
    required this.busy,
    required this.label,
    this.onTap,
  });

  @override
  State<ConnectOrb> createState() => _ConnectOrbState();
}

class _ConnectOrbState extends State<ConnectOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ConnectOrb old) {
    super.didUpdateWidget(old);
    _syncAnimation();
  }

  /// Only pulse when there's something to animate — otherwise the controller
  /// runs forever and `pumpAndSettle` (and battery) never rest.
  void _syncAnimation() {
    final animate = widget.busy || widget.connected;
    if (animate) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final accent = !active
        ? context.muted
        : (widget.connected ? AppColors.connected : AppColors.brandBlue);
    final gradient = !active
        ? null
        : (widget.connected
            ? AppColors.connectedGradient
            : AppColors.brandGradient);
    final animate = widget.busy || widget.connected;

    return Semantics(
      button: true,
      enabled: active,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final glow = animate
                ? 0.30 + 0.28 * _pulse.value
                : (active ? 0.22 : 0.0);
            final ringScale = animate ? 1.0 + 0.06 * _pulse.value : 1.0;

            return SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Soft outer glow.
                  Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: glow),
                          blurRadius: 48,
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  // Pulsing halo ring while busy / connected.
                  Transform.scale(
                    scale: ringScale,
                    child: Container(
                      width: 176,
                      height: 176,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accent.withValues(alpha: animate ? 0.35 : 0.15),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  // Indeterminate progress arc while connecting.
                  if (widget.busy)
                    SizedBox(
                      width: 172,
                      height: 172,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation(accent.withValues(alpha: 0.9)),
                      ),
                    ),
                  // Main orb.
                  Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradient,
                      color: gradient == null ? context.panelHi : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.power_settings_new_rounded,
                          size: 56,
                          color: active ? Colors.white : context.muted,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: active
                                ? Colors.white.withValues(alpha: 0.95)
                                : context.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
