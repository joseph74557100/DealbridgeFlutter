import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/app_exception.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/status_pill.dart';
import '../deals/propose_deal_screen.dart';
import 'business_form_screen.dart';
import 'data/business_repository.dart';
import 'models/business.dart';

/// Full profile of a single business: contact details, ratings, save state and
/// the entry point for proposing a deal.
class BusinessDetailsScreen extends StatefulWidget {
  const BusinessDetailsScreen({
    super.key,
    required this.businessId,
    this.repository,
  });

  final String businessId;

  /// Overrides the repository, which keeps the screen testable.
  final BusinessRepository? repository;

  @override
  State<BusinessDetailsScreen> createState() => _BusinessDetailsScreenState();
}

class _BusinessDetailsScreenState extends State<BusinessDetailsScreen> {
  late final BusinessRepository _repository =
      widget.repository ?? BusinessRepository();

  bool _busy = false;
  String? _error;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _toggleSaved(Business business, bool saved) async {
    setState(() => _busy = true);
    try {
      await _repository.setSaved(business.id, saved: !saved);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not update your saved businesses.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      if (uri != null && uri.path.isNotEmpty) {
        await _openUrl('https://$value');
      }
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open that link.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _proposeDeal(Business business) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProposeDealScreen(initialBusinessId: business.id),
      ),
    );
  }

  Future<void> _editBusiness(Business business) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => BusinessFormScreen(business: business),
      ),
    );
  }

  Future<void> _deleteBusiness(Business business) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this business?'),
        content: const Text(
          'The business profile is removed for everyone. Existing deals are '
          'not affected.',
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

    setState(() => _busy = true);
    try {
      await _repository.deleteBusiness(business.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not delete the business.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestVerification(Business business) async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Request verification'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Document link',
              hintText: 'https://example.com/certificate.pdf',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await _repository.requestVerification(
        businessId: business.id,
        documentType: 'Business registration document',
        documentUrl: url,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification requested.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not submit the verification request.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<Business?>(
        stream: _repository.watchBusiness(widget.businessId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: const StateMessage.error(
                title: 'Could not load this business',
                subtitle: 'Check your connection and try again.',
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final business = snapshot.data;
          if (business == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const StateMessage.error(
                title: 'Business not found',
                subtitle:
                    'It may have been removed or you may not have access.',
              ),
            );
          }
          return _body(business);
        },
      ),
    );
  }

  Widget _body(Business business) {
    final isOwner = business.ownerId.isNotEmpty && business.ownerId == _uid;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 220,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            background: _Header(business: business),
          ),
          actions: [
            if (business.ownerId.isNotEmpty && business.ownerId == _uid)
              IconButton(
                tooltip: 'Edit business',
                onPressed: _busy ? null : () => _editBusiness(business),
                icon: const Icon(Icons.edit_outlined),
              ),
            StreamBuilder<Set<String>>(
              stream: _repository.watchSavedBusinessIds(),
              builder: (context, saved) {
                final isSaved =
                    (saved.data ?? const <String>{}).contains(business.id);
                return IconButton(
                  tooltip: isSaved ? 'Remove from saved' : 'Save business',
                  onPressed: _busy ? null : () => _toggleSaved(business, isSaved),
                  icon: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_border,
                  ),
                );
              },
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (business.category.isNotEmpty)
                      StatusPill(
                        label: business.category,
                        color: AppColors.primarySoft,
                        dense: true,
                      ),
                    if (business.city.isNotEmpty)
                      StatusPill(
                        label: business.city,
                        color: AppColors.info,
                        dense: true,
                        icon: Icons.location_on_outlined,
                      ),
                    if (business.isGenuinelyVerified)
                      const StatusPill(
                        label: 'Verified',
                        color: AppColors.info,
                        dense: true,
                        icon: Icons.verified,
                      ),
                    if (business.completedDeals > 0)
                      StatusPill(
                        label: '${business.completedDeals} deals',
                        color: AppColors.success,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (business.ratingCount > 0)
                  Row(
                    children: [
                      const Icon(Icons.star, color: AppColors.warning, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        business.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${business.ratingCount} ratings)',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                if (business.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'About',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    business.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Contact',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                if (business.phone.isEmpty &&
                    business.email.isEmpty &&
                    business.website.isEmpty)
                  const Text(
                    'No contact details published.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                if (business.phone.isNotEmpty)
                  _ContactTile(
                    icon: Icons.phone_outlined,
                    label: business.phone,
                    onTap: () => _openUrl('tel:${business.phone}'),
                  ),
                if (business.email.isNotEmpty)
                  _ContactTile(
                    icon: Icons.email_outlined,
                    label: business.email,
                    onTap: () => _openUrl('mailto:${business.email}'),
                  ),
                if (business.website.isNotEmpty)
                  _ContactTile(
                    icon: Icons.language_outlined,
                    label: business.website,
                    onTap: () => _openUrl(business.website),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 20),
                if (!isOwner)
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _proposeDeal(business),
                    icon: const Icon(Icons.handshake_outlined),
                    label: const Text('Propose a deal'),
                  )
                else ...[
                  const Text(
                    'This is your business.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _editBusiness(business),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit details'),
                  ),
                  if (!business.isGenuinelyVerified) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _requestVerification(business),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Request verification'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _deleteBusiness(business),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete business'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Ratings',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<BusinessRating>>(
                  stream: _repository.watchRatings(business.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final ratings = snapshot.data ?? const <BusinessRating>[];
                    if (ratings.isEmpty) {
                      return const Text(
                        'No ratings yet.',
                        style: TextStyle(color: AppColors.textSecondary),
                      );
                    }
                    return Column(
                      children: ratings
                          .map(
                            (rating) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        size: 18,
                                        color: rating.stars > 0
                                            ? AppColors.warning
                                            : AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rating.userName.isEmpty
                                                  ? 'DealBridge member'
                                                  : rating.userName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (rating.comment.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                rating.comment,
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.business});

  final Business business;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Text(
        business.name.isEmpty ? '?' : business.name.substring(0, 1).toUpperCase(),
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontWeight: FontWeight.w700,
          fontSize: 44,
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (business.logoUrl.isEmpty)
          fallback
        else
          Image.network(
            business.logoUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.navy],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Text(
            business.name.isEmpty ? 'Unnamed business' : business.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: onTap,
    );
  }
}
