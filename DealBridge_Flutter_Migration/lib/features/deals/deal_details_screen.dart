import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/functions_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/app_formatters.dart';
import '../../core/widgets/state_message.dart';
import '../agreements/data/agreement_repository.dart';
import '../agreements/agreement_details_screen.dart';
import '../businesses/data/business_repository.dart';
import 'data/deal_repository.dart';
import 'models/deal.dart';
import 'widgets/deal_card.dart';

class DealDetailsScreen extends StatefulWidget {
  const DealDetailsScreen({super.key, required this.dealId});

  final String dealId;

  @override
  State<DealDetailsScreen> createState() => _DealDetailsScreenState();
}

class _DealDetailsScreenState extends State<DealDetailsScreen> {
  final _repository = DealRepository();
  final _functions = FunctionsService();

  bool _busy = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: AppColors.success),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmCancel(Deal deal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this deal?'),
        content: const Text(
          'The other party will be notified. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep deal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel deal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _functions.cancelDeal(deal.id),
      'Deal cancelled.',
    );
  }

  Future<void> _fileDispute(Deal deal) async {
    final result = await showModalBottomSheet<_DisputeInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DisputeSheet(),
    );
    if (result == null || !mounted) return;

    await _run(
      () => _functions.fileDealDispute(
        dealId: deal.id,
        businessId: deal.businessId,
        reason: result.reason,
        description: result.description,
      ),
      'Dispute filed. The DealBridge team has been notified.',
    );
  }

  Future<void> _rateBusiness(Deal deal) async {
    final result = await showModalBottomSheet<_RatingInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _RatingSheet(),
    );
    if (result == null || !mounted) return;

    await _run(
      () => BusinessRepository().rateBusiness(
        businessId: deal.businessId,
        dealId: deal.id,
        stars: result.stars,
        comment: result.comment,
      ),
      'Thanks for your rating.',
    );
  }

  Future<void> _hideDeal() async {
    await _run(
      () => _repository.hideDeal(widget.dealId),
      'Deal hidden from your list.',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deal details'),
        actions: [
          IconButton(
            tooltip: 'Hide deal',
            onPressed: _busy ? null : _hideDeal,
            icon: const Icon(Icons.visibility_off_outlined),
          ),
        ],
      ),
      body: StreamBuilder<Deal?>(
        stream: _repository.watchDeal(widget.dealId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StateMessage.error(
              title: 'Could not load this deal',
              subtitle: snapshot.error.toString(),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final deal = snapshot.data;
          if (deal == null) {
            return const StateMessage.error(
              title: 'Deal not found',
              subtitle: 'It may have been removed or you may not have access.',
            );
          }
          return _body(deal);
        },
      ),
    );
  }

  Widget _body(Deal deal) {
    final isSender = deal.isSender(_uid);
    final isRecipient = deal.isRecipient(_uid);
    final mine = deal.confirmationFor(_uid);
    final canRespond = isRecipient && deal.status == DealStatus.pending;
    final canConfirm = (isSender || isRecipient) &&
        (deal.status == DealStatus.pending || deal.status == DealStatus.accepted) &&
        mine != ConfirmationStatus.confirmed &&
        !deal.hasBothConfirmed;
    final canDispute = deal.status == DealStatus.accepted ||
        deal.status == DealStatus.completed;
    final canRate = deal.status == DealStatus.completed &&
        deal.businessId.isNotEmpty &&
        !isSender;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        deal.title.isEmpty ? 'Untitled deal' : deal.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    DealStatusPill(deal: deal, currentUid: _uid),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isSender
                      ? 'To ${deal.businessName}'
                      : 'From ${deal.senderName}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                if (deal.value.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    deal.value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirmation progress',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ConfirmationProgress(deal: deal, currentUid: _uid),
                if (deal.terms.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Terms',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    deal.terms,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _DetailRow(label: 'Status', value: deal.displayStatusFor(_uid)),
                _DetailRow(label: 'Business', value: deal.businessName),
                _DetailRow(label: 'Amount', value: deal.value.isEmpty ? 'Not specified' : deal.value),
                _DetailRow(
                  label: 'Created',
                  value: AppFormatters.fromEpoch(deal.timestamp) ?? deal.createdAt,
                ),
                _DetailRow(label: 'Expires', value: deal.expiryLabel ?? 'No deadline'),
                if (deal.completedDate.isNotEmpty)
                  _DetailRow(label: 'Completed', value: deal.completedDate),
                if (deal.disputeStatus.isNotEmpty)
                  _DetailRow(label: 'Dispute', value: deal.disputeStatus),
              ],
            ),
          ),
        ),
        if (deal.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Description',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    deal.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (canRespond) ...[
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => _repository.acceptDeal(deal),
                      'Deal accepted. Review the terms and confirm.',
                    ),
            icon: const Icon(Icons.check),
            label: const Text('Accept deal'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => _repository.declineDeal(deal),
                      'Deal declined.',
                    ),
            icon: const Icon(Icons.close),
            label: const Text('Decline'),
          ),
          const SizedBox(height: 10),
        ],
        if (canConfirm) ...[
          if (mine == ConfirmationStatus.reviewTerms)
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _repository.setConfirmationStatus(
                          deal,
                          ConfirmationStatus.agreed,
                        ),
                        'You agreed to the terms.',
                      ),
              icon: const Icon(Icons.gavel),
              label: const Text('Agree to terms'),
            ),
          if (mine != ConfirmationStatus.reviewTerms) const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy || mine == ConfirmationStatus.confirmed
                ? null
                : () => _run(
                      () => _repository.setConfirmationStatus(
                        deal,
                        ConfirmationStatus.confirmed,
                      ),
                      'Confirmed. The deal completes once both parties confirm.',
                    ),
            icon: const Icon(Icons.verified),
            label: const Text('Confirm deal'),
          ),
          const SizedBox(height: 10),
        ],
        if (deal.status == DealStatus.completed) ...[
          _AgreementTile(dealId: deal.id),
          const SizedBox(height: 10),
        ],
        if (canRate) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _rateBusiness(deal),
            icon: const Icon(Icons.star_outline),
            label: const Text('Rate business'),
          ),
          const SizedBox(height: 10),
        ],
        if (canDispute) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _fileDispute(deal),
            icon: const Icon(Icons.gavel_outlined),
            label: const Text('File a dispute'),
          ),
          const SizedBox(height: 10),
        ],
        if (deal.status == DealStatus.pending ||
            deal.status == DealStatus.accepted) ...[
          TextButton.icon(
            onPressed: _busy ? null : () => _confirmCancel(deal),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel deal'),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves and opens the agreement generated for a completed deal.
class _AgreementTile extends StatefulWidget {
  const _AgreementTile({required this.dealId});

  final String dealId;

  @override
  State<_AgreementTile> createState() => _AgreementTileState();
}

class _AgreementTileState extends State<_AgreementTile> {
  final _repository = AgreementRepository();
  bool _loading = true;
  String? _agreementId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final agreement = await _repository.findForDeal(widget.dealId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _agreementId = agreement?.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_agreementId == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'The agreement for this deal is still being generated.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: const Text('View agreement'),
        subtitle: const Text('Open the signed agreement and its PDF'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AgreementDetailsScreen(agreementId: _agreementId!),
          ),
        ),
      ),
    );
  }
}

