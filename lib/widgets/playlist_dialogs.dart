import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// Prompts for a new playlist name. Returns the trimmed name, or `null` if
/// cancelled/dismissed without entering one.
Future<String?> showCreatePlaylistDialog(BuildContext context) {
  return M3EDialog.show<String>(context, dialog: const _CreatePlaylistDialog());
}

/// Confirms deleting [playlistName]. Returns whether the user confirmed.
Future<bool> showConfirmDeletePlaylistDialog(BuildContext context, String playlistName) async {
  final confirmed = await M3EDialog.show<bool>(
    context,
    dialog: _ConfirmDeletePlaylistDialog(playlistName: playlistName),
  );
  return confirmed ?? false;
}

class _ConfirmDeletePlaylistDialog extends StatelessWidget {
  const _ConfirmDeletePlaylistDialog({required this.playlistName});

  final String playlistName;

  @override
  Widget build(BuildContext context) {
    // Uses this widget's own context (a descendant of the dialog's route),
    // not whatever context the caller happened to show the dialog from -
    // M3EDialog.show pushes onto the root navigator (via showGeneralDialog),
    // which may not be the nearest one at the call site.
    return M3EDialog(
      title: 'Delete playlist?',
      icon: const Icon(M3EIcons.delete_outline),
      content: Text('This permanently deletes "$playlistName" from your Navidrome server.'),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        M3EButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final _controller = TextEditingController();
  bool _canCreate = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canCreate = _controller.text.trim().isNotEmpty;
      if (canCreate != _canCreate) setState(() => _canCreate = canCreate);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return M3EDialog(
      title: 'New playlist',
      icon: const Icon(M3EIcons.playlist_add),
      content: M3ETextField(
        controller: _controller,
        label: 'Playlist name',
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        M3EButton(
          style: M3EButtonStyle.text,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        M3EButton(
          onPressed: _canCreate ? _submit : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
