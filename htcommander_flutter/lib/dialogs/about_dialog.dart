/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

/// About dialog showing version and project links.
class AboutAppDialog extends StatelessWidget {
  final String version;
  final void Function(String url)? onLinkTap;

  const AboutAppDialog({super.key, required this.version, this.onLinkTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ABOUT HTCOMMANDER-X',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Version $version',
                style: TextStyle(fontSize: 11, color: colors.onSurface),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => onLinkTap?.call('https://github.com/dikei100/HTCommander-X'),
                child: Text(
                  'GitHub (Fork)',
                  style: TextStyle(fontSize: 11, color: colors.primary),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => onLinkTap?.call('https://github.com/Ylianst/HTCommander'),
                child: Text(
                  'Original Project',
                  style: TextStyle(fontSize: 11, color: colors.primary),
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => onLinkTap?.call('https://www.apache.org/licenses/LICENSE-2.0'),
                child: Text(
                  'Apache License 2.0',
                  style: TextStyle(fontSize: 11, color: colors.primary),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'CLOSE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
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
