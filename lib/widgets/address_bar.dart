import 'package:flutter/material.dart';

class AddressBar extends StatelessWidget {
  final String address;
  final bool fromCache;
  final bool isLoading;
  final bool isFastAddress;

  const AddressBar({
    super.key,
    required this.address,
    required this.fromCache,
    required this.isLoading,
    this.isFastAddress = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = fromCache
        ? const Color(0xFFCC9000)
        : (isFastAddress ? Colors.cyan.shade300 : Colors.white70);
    final borderColor = fromCache
        ? const Color(0x40FF9500)
        : (isFastAddress ? const Color(0x401E90FF) : const Color(0x401E90FF));
    final icon = fromCache
        ? Icons.history_outlined
        : (isFastAddress ? Icons.speed_outlined : Icons.location_on_outlined);
    final iconColor = fromCache
        ? const Color(0xFFFF9500)
        : (isFastAddress ? const Color(0xFF00BCD4) : const Color(0xFF1E90FF));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFastAddress && !fromCache && !isLoading)
                  const Text('⏳ Memperbarui alamat akurat...',
                      style: TextStyle(color: Colors.cyan, fontSize: 9)),
                Text(address, style: TextStyle(color: color, fontSize: 11),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (isLoading) ...[
            const SizedBox(width: 6),
            const SizedBox(width: 8, height: 8,
                child: CircularProgressIndicator(strokeWidth: 1.2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFFFF9500)))),
          ],
        ],
      ),
    );
  }
}
