import 'package:flutter/material.dart';
import '../core/constants.dart';

class LayoutPickerSheet extends StatelessWidget {
  final WatermarkLayout current;
  final ValueChanged<WatermarkLayout> onSelect;

  const LayoutPickerSheet({
    super.key,
    required this.current,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Pilih Gaya Watermark',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ...WatermarkLayout.values.map((l) {
          final selected = l == current;
          return ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1E90FF).withOpacity(0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(8),
                border: selected
                    ? Border.all(color: const Color(0xFF1E90FF), width: 1.5)
                    : null,
              ),
              child: Icon(
                _iconFor(l),
                color: selected ? const Color(0xFF1E90FF) : Colors.white38,
                size: 18,
              ),
            ),
            title: Text(
              l.displayName,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              l.description,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
            onTap: () => onSelect(l),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  IconData _iconFor(WatermarkLayout l) {
    switch (l) {
      case WatermarkLayout.podCorporate:
        return Icons.article_rounded;
      case WatermarkLayout.podDarkField:
        return Icons.camera_alt_rounded;
      case WatermarkLayout.podGovern:
        return Icons.verified_rounded;
    }
  }
}
