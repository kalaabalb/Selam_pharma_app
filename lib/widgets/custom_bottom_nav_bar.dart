import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

const Color _kPrimary = Color(0xFF007BFF);
const Color _kMuted = Color(0xFF6C757D);

class CustomBottomNavBar extends StatelessWidget {
  final dynamic pharmacyProvider;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onHome;
  final VoidCallback onRegister;
  final VoidCallback onChat;
  final VoidCallback onReports;
  final VoidCallback onAudit;

  const CustomBottomNavBar({
    super.key,
    required this.pharmacyProvider,
    required this.selectedIndex,
    required this.onSelect,
    required this.onHome,
    required this.onRegister,
    required this.onChat,
    required this.onReports,
    required this.onAudit,
  });

  Widget _buildItem({
    required BuildContext context,
    required int index,
    required IconData outlined,
    required IconData filled,
    required String label,
    required VoidCallback onTap,
    int badgeCount = 0,
    bool showBadges = true,
  }) {
    final active = selectedIndex == index;
    const iconSize = 24.0;
    return Expanded(
      child: InkWell(
        onTap: () {
          onSelect(index);
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(
                    width: 36,
                    height: 32,
                    child: Center(
                      child: Icon(
                        active ? filled : outlined,
                        size: iconSize,
                        color: active ? _kPrimary : _kMuted,
                      ),
                    ),
                  ),
                  if (showBadges && badgeCount > 0)
                    Positioned(
                      right: 0,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _kPrimary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? _kPrimary : _kMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final newReports = (pharmacyProvider?.newReportsCount ?? 0) as int;
    final settingsBox = Hive.box('settings');

    // listen so that toggling the badge preference rebuilds the bar
    return ValueListenableBuilder<Box>(
      valueListenable: settingsBox.listenable(keys: ['show_badges']),
      builder: (context, box, _) {
        final showBadges = box.get('show_badges', defaultValue: true) as bool;
        return BottomAppBar(
          elevation: 8,
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Container(
            height: 64 + bottomInset,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildItem(
                  context: context,
                  index: 0,
                  outlined: Icons.home_outlined,
                  filled: Icons.home,
                  label: 'Home',
                  onTap: onHome,
                  showBadges: showBadges,
                ),
                _buildItem(
                  context: context,
                  index: 1,
                  outlined: Icons.chat_bubble_outline,
                  filled: Icons.chat_bubble,
                  label: 'Chat',
                  onTap: onChat,
                  showBadges: showBadges,
                ),
                SizedBox(
                  width: 76,
                  child: Center(
                    child: InkWell(
                      onTap: onRegister,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _kPrimary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(
                                (0.12 * 255).round(),
                              ),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
                _buildItem(
                  context: context,
                  index: 2,
                  outlined: Icons.bar_chart_outlined,
                  filled: Icons.bar_chart,
                  label: 'Reports',
                  onTap: onReports,
                  badgeCount: newReports,
                  showBadges: showBadges,
                ),
                _buildItem(
                  context: context,
                  index: 3,
                  outlined: Icons.assessment_outlined,
                  filled: Icons.assessment,
                  label: 'Audit',
                  onTap: onAudit,
                  showBadges: showBadges,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
