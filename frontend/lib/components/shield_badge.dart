// Small pill showing whether the backend's injection guard (SHIELD) is on.
import 'package:flutter/material.dart';

import '../theme.dart';

class ShieldBadge extends StatelessWidget {
  const ShieldBadge({super.key, required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Brand.ok : Brand.danger;
    return Tooltip(
      message: on ? 'Injection guard active' : 'Injection guard disabled (demo only)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? Brand.okSoft : Brand.dangerSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.verified_user_outlined : Icons.gpp_bad_outlined, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              on ? 'Shield on' : 'Shield off',
              style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
