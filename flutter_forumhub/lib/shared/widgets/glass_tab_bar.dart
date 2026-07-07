import 'package:flutter/material.dart';
import 'package:flutter_forumhub/app/theme/app_theme.dart';

class GlassTabDestination {
  const GlassTabDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final List<GlassTabDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withValues(alpha: 0.92),
                const Color(0xFFF4E8D3).withValues(alpha: 0.78),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.86),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppTheme.ink.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: List<Widget>.generate(destinations.length, (int index) {
                final GlassTabDestination item = destinations[index];
                final bool isSelected = index == currentIndex;

                return Expanded(
                  child: _GlassTabButton(
                    destination: item,
                    isSelected: isSelected,
                    onTap: () => onSelected(index),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTabButton extends StatelessWidget {
  const _GlassTabButton({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final GlassTabDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = isSelected ? AppTheme.ink : AppTheme.secondaryInk;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.48)
                  : Colors.transparent,
              border: isSelected
                  ? Border.all(color: Colors.white.withValues(alpha: 0.72))
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isSelected ? destination.selectedIcon : destination.icon,
                  color: foregroundColor,
                  size: 21,
                ),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
