import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/sounds.dart';
import '../../../core/haptics.dart';

/// Grouped tone picker shared by the editor and settings.
///
/// Returns the selected sound id, or null when dismissed.
Future<String?> showSoundPickerSheet(
  BuildContext context, {
  required String currentId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => _SoundSheet(currentId: currentId),
  );
}

class _SoundSheet extends StatefulWidget {
  const _SoundSheet({required this.currentId});

  final String currentId;

  @override
  State<_SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<_SoundSheet> {
  late String _selected = widget.currentId;

  Future<void> _preview(String id) async {
    await hapticTap();
    if (id == 'system') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('System sound plays at fire time')),
      );
      return;
    }
    try {
      final player = AudioPlayer();
      unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
      await player.play(AssetSource('sounds/$id.wav'));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not preview this tone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RadioGroup<String>(
        groupValue: _selected,
        onChanged: (value) async {
          await hapticTap();
          if (value == null) return;
          setState(() => _selected = value);
          if (context.mounted) Navigator.pop(context, value);
        },
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Alarm tone',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final category in soundCategories) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  category.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              for (final sound in alarmSounds.where(
                  (s) => s.category == category))
                RadioListTile<String>(
                  value: sound.id,
                  title: Text(sound.label,
                      style: Theme.of(context).textTheme.titleMedium),
                  secondary: sound.id == 'system'
                      ? null
                      : IconButton(
                          tooltip: 'Preview ${sound.label}',
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _preview(sound.id),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
