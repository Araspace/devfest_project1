// One step of the 4-step agent flow (Extract → Check → Approve → Export).

import 'package:flutter/material.dart';

import '../theme.dart';

enum FlowState { idle, running, done, warning, failed, waiting, skipped }

class FlowStep {
  FlowStep(this.title, this.agent, this.icon);
  final String title;
  final String agent;
  final IconData icon;
  FlowState state = FlowState.idle;
  String summary = '';
}

class StepRow extends StatelessWidget {
  const StepRow({super.key, required this.step, required this.last});
  final FlowStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, badge) = switch (step.state) {
      FlowState.idle => (Brand.cream, Brand.muted, null),
      FlowState.running => (Brand.purpleSoft, Brand.purple, null),
      FlowState.done => (Brand.purpleSoft, Brand.purple, Icons.check_circle),
      FlowState.warning => (Brand.orangeSoft, Brand.orangeDark, Icons.warning_rounded),
      FlowState.waiting => (Brand.orangeSoft, Brand.orangeDark, Icons.hourglass_top_rounded),
      FlowState.failed => (const Color(0xFFFEE2E2), Brand.red, Icons.cancel),
      FlowState.skipped => (Brand.cream, Brand.muted, Icons.remove_circle_outline),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
                    child: step.state == FlowState.running
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Brand.purple),
                          )
                        : Icon(step.icon, color: step.state == FlowState.idle ? Brand.muted : Brand.purple),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(badge, size: 18, color: fg),
                      ),
                    ),
                ],
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 6), color: Brand.line),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: last ? 4 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(step.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(step.agent, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.summary.isEmpty ? 'Waiting' : step.summary,
                    style: TextStyle(color: step.state == FlowState.idle ? Brand.muted : fg),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
