import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/status_pill.dart';
import 'agreement_details_screen.dart';
import 'data/agreement_repository.dart';
import 'models/agreement.dart';

/// The completed-deal agreement vault.
class AgreementsScreen extends StatefulWidget {
  const AgreementsScreen({super.key, this.repository});

  /// Overrides the repository, which keeps the screen testable.
  final AgreementRepository? repository;

  @override
  State<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends State<AgreementsScreen> {
  late final AgreementRepository _repository =
      widget.repository ?? AgreementRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agreements')),
      body: StreamBuilder<List<Agreement>>(
        stream: _repository.watchMyAgreements(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StateMessage.error(
              title: 'Could not load agreements',
              subtitle: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final agreements = snapshot.data ?? const <Agreement>[];
          if (agreements.isEmpty) {
            return const StateMessage.empty(
              title: 'No agreements yet',
              subtitle:
                  'An agreement is created automatically once a deal is '
                  'completed.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: agreements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final agreement = agreements[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    agreement.title.isEmpty
                        ? 'Untitled agreement'
                        : agreement.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      agreement.businessOneName,
                      agreement.businessTwoName,
                    ].where((v) => v.isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusPill(
                    label: agreement.status,
                    color: agreement.isSigned
                        ? AppColors.success
                        : AppColors.warning,
                    dense: true,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AgreementDetailsScreen(
                        agreementId: agreement.id,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A compact summary line used by the profile screen.
String agreementSummary(Agreement agreement) {
  final created = agreement.createdLabel;
  if (created == null || created.isEmpty) return agreement.status;
  return '${agreement.status} • $created';
}

/// Formats the signing deadline of an agreement for list rows.
String agreementExpiryLabel(Agreement agreement) {
  final expiry = agreement.expiryDate;
  if (expiry.isEmpty) return '';
  final parsed = AppFormatters.parseDateTime(expiry);
  return parsed == null ? expiry : AppFormatters.date(parsed);
}
