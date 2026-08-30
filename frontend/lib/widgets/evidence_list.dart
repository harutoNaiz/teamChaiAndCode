import 'package:flutter/material.dart';
import '../models/retrieved_evidence.dart';
import '../theme/app_theme.dart';
import 'evidence_card.dart';

/// V2+V5: Horizontal scrollable list of EvidenceCards.
/// Renders nothing when the list is empty.
class EvidenceList extends StatelessWidget {
  final List<RetrievedEvidence> evidences;
  final ValueChanged<String>? onOpen;

  const EvidenceList({
    super.key,
    required this.evidences,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (evidences.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'SOURCES',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkTextTertiary
                : Colors.black45,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 190,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: evidences.length,
            itemBuilder: (ctx, i) => EvidenceCard(
              evidence: evidences[i],
              onOpen: onOpen,
            ),
          ),
        ),
      ],
    );
  }
}
