import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// V3: Grounded response state enum and banner widget.
/// None of these states may display fabricated content.
enum GroundedState {
  retrievalPending,
  noResults,
  sourceRevoked,
  indexFailure,
  modelFailure,
  uncitedAnswer,
  cloudPrivacyNotice,
}

class GroundedStateBanner extends StatelessWidget {
  final GroundedState state;
  final String? cloudModelName;

  const GroundedStateBanner({
    super.key,
    required this.state,
    this.cloudModelName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _config(state, cloudModelName);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: config.bgColor.withOpacity(isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: config.bgColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          if (state == GroundedState.retrievalPending)
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: config.bgColor,
              ),
            )
          else
            Icon(config.icon, size: 14, color: config.bgColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              config.message,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: config.bgColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _BannerConfig _config(GroundedState s, String? modelName) {
    switch (s) {
      case GroundedState.retrievalPending:
        return _BannerConfig(
          AppTheme.brandAccent,
          Icons.manage_search_rounded,
          'Searching device index…',
        );
      case GroundedState.noResults:
        return _BannerConfig(
          Colors.grey,
          Icons.search_off_rounded,
          'No matching sources found on device.',
        );
      case GroundedState.sourceRevoked:
        return _BannerConfig(
          Colors.orange,
          Icons.lock_outlined,
          'Source permission revoked — answer cannot be verified.',
        );
      case GroundedState.indexFailure:
        return _BannerConfig(
          Colors.red,
          Icons.storage_rounded,
          'Index unavailable — check device storage.',
        );
      case GroundedState.modelFailure:
        return _BannerConfig(
          Colors.red,
          Icons.error_outline_rounded,
          'Model response failed.',
        );
      case GroundedState.uncitedAnswer:
        return _BannerConfig(
          Colors.amber.shade700,
          Icons.warning_amber_rounded,
          'Answer references device content but cites no source.',
        );
      case GroundedState.cloudPrivacyNotice:
        return _BannerConfig(
          Colors.blueGrey,
          Icons.cloud_outlined,
          'Sending to cloud model${modelName != null ? ': $modelName' : ''}.',
        );
    }
  }
}

class _BannerConfig {
  final Color bgColor;
  final IconData icon;
  final String message;
  const _BannerConfig(this.bgColor, this.icon, this.message);
}
