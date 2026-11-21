// The Approver agent's recommendation, shown above the human decision buttons.

import 'package:belegguard_shared/models.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class RecommendationBox extends StatelessWidget {
  const RecommendationBox({super.key, required this.recommendation});
  final ApprovalRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final r = recommendation;
    final label = switch (r.decision) {
      'approve' => 'Approver agent: approve',
      'reject' => 'Approver agent: reject',
      _ => 'Approver agent: needs human review',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.accentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.fact_check_outlined, color: Brand.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (r.reasoning.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(r.reasoning, style: const TextStyle(color: Brand.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
