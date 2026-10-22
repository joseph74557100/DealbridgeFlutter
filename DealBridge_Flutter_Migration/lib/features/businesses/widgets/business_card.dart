import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_pill.dart';
import '../models/business.dart';

/// A business row used in the directory and in "my businesses".
class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.business,
    required this.onTap,
    this.trailing,
    this.showOwner = false,
  });

  final Business business;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(business: business),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            business.name.isEmpty
                                ? 'Unnamed business'
                                : business.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (business.isGenuinelyVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 16,
                            color: AppColors.info,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (business.category.isNotEmpty)
                          StatusPill(
                            label: business.category,
                            color: AppColors.primarySoft,
                            dense: true,
                          ),
                        if (business.ratingCount > 0)
                          StatusPill(
                            label:
                                '${business.rating.toStringAsFixed(1)} ★ (${business.ratingCount})',
                            color: AppColors.warning,
                            dense: true,
                            icon: Icons.star,
                          ),
                        if (business.isGenuinelyVerified)
                          const StatusPill(
                            label: 'Verified',
                            color: AppColors.info,
                            dense: true,
                            icon: Icons.verified,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    if (showOwner) {
      return business.city.isEmpty ? 'Owner' : 'Owner • ${business.city}';
    }
    final parts = <String>[
      if (business.category.isNotEmpty) business.category,
      if (business.city.isNotEmpty) business.city,
    ];
    return parts.isEmpty ? 'Business' : parts.join(' • ');
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF273956),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        business.name.isEmpty
            ? '?'
            : business.name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
      ),
    );

    if (business.logoUrl.isEmpty) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        business.logoUrl,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
