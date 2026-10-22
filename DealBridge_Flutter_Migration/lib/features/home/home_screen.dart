import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/state_message.dart';
import '../../core/widgets/status_pill.dart';
import '../auth/data/user_repository.dart';
import '../auth/models/user_profile.dart';
import '../businesses/data/business_repository.dart';
import '../businesses/models/business.dart';
import '../deals/data/deal_repository.dart';
import '../deals/models/deal.dart';
import '../deals/widgets/deal_card.dart';

/// Dashboard summarising the signed-in user's deals and businesses.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _deals = DealRepository();
  final _businesses = BusinessRepository();
  final _users = UserRepository();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            StreamBuilder<UserProfile?>(
              stream: _users.watchMyProfile(),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.fullName.isNotEmpty == true
                          ? 'Hello, ${profile!.fullName.split(' ').first}'
                          : 'Welcome back',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile?.company.isNotEmpty == true
                          ? profile!.company
                          : 'Connect businesses and build opportunities.',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
            StreamBuilder<List<Deal>>(
              stream: _deals.watchMyDeals(),
              builder: (context, snapshot) {
                final deals = snapshot.data ?? const <Deal>[];
                final pending = deals
                    .where((d) => d.status == DealStatus.pending)
                    .length;
                final active = deals
                    .where(
                      (d) =>
                          d.status == DealStatus.accepted ||
                          d.status == DealStatus.active,
                    )
                    .length;
                final completed = deals
                    .where((d) => d.status == DealStatus.completed)
                    .length;

                return Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Awaiting',
                        value: pending,
                        color: AppColors.warning,
                        icon: Icons.hourglass_top_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Active',
                        value: active,
                        color: AppColors.info,
                        icon: Icons.timelapse_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Completed',
                        value: completed,
                        color: AppColors.success,
                        icon: Icons.check_circle_outline,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            StreamBuilder<List<Business>>(
              stream: _businesses.watchMyBusinesses(),
              builder: (context, snapshot) {
                final mine = snapshot.data ?? const <Business>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your businesses',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (mine.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'You have not added a business yet. Add one from '
                            'the Discover tab to receive deal proposals.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ...mine.map(
                        (business) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            child: ListTile(
                              leading: const Icon(Icons.business_outlined),
                              title: Text(
                                business.name.isEmpty
                                    ? 'Unnamed business'
                                    : business.name,
                              ),
                              subtitle: Text(
                                business.category.isEmpty
                                    ? 'Business'
                                    : business.category,
                              ),
                              trailing: business.isGenuinelyVerified
                                  ? const StatusPill(
                                      label: 'Verified',
                                      color: AppColors.info,
                                      dense: true,
                                      icon: Icons.verified,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent deals',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<Deal>>(
              stream: _deals.watchMyDeals(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final deals = snapshot.data ?? const <Deal>[];
                if (deals.isEmpty) {
                  return const StateMessage.empty(
                    title: 'No deals yet',
                    subtitle: 'Propose a deal to a business to get started.',
                    compact: true,
                  );
                }
                return Column(
                  children: deals
                      .take(3)
                      .map(
                        (deal) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DealCard(
                            deal: deal,
                            currentUid: uid,
                            onTap: () {},
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
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
