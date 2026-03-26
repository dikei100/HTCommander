import 'package:flutter/material.dart';

/// Large PTT (Push-To-Talk) button with press-and-hold interaction.
/// Includes integrated status label below the button.
class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    this.onPttStart,
    this.onPttStop,
    this.isEnabled = false,
    this.isTransmitting = false,
    this.size = 80,
    this.showLabel = true,
  });

  final VoidCallback? onPttStart;
  final VoidCallback? onPttStop;
  final bool isEnabled;
  final bool isTransmitting;
  final double size;
  final bool showLabel;

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isActive = widget.isTransmitting || _pressed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: widget.isEnabled
              ? (_) {
                  setState(() => _pressed = true);
                  widget.onPttStart?.call();
                }
              : null,
          onTapUp: widget.isEnabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPttStop?.call();
                }
              : null,
          onTapCancel: widget.isEnabled
              ? () {
                  setState(() => _pressed = false);
                  widget.onPttStop?.call();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? colors.error
                  : widget.isEnabled
                      ? colors.primary
                      : colors.surfaceContainerHighest,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: colors.error.withAlpha(100),
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ]
                  : widget.isEnabled
                      ? [
                          BoxShadow(
                            color: colors.primary.withAlpha(30),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
            ),
            child: Center(
              child: Text(
                'PTT',
                style: TextStyle(
                  fontSize: widget.size * 0.18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: isActive || widget.isEnabled
                      ? colors.onPrimary
                      : colors.outline,
                ),
              ),
            ),
          ),
        ),
        if (widget.showLabel) ...[
          const SizedBox(height: 8),
          Text(
            isActive ? 'TRANSMITTING' : 'PUSH TO TALK',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: isActive ? colors.error : colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
