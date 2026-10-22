import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../core/utils/validators.dart';
import 'data/business_repository.dart';
import 'models/business.dart';

/// Creates a new business or edits an existing one.
///
/// When [business] is supplied the form updates that document, otherwise it
/// creates a new business owned by the signed-in user.
class BusinessFormScreen extends StatefulWidget {
  const BusinessFormScreen({super.key, this.business, this.repository});

  final Business? business;

  /// Overrides the repository, which keeps the form testable.
  final BusinessRepository? repository;

  @override
  State<BusinessFormScreen> createState() => _BusinessFormScreenState();
}

class _BusinessFormScreenState extends State<BusinessFormScreen> {
  late final BusinessRepository _repository =
      widget.repository ?? BusinessRepository();
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.business?.name ?? '');
  late final _category =
      TextEditingController(text: widget.business?.category ?? '');
  late final _city = TextEditingController(text: widget.business?.city ?? '');
  late final _description =
      TextEditingController(text: widget.business?.description ?? '');
  late final _phone = TextEditingController(text: widget.business?.phone ?? '');
  late final _email = TextEditingController(text: widget.business?.email ?? '');
  late final _website =
      TextEditingController(text: widget.business?.website ?? '');

  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.business != null;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _city.dispose();
    _description.dispose();
    _phone.dispose();
    _email.dispose();
    _website.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final business = widget.business;
      if (business == null) {
        await _repository.createBusiness(
          name: _name.text.trim(),
          category: _category.text.trim(),
          city: _city.text.trim(),
          description: _description.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          website: _website.text.trim(),
        );
      } else {
        await _repository.updateBusiness(
          business.copyWith(
            name: _name.text.trim(),
            category: _category.text.trim(),
            city: _city.text.trim(),
            description: _description.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            website: _website.text.trim(),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not save the business. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit business' : 'Add business'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Business name'),
              validator: (value) =>
                  Validators.required(value, field: 'Business name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Category',
                helperText: 'e.g. Retail, Construction, Technology',
              ),
              validator: (value) =>
                  Validators.required(value, field: 'Category'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'City'),
              validator: (value) => Validators.required(value, field: 'City'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  Validators.required(value, field: 'Description'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              validator: Validators.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: Validators.optionalEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Website',
                helperText: 'Include https://',
              ),
              validator: Validators.website,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: businessCategories
                  .map(
                    (category) => ActionChip(
                      label: Text(category),
                      onPressed: () => setState(() {
                        _category.text = category;
                      }),
                    ),
                  )
                  .toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_isEditing ? 'Save changes' : 'Add business'),
            ),
          ],
        ),
      ),
    );
  }
}