class _DisputeInput {
  const _DisputeInput({required this.reason, required this.description});

  final String reason;
  final String description;
}

class _DisputeSheet extends StatefulWidget {
  const _DisputeSheet();

  @override
  State<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends State<_DisputeSheet> {
  final _description = TextEditingController();
  String _reason = DisputeReasons.values.first;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _description.text.trim();
    if (text.length < 10) {
      setState(() => _error = 'Please describe the issue in at least 10 characters.');
      return;
    }
    if (text.length > 2000) {
      setState(() => _error = 'Please keep the description under 2000 characters.');
      return;
    }
    Navigator.of(context).pop(
      _DisputeInput(reason: _reason, description: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'File a dispute',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _reason,
            items: DisputeReasons.values
                .map(
                  (r) => DropdownMenuItem<String>(
                    value: r,
                    child: Text(r),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'What happened?',
              alignLabelWithHint: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _submit, child: const Text('Submit dispute')),
        ],
      ),
    );
  }
}

class _RatingInput {
  const _RatingInput({required this.stars, required this.comment});

  final int stars;
  final String comment;
}

class _RatingSheet extends StatefulWidget {
  const _RatingSheet();

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final _comment = TextEditingController();
  int _stars = 5;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Rate this business',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() => _stars = value),
                iconSize: 38,
                color: value <= _stars
                    ? AppColors.warning
                    : AppColors.textSecondary,
                icon: Icon(
                  value <= _stars ? Icons.star : Icons.star_border,
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _RatingInput(stars: _stars, comment: _comment.text.trim()),
            ),
            child: const Text('Submit rating'),
          ),
        ],
      ),
    );
  }
}
