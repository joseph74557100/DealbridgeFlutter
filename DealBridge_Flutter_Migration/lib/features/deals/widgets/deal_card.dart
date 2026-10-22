import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../core/widgets/status_pill.dart';
import '../models/deal.dart';

/// Maps a deal status to its display colour.
Color dealStatusColor(String status) {
  switch (status) {
    case DealStatus.completed:
      return AppColors.success;
    case DealStatus.declined:
    case DealStatus.cancelled:
      return AppColors.danger;
    case DealStatus.accepted:
    case DealStatus.active:
      return AppColors.info;
    case DealStatus.expired:
      return AppColors.textSecondary;
    case DealStatus.flagged:
      return AppColors.warning;
    default:
      return AppColors.warning;
  }
}

/// The status pill used across deal surfaces.
class DealStatusPill extends StatelessWidget {
  const DealStatusPill({super.key, required this.deal, required this.currentUid});

  final Deal deal;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final label = deal.displayStatusFor(currentUid);
    return StatusPill(
      label: label,
      color: dealStatusColor(deal.status),
      dense: true,
    );
  }
}

/// The confirmation progress indicator for the current user.
class ConfirmationProgress extends StatelessWidget {
  const ConfirmationProgress({
    super.key,
    required this.deal,
    required this.currentUid,
  });

  final Deal deal;
  final String currentUid;

  @override
  Widget build(BuildContext context) {
    final mine = deal.confirmationFor(currentUid);
    final theirs = currentUid == deal.senderId
        ? deal.recipientConfirmationStatus
        : deal.senderConfirmationStatus;
    final mineLabel = _label(mine);
    final theirsLabel = _label(theirs);

    return Row(
      children: [
        Expanded(
          child: _ProgressTile(
            label: 'You',
            value: mineLabel,
            done: mine == ConfirmationStatus.confirmed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ProgressTile(
            label: 'Them',
            value: theirsLabel,
            done: theirs == ConfirmationStatus.confirmed,
          ),
        ),
      ],
    );
  }

  static String _label(String status) {
    switch (status) {
      case ConfirmationStatus.agreed:
        return 'Agreed';
      case ConfirmationStatus.confirmed:
        return 'Confirmed';
      default:
        return 'Reviewing';
    }
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.label,
    required this.value,
    required this.done,
  });

  final String label;
  final String value;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2435),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done ? AppColors.success : const Color(0xFF2C3A52),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: done ? AppColors.success : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: done ? AppColors.success : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single deal row.
class DealCard extends StatelessWidget {
  const DealCard({
    super.key,
    required this.deal,
    required this.currentUid,
    required this.onTap,
  });

  final Deal deal;
  final String currentUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final counterparty = deal.counterpartyName(currentUid);
    final subtitle = currentUid == deal.senderId
        ? 'From ${deal.senderName}'
        : 'To ${deal.businessName}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF273956),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.handshake_outlined,
                      color: Color(0xFF75A5FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deal.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          counterparty.isEmpty ? subtitle : counterparty,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  DealStatusPill(deal: deal, currentUid: currentUid),
                ],
              ),
              if (deal.value.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  deal.value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 13,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _timeLabel(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (deal.flagged)
                    const StatusPill(
                      label: 'Under review',
                      color: AppColors.warning,
                      dense: true,
                      icon: Icons.flag_outlined,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel() {
    if (deal.status == DealStatus.completed && deal.completedDate.isNotEmpty) {
      return 'Completed ${deal.completedDate}';
    }
    final created = AppFormatters.fromEpoch(deal.timestamp);
    if (created != null) return 'Created $created';
    if (deal.createdAt.isNotEmpty) return 'Created ${deal.createdAt}';
    return 'Recently';
  }
}
