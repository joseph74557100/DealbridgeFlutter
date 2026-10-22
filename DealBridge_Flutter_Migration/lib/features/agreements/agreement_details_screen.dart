import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/status_pill.dart';
import 'agreement_pdf_screen.dart';
import 'data/agreement_repository.dart';
import 'models/agreement.dart';

/// Full view of a single agreement, including its signatures, notes and the
/// generated PDF document.
class AgreementDetailsScreen extends StatefulWidget {
  const AgreementDetailsScreen({
    super.key,
    required this.agreementId,
    this.repository,
  });

  final String agreementId;

  /// Overrides the repository, which keeps the screen testable.
  final AgreementRepository? repository;

  @override
  State<AgreementDetailsScreen> createState() => _AgreementDetailsScreenState();
}

class _AgreementDetailsScreenState extends State<AgreementDetailsScreen> {
  late final AgreementRepository _repository =
      widget.repository ?? AgreementRepository();

  bool _busy = false;
  bool _editingNotes = false;
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

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
    } catch (_) {
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

  Future<void> _saveNotes(Agreement agreement) async {
    await _run(
      () => _repository.updateMetadata(
        agreementId: agreement.id,
        notes: _notes.text.trim(),
      ),
      'Notes saved.',
    );
    if (mounted) setState(() => _editingNotes = false);
  }

  Future<void> _confirmDelete(Agreement agreement) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this agreement?'),
        content: const Text(
          'This removes the agreement document for both participants.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => _repository.delete(agreement.id),
      'Agreement deleted.',
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agreement')),
      body: FutureBuilder<Agreement?>(
        future: _repository.fetchAgreement(widget.agreementId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return StateMessage.error(
              title: 'Could not load this agreement',
              subtitle: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => setState(() {}),
                child: const Text('Retry'),
              ),
            );
          }
          final agreement = snapshot.data;
          if (agreement == null) {
            return const StateMessage.error(
              title: 'Agreement not found',
              subtitle: 'It may have been removed or you may not have access.',
            );
          }
          return _body(agreement);
        },
      ),
    );
  }

  Widget _body(Agreement agreement) {
    final archived = agreement.status == AgreementStatus.archived;
    final locked = agreement.locked || agreement.fullySigned;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                        agreement.title.isEmpty
                            ? 'Untitled agreement'
                            : agreement.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(
                      label: agreement.status,
                      color: agreement.isSigned
                          ? AppColors.success
                          : (archived ? AppColors.textSecondary : AppColors.warning),
                      dense: true,
                    ),
                  ],
                ),
                if (agreement.agreementNumber.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    agreement.agreementNumber,
                    style: const TextStyle(color: AppColors.textSecondary),
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
                _DetailRow(
                  label: 'Business one',
                  value: agreement.businessOneName,
                ),
                _DetailRow(
                  label: 'Business two',
                  value: agreement.businessTwoName,
                ),
                _DetailRow(
                  label: 'Deal value',
                  value: agreement.dealValue.isEmpty
                      ? 'Not specified'
                      : agreement.dealValue,
                ),
                _DetailRow(
                  label: 'Created',
                  value: agreement.createdLabel ?? '—',
                ),
                _DetailRow(
                  label: 'Expires',
                  value: agreement.expiryDate.isEmpty
                      ? 'No expiry'
                      : agreement.expiryDate,
                ),
                _DetailRow(
                  label: 'Signatures',
                  value: '${agreement.signatures.length} of '
                      '${agreement.requiredSignatures}',
                ),
              ],
            ),
          ),
        ),
        if (agreement.terms.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Terms',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    agreement.terms,
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
        if (agreement.signatures.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Signatures',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  ...agreement.signatures.map(
                    (signature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.verified,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  signature.businessName.isEmpty
                                      ? 'Participant'
                                      : signature.businessName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  [
                                    signature.signedDate,
                                    signature.signedTime,
                                  ].where((v) => v.isNotEmpty).join(' • '),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!_editingNotes)
                      TextButton(
                        onPressed: () {
                          _notes.text = agreement.notes;
                          setState(() => _editingNotes = true);
                        },
                        child: const Text('Edit'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_editingNotes)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _notes,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _editingNotes = false),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy
                                  ? null
                                  : () => _saveNotes(agreement),
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                else
                  Text(
                    agreement.notes.isEmpty
                        ? 'No notes yet.'
                        : agreement.notes,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 20),
        if (agreement.hasDocument)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AgreementPdfScreen(
                  url: agreement.pdfUrl.isNotEmpty
                      ? agreement.pdfUrl
                      : agreement.localPdfPath,
                  title: agreement.title,
                ),
              ),
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('View document'),
          ),
        if (agreement.hasDocument) const SizedBox(height: 10),
        if (!locked)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => archived
                          ? _repository.restore(agreement.id)
                          : _repository.archive(agreement.id),
                      archived ? 'Agreement restored.' : 'Agreement archived.',
                    ),
            icon: Icon(
              archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            ),
            label: Text(archived ? 'Restore' : 'Archive'),
          ),
        if (!locked) const SizedBox(height: 10),
        if (!locked)
          TextButton.icon(
            onPressed: _busy ? null : () => _confirmDelete(agreement),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete agreement'),
          ),
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
            width: 100,
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
