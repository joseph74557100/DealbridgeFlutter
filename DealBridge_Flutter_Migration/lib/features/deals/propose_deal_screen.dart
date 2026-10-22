import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/state_message.dart';
import '../auth/data/user_repository.dart';
import '../businesses/data/business_repository.dart';
import '../businesses/models/business.dart';
import 'data/deal_repository.dart';

/// Form used to propose a new deal to a business.
///
/// The business owner is resolved by [DealRepository] before the deal is
/// written, because Firestore rules require `participantIds` to be exactly
/// `[senderUid, businessOwnerUid]`.
class ProposeDealScreen extends StatefulWidget {
  const ProposeDealScreen({
    super.key,
    this.initialBusinessId,
    this.dealRepository,
    this.businessRepository,
    this.userRepository,
  });

  /// Pre-selects a business, for example when the user starts from a
  /// business profile.
  final String? initialBusinessId;

  /// Repository overrides, which keep the form testable.
  final DealRepository? dealRepository;
  final BusinessRepository? businessRepository;
  final UserRepository? userRepository;

  @override
  State<ProposeDealScreen> createState() => _ProposeDealScreenState();
}

class _ProposeDealScreenState extends State<ProposeDealScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _value = TextEditingController();
  final _terms = TextEditingController();

  late final DealRepository _deals = widget.dealRepository ?? DealRepository();
  late final BusinessRepository _businesses =
      widget.businessRepository ?? BusinessRepository();
  late final UserRepository _users = widget.userRepository ?? UserRepository();

  String? _businessId;
  int _validityDays = 30;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _businessId = widget.initialBusinessId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _value.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Business> options) async {
    if (!_formKey.currentState!.validate()) return;
    final businessId = _businessId;
    if (businessId == null || businessId.isEmpty) {
      setState(() => _error = 'Select the business you want to deal with.');
      return;
    }
    final business = options.firstWhere(
      (b) => b.id == businessId,
      orElse: () => const Business(id: ''),
    );

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final profile = await _users.fetchProfile(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      await _deals.createDeal(
        businessId: business.id,
        businessName: business.name,
        title: _title.text.trim(),
        description: _description.text.trim(),
        value: _value.text.trim(),
        senderName: profile?.fullName ?? '',
        terms: _terms.text.trim(),
        deadline: DateTime.now()
            .add(Duration(days: _validityDays))
            .millisecondsSinceEpoch,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Deal sent. The business has been notified.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the deal. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Propose a deal')),
      body: SafeArea(
        child: StreamBuilder<List<Business>>(
          stream: _businesses.watchDirectory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const StateMessage.error(
                title: 'Could not load businesses',
                subtitle: 'Check your connection and try again.',
              );
            }
            final options = snapshot.data ?? const <Business>[];

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _businessId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Business',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    hint: const Text('Select a business'),
                    items: options
                        .map(
                          (b) => DropdownMenuItem<String>(
                            value: b.id,
                            child: Text(
                              b.name.isEmpty ? 'Unnamed business' : b.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _businessId = value),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? 'Select a business' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Deal title',
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (v) => Validators.required(v, field: 'Deal title'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    maxLines: 4,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'What are you offering?',
                      alignLabelWithHint: true,
                    ),
                    validator: (v) =>
                        Validators.required(v, field: 'A description'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _value,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Deal value (optional)',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _terms,
                    maxLines: 4,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Terms (optional)',
                      alignLabelWithHint: true,
                      helperText:
                          'Leave empty to use the standard DealBridge terms.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Valid for $_validityDays days',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Slider(
                    value: _validityDays.toDouble(),
                    min: 1,
                    max: 90,
                    divisions: 89,
                    label: '$_validityDays days',
                    onChanged: (v) => setState(() => _validityDays = v.round()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(options),
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Send deal'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
