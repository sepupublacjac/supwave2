import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../models/song.dart';
import '../state/offline_manager.dart';

/// Starts or cancels an offline download for [song] and confirms it with a
/// snackbar. Shared by the player's "..." menu, the per-song context menu,
/// and the main player's offline indicator button, so the confirmation
/// message stays consistent everywhere "Available offline" is toggled.
void setOfflineWithFeedback(
  BuildContext context,
  OfflineManager offline,
  Song song,
  bool wantOffline,
) {
  if (wantOffline) {
    offline.download(song);
    M3ESnackbar.show(context, message: 'Downloading "${song.title}" for offline playback…');
  } else {
    offline.remove(song);
    M3ESnackbar.show(context, message: 'Removed "${song.title}" from offline downloads');
  }
}
