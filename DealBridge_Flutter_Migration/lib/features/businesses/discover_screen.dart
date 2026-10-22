import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_message.dart';
import '../data/business_repository.dart';
import '../models/business.dart';
import '../widgets/business_card.dart';
import 'business_details_screen.dart';

/// The business directory: search, category filtering and saved businesses.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key, this.initialTab = 0});

  /// 0 = directory, 1 = saved.
  final int initialTab;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  final _repository = BusinessRepository();
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  final _search = TextEditingController();
  String _query = '';
  String _category = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (_search.text == _query) return;
      setState(() => _query = _search.text);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Directory'),
            Tab(text: 'Saved'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DirectoryTab(
            repository: _repository,
            search: _search,
            query: _query,
            category: _category,
            onCategoryChanged: (value) => setState(() => _category = value),
          ),
          _SavedTab(repository: _repository),
        ],
      ),
    );
  }
}

class _DirectoryTab extends StatelessWidget {
  const _DirectoryTab({
    required this.repository,
    required this.search,
    required this.query,
    required this.category,
    required this.onCategoryChanged,
  });

  final BusinessRepository repository;
  final TextEditingController search;
  final String query;
  final String category;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: search,
            decoration: InputDecoration(
              hintText: 'Search businesses',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () => search.clear(),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _CategoryChip(
                label: 'All',
                selected: category.isEmpty,
                onTap: () => onCategoryChanged(''),
              ),
              ...businessCategories.map(
                (c) => _CategoryChip(
                  label: c,
                  selected: category == c,
                  onTap: () => onCategoryChanged(c),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Business>>(
            stream: repository.watchDirectory(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const StateMessage.error(
                  title: 'Could not load businesses',
                  subtitle: 'Check your connection and try again.',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final all = snapshot.data ?? const <Business>[];
              final term = query.trim().toLowerCase();
              final filtered = all.where((business) {
                if (category.isNotEmpty && business.category != category) {
                  return false;
                }
                if (term.isEmpty) return true;
                return business.name.toLowerCase().contains(term) ||
                    business.description.toLowerCase().contains(term) ||
                    business.category.toLowerCase().contains(term) ||
                    business.city.toLowerCase().contains(term);
              }).toList();

              if (filtered.isEmpty) {
                return StateMessage.empty(
                  title: term.isEmpty && category.isEmpty
                      ? 'No businesses yet'
                      : 'No matches',
                  subtitle: term.isEmpty && category.isEmpty
                      ? 'Businesses added by other members appear here.'
                      : 'Try a different search term or category.',
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final business = filtered[index];
                  return BusinessCard(
                    business: business,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BusinessDetailsScreen(businessId: business.id),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SavedTab extends StatelessWidget {
  const _SavedTab({required this.repository});

  final BusinessRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: repository.watchSavedBusinessIds(),
      builder: (context, savedSnapshot) {
        return StreamBuilder<List<Business>>(
          stream: repository.watchDirectory(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const StateMessage.error(
                title: 'Could not load saved businesses',
                subtitle: 'Check your connection and try again.',
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final savedIds = savedSnapshot.data ?? const <String>{};
            final businesses = (snapshot.data ?? const <Business>[])
                .where((b) => savedIds.contains(b.id))
                .toList();

            if (businesses.isEmpty) {
              return const StateMessage.empty(
                title: 'No saved businesses',
                subtitle: 'Tap the bookmark on a business to save it here.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: businesses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final business = businesses[index];
                return BusinessCard(
                  business: business,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BusinessDetailsScreen(businessId: business.id),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.primary.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.primarySoft : AppColors.textSecondary,
        ),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
