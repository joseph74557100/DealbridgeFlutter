import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/firestore_errors.dart';
import '../../core/widgets/state_message.dart';
import 'data/deal_repository.dart';
import 'models/deal.dart';
import 'widgets/deal_card.dart';
import 'deal_details_screen.dart';
import 'propose_deal_screen.dart';

class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key, this.repository});

  /// Overrides the repository, which keeps the screen testable.
  final DealRepository? repository;

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  late final DealRepository _repository = widget.repository ?? DealRepository();
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deals'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProposeDealScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Propose deal'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: DealStatus.filterTabs.map((tab) {
                final selected = tab == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: AppColors.primary.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.primarySoft
                          : AppColors.textSecondary,
                    ),
                    onSelected: (_) => setState(() => _filter = tab),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Deal>>(
              stream: _repository.watchMyDeals(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return StateMessage.error(
                    title: 'Could not load deals',
                    subtitle: firestoreErrorMessage(
                      snapshot.error!,
                      'Check your connection and Firestore permissions.',
                    ),
                    action: FilledButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final all = snapshot.data ?? const <Deal>[];
                final deals = _filter == 'All'
                    ? all
                    : all.where((d) => d.status == _filter).toList();

                if (deals.isEmpty) {
                  return StateMessage.empty(
                    title: _filter == 'All'
                        ? 'No deals yet'
                        : 'No $_filter deals',
                    subtitle: _filter == 'All'
                        ? 'Propose a deal to a business to get started.'
                        : 'Try a different filter tab.',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: deals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final deal = deals[index];
                      return DealCard(
                        deal: deal,
                        currentUid: uid,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DealDetailsScreen(dealId: deal.id),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A short, safe hint for Firestore failures.
String firestoreHint(Object? error) {
  return firestoreErrorMessage(
    error ?? 'Unknown error',
    'Check your connection and Firestore permissions.',
  );
}
