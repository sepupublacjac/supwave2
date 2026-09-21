import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/library_controller.dart';
import '../state/offline_manager.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final typography = M3ETheme.of(context).typography;
    final auth = context.watch<AuthController>();
    final library = context.watch<LibraryController>();
    final offline = context.watch<OfflineManager>();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const M3EAppBar.sliver(titleText: 'Settings', variant: M3EAppBarVariant.small),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Server', style: typography.emphasized.titleSmall),
                  const SizedBox(height: 8),
                  M3ECardList(
                    variant: M3ECardVariant.filled,
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      switch (index) {
                        case 0:
                          return M3EListItem(
                            leading: const Icon(M3EIcons.dns),
                            headline: 'Server URL',
                            supportingText: auth.serverUrl ?? '',
                          );
                        case 1:
                          return M3EListItem(
                            leading: const Icon(M3EIcons.person),
                            headline: 'Username',
                            supportingText: auth.username ?? '',
                          );
                        default:
                          return M3EListItem(
                            leading: const Icon(M3EIcons.music_note),
                            headline: 'Total songs',
                            supportingText: '${library.totalSongCount}',
                          );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('Storage', style: typography.emphasized.titleSmall),
                  const SizedBox(height: 8),
                  M3ECardList(
                    variant: M3ECardVariant.filled,
                    itemCount: 2,
                    onTap: (index) async {
                      if (index != 1 || offline.downloadedCount == 0) return;
                      await context.read<OfflineManager>().removeAll();
                      if (context.mounted) {
                        M3ESnackbar.show(context, message: 'Downloads cleared');
                      }
                    },
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return M3EListItem(
                          leading: const Icon(M3EIcons.download_done),
                          headline: 'Downloaded songs',
                          supportingText: '${offline.downloadedCount}',
                        );
                      }
                      return const M3EListItem(
                        leading: Icon(M3EIcons.delete_sweep),
                        headline: 'Clear downloads',
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  M3EButton(
                    style: M3EButtonStyle.outlined,
                    onPressed: () => context.read<AuthController>().logout(),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
