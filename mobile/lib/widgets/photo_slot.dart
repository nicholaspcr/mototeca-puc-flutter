import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// A photo chosen but not yet uploaded. Bytes are held in memory because the
/// upload only happens once the record exists to attach them to.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Tapping adds photos (or replaces the invoice); the corner button clears
/// the slot.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({
    super.key,
    required this.label,
    required this.photos,
    required this.onTap,
    required this.onClear,
    this.icon = Icons.add_a_photo_outlined,
  });

  final String label;
  final List<PickedPhoto> photos;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cover = photos.firstOrNull;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.controlRadius),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: MtColors.slate50,
          border: Border.all(
            color: cover == null ? MtColors.slate200 : MtColors.petrol,
          ),
          borderRadius: BorderRadius.circular(MtSizes.controlRadius),
        ),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: cover == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: const Color(0xFF94A3B8)),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: MtColors.slate500,
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(cover.bytes, fit: BoxFit.cover),
                  if (photos.length > 1)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _Badge(child: Text('${photos.length} fotos')),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remover',
                      onPressed: onClear,
                      icon: const _Badge(
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: MtColors.graphite.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 11, color: Colors.white),
        child: child,
      ),
    );
  }
}
