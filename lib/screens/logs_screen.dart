import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_logger.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  IconData _iconFor(LogLevel level) {
    switch (level) {
      case LogLevel.info:
        return M3EIcons.info;
      case LogLevel.warning:
        return M3EIcons.warning;
      case LogLevel.error:
        return M3EIcons.error;
    }
  }

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: AppLogger.instance,
        builder: (context, _) {
          final entries = AppLogger.instance.entries;
          final typography = M3ETheme.of(context).typography;
          final colorScheme = M3ETheme.of(context).colorScheme;

          return CustomScrollView(
            slivers: [
              const M3EAppBar.sliver(
                titleText: 'Logs',
                variant: M3EAppBarVariant.small,
              ),
              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No logs yet',
                      style: typography.baseline.bodyMedium.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => const M3EDivider(),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return M3EListItem(
                        leading: Icon(_iconFor(entry.level), color: colorScheme.onSurfaceVariant),
                        headline: entry.message,
                        supportingText: _formatTime(entry.time),
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}
