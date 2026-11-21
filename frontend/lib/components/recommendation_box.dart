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
      'approve' => 'Approver agent recommends: approve',
      'reject' => 'Approver agent recommends: reject',
      _ => 'Approver agent recommends: human review',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.purpleSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome, color: Brand.purple, size: 20),
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
