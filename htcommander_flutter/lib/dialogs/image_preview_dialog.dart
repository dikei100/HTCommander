import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dialog for displaying and optionally saving an image.
///
/// Accepts either raw ARGB pixel data or a file path.
class ImagePreviewDialog extends StatelessWidget {
  /// Title shown in the dialog header.
  final String title;

  /// Raw ARGB pixel data (if provided, rendered as an image).
  final Int32List? pixels;

  /// Image dimensions (required if pixels are provided).
  final int? width;
  final int? height;

  /// Path to an image file on disk.
  final String? filePath;

  /// Optional save callback. If provided, a "Save" button is shown.
  final void Function(String savePath)? onSave;

  const ImagePreviewDialog({
    super.key,
    this.title = 'IMAGE PREVIEW',
    this.pixels,
    this.width,
    this.height,
    this.filePath,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget imageWidget;
    if (filePath != null) {
      imageWidget = Image.file(File(filePath!), fit: BoxFit.contain);
    } else if (pixels != null && width != null && height != null) {
      imageWidget = FutureBuilder<ui.Image>(
        future: _createImageFromPixels(pixels!, width!, height!),
        builder: (ctx, snap) {
          if (snap.hasData) {
            return RawImage(image: snap.data, fit: BoxFit.contain);
          }
          return const Center(child: CircularProgressIndicator());
        },
      );
    } else {
      imageWidget = Center(
          child: Text('No image data',
              style: TextStyle(color: colors.onSurfaceVariant)));
    }

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              Container(
                height: 360,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: imageWidget,
                ),
              ),
              if (width != null && height != null) ...[
                const SizedBox(height: 8),
                Text('${width}x$height',
                    style: TextStyle(
                        fontSize: 10, color: colors.onSurfaceVariant)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onSave != null) ...[
                    FilledButton.tonal(
                      onPressed: () => _showSaveDialog(context),
                      child: const Text('SAVE',
                          style: TextStyle(fontSize: 10, letterSpacing: 1)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('CLOSE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              color: colors.onSurfaceVariant))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSaveDialog(BuildContext context) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Save path',
                  hintText: '/path/to/save.png',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CANCEL')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('SAVE')),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (path != null && path.isNotEmpty && onSave != null) {
      onSave!(path);
    }
  }

  static Future<ui.Image> _createImageFromPixels(
      Int32List pixels, int width, int height) async {
    final bytes = Uint8List.view(pixels.buffer);
    final codec = await ui.instantiateImageCodec(
      _encodeRgba(bytes, width, height),
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Converts ARGB pixel data to a minimal BMP for rendering.
  static Uint8List _encodeRgba(Uint8List argbBytes, int width, int height) {
    // Use raw RGBA via decodeImageFromPixels approach
    // For simplicity, create a 32-bit BMP
    final rowSize = width * 4;
    final imageSize = rowSize * height;
    final fileSize = 122 + imageSize; // headers + pixel data

    final bmp = Uint8List(fileSize);
    final bd = ByteData.view(bmp.buffer);

    // BMP header
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    bd.setUint32(2, fileSize, Endian.little);
    bd.setUint32(10, 122, Endian.little); // pixel data offset

    // DIB header (BITMAPV4HEADER)
    bd.setUint32(14, 108, Endian.little); // header size
    bd.setInt32(18, width, Endian.little);
    bd.setInt32(22, -height, Endian.little); // top-down
    bd.setUint16(26, 1, Endian.little); // planes
    bd.setUint16(28, 32, Endian.little); // bits per pixel
    bd.setUint32(30, 3, Endian.little); // BI_BITFIELDS
    bd.setUint32(34, imageSize, Endian.little);

    // Channel masks (RGBA)
    bd.setUint32(54, 0x00FF0000, Endian.little); // R
    bd.setUint32(58, 0x0000FF00, Endian.little); // G
    bd.setUint32(62, 0x000000FF, Endian.little); // B
    bd.setUint32(66, 0xFF000000, Endian.little); // A

    // Copy pixel data (ARGB → BGRA for BMP)
    for (var i = 0; i < width * height; i++) {
      final srcOff = i * 4;
      final dstOff = 122 + i * 4;
      if (srcOff + 3 < argbBytes.length) {
        bmp[dstOff] = argbBytes[srcOff + 2]; // B
        bmp[dstOff + 1] = argbBytes[srcOff + 1]; // G
        bmp[dstOff + 2] = argbBytes[srcOff]; // R (was A in ARGB Int32)
        bmp[dstOff + 3] = argbBytes[srcOff + 3]; // A
      }
    }

    return bmp;
  }
}
