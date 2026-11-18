import 'package:flutter/services.dart' show TextEditingValue, TextInputFormatter, TextInputType, TextSelection;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../lyrics/lrclib_provider.dart';
import '../lyrics/netease_provider.dart';
import '../state/lyrics_settings.dart';

/// The "Lyrics" block of the settings screen: where lyrics come from (your
/// server and/or internet providers), NetEase translations, and a timing
/// offset.
class LyricsSettingsSection extends StatelessWidget {
  const LyricsSettingsSection({super.key});

  static const _providerLabels = {
    NeteaseProvider.providerId: 'NetEase',
    LrcLibProvider.providerId: 'lrclib.net',
  };

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<LyricsSettings>();
    final theme = M3ETheme.of(context);
    final online = settings.fetchFromInternet;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lyrics', style: theme.typography.emphasized.titleSmall),
        const SizedBox(height: 8),
        M3EList(
          variant: M3ECardVariant.filled,
          itemCount: 5,
          onTap: (index) {
            switch (index) {
              case 0:
                settings.setPreferLocal(!settings.preferLocal);
              case 1:
                settings.setFetchFromInternet(!online);
              case 3:
                if (online) settings.setNeteaseTranslations(!settings.neteaseTranslations);
            }
          },
          itemBuilder: (context, index) {
            switch (index) {
              case 0:
                return M3EListItem(
                  leading: const Icon(M3EIcons.dns),
                  headline: 'Prefer local lyrics',
                  supportingText: 'Use lyrics from your server before looking on the internet',
                  trailing: M3ESwitch(value: settings.preferLocal, onChanged: settings.setPreferLocal),
                );
              case 1:
                return M3EListItem(
                  leading: const Icon(M3EIcons.cloud_download),
                  headline: 'Fetch lyrics from the internet',
                  supportingText:
                      'When your server has none, look them up on the providers below. '
                      "This sends the song's artist, title, album and length to those services.",
                  trailing: M3ESwitch(value: online, onChanged: settings.setFetchFromInternet),
                );
              case 2:
                return _ProvidersRow(settings: settings, labels: _providerLabels);
              case 3:
                return M3EListItem(
                  leading: const Icon(M3EIcons.translate),
                  headline: 'Enable NetEase translations',
                  supportingText: 'Show NetEase\'s translated lyrics under each line when it has them',
                  enabled: online,
                  trailing: M3ESwitch(
                    value: settings.neteaseTranslations,
                    onChanged: online ? settings.setNeteaseTranslations : null,
                  ),
                );
              default:
                return _OffsetRow(settings: settings);
            }
          },
        ),
      ],
    );
  }
}

class _ProvidersRow extends StatelessWidget {
  const _ProvidersRow({required this.settings, required this.labels});

  final LyricsSettings settings;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final online = settings.fetchFromInternet;
    final order = settings.providerIds.map((id) => labels[id] ?? id).join(' → ');

    return Opacity(
      opacity: online ? 1 : 0.38,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Providers to fetch lyrics from', style: theme.typography.baseline.bodyLarge),
            const SizedBox(height: 2),
            Text(
              order.isEmpty ? 'No provider selected' : 'Tried in this order: $order',
              style: theme.typography.baseline.bodyMedium.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in LyricsSettings.allProviderIds)
                  M3EChip(
                    label: labels[id] ?? id,
                    type: M3EChipType.filter,
                    selected: settings.isProviderEnabled(id),
                    onPressed: online
                        ? () => settings.setProviderEnabled(id, !settings.isProviderEnabled(id))
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OffsetRow extends StatefulWidget {
  const _OffsetRow({required this.settings});

  final LyricsSettings settings;

  @override
  State<_OffsetRow> createState() => _OffsetRowState();
}

class _OffsetRowState extends State<_OffsetRow> {
  /// What the ± buttons add or subtract.
  static const _step = 100;

  late final TextEditingController _controller = TextEditingController(text: '${widget.settings.offsetMs}');
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    // "" and "-" are on the way to a number; keep the saved value meanwhile.
    final value = int.tryParse(text);
    if (value != null) widget.settings.setOffsetMs(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final offset = widget.settings.offsetMs;

    // Reflect changes made by the ± buttons (or clamping), but never fight
    // the user while they're typing.
    if (!_focus.hasFocus && _controller.text != '$offset') {
      _controller.text = '$offset';
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lyric offset (ms)', style: theme.typography.baseline.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  'Positive shows lyrics later, negative earlier',
                  style: theme.typography.baseline.bodyMedium.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          M3EIconButton(
            icon: const Icon(M3EIcons.remove),
            onPressed: () => widget.settings.setOffsetMs(offset - _step),
          ),
          SizedBox(
            width: 96,
            child: M3ETextField(
              controller: _controller,
              focusNode: _focus,
              suffixText: 'ms',
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [_SignedIntFormatter()],
              textAlign: TextAlign.end,
              onChanged: _onChanged,
            ),
          ),
          M3EIconButton(
            icon: const Icon(M3EIcons.add),
            onPressed: () => widget.settings.setOffsetMs(offset + _step),
          ),
        ],
      ),
    );
  }
}

/// Keeps a text field to an optional leading minus followed by at most five
/// digits, however the text got there (typed, pasted, autofilled): anything
/// else is dropped rather than rejecting the whole edit.
class _SignedIntFormatter extends TextInputFormatter {
  static const _maxDigits = 5;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final negative = newValue.text.startsWith('-');
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > _maxDigits) digits = digits.substring(0, _maxDigits);

    final cleaned = '${negative ? '-' : ''}$digits';
    if (cleaned == newValue.text) return newValue;
    return TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
  }
}
