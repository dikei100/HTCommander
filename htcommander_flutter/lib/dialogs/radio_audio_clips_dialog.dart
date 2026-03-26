import 'package:flutter/material.dart';
import '../handlers/audio_clip_handler.dart';

/// Dialog for listing audio clips with play, delete, and rename actions.
/// Returns a map with 'action' ('play'/'delete'/'rename') and 'name' keys.
/// For rename, also includes 'newName'.
class RadioAudioClipsDialog extends StatefulWidget {
  final List<AudioClipEntry> clips;

  const RadioAudioClipsDialog({super.key, required this.clips});

  @override
  State<RadioAudioClipsDialog> createState() => _RadioAudioClipsDialogState();
}

class _RadioAudioClipsDialogState extends State<RadioAudioClipsDialog> {
  int _selectedIndex = -1;

  void _onPlay() {
    if (_selectedIndex < 0) return;
    Navigator.pop(context, <String, String>{
      'action': 'play',
      'name': widget.clips[_selectedIndex].name,
    });
  }

  void _onDelete() {
    if (_selectedIndex < 0) return;
    Navigator.pop(context, <String, String>{
      'action': 'delete',
      'name': widget.clips[_selectedIndex].name,
    });
  }

  void _onRename() {
    if (_selectedIndex < 0) return;
    final clip = widget.clips[_selectedIndex];
    final controller = TextEditingController(text: clip.name);

    showDialog<String>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RENAME CLIP',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: colors.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: TextField(
                      controller: controller,
                      style:
                          TextStyle(fontSize: 11, color: colors.onSurface),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: colors.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide:
                              BorderSide(color: colors.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: colors.primary),
                        ),
                        filled: true,
                        fillColor: colors.surfaceContainerLow,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('CANCEL',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: colors.onSurfaceVariant)),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(ctx, controller.text.trim()),
                        child: const Text('RENAME',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((newName) {
      controller.dispose();
      if (newName != null && newName.isNotEmpty && newName != clip.name) {
        Navigator.pop(context, <String, String>{
          'action': 'rename',
          'name': clip.name,
          'newName': newName,
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AUDIO CLIPS',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              if (widget.clips.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No audio clips',
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.clips.length,
                    itemBuilder: (context, index) {
                      final clip = widget.clips[index];
                      final isSelected = _selectedIndex == index;

                      return InkWell(
                        onTap: () =>
                            setState(() => _selectedIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.primary.withValues(alpha: 0.15)
                                : null,
                            border: Border(
                              bottom: BorderSide(
                                  color: colors.outlineVariant, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.audiotrack,
                                  size: 14,
                                  color: colors.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(clip.name,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: colors.onSurface)),
                              ),
                              if (clip.duration.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Text(clip.duration,
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: colors.onSurfaceVariant)),
                                ),
                              Text(clip.size,
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontFamily: 'monospace',
                                      color: colors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _selectedIndex >= 0 ? _onRename : null,
                    child: Text('RENAME',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: _selectedIndex >= 0
                                ? colors.onSurfaceVariant
                                : colors.onSurfaceVariant.withValues(alpha: 0.4))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _selectedIndex >= 0 ? _onDelete : null,
                    child: Text('DELETE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: _selectedIndex >= 0
                                ? colors.error
                                : colors.error.withValues(alpha: 0.4))),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _selectedIndex >= 0 ? _onPlay : null,
                    child: const Text('PLAY',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: colors.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
