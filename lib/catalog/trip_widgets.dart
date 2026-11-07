import 'package:flutter/material.dart';

import '../metrics.dart';

// Leaf widgets shared by BOTH modes. Each one counts its build() calls
// and its initState() calls (mounts), so the metrics show how often the
// catalog code around them rebuilds or throws them away.
//
// The naive and optimised catalogs differ only in how they use these:
// keys, memoisation, lazy lists and image sizes.

/// Reads loosely typed JSON values from the model safely.
String str(Object? v) => v == null ? '' : (v is String ? v : v.toString());

num numOf(Object? v) => v is num ? v : num.tryParse(str(v)) ?? 0;

List<Map<String, Object?>> maps(Object? v) => v is List
    ? v.whereType<Map>().map((m) => m.cast<String, Object?>()).toList()
    : const [];

/// A deterministic photo for a place, so the model never invents URLs.
String photoUrl(String seed, {required int width, required int height}) {
  final s = Uri.encodeComponent(seed.isEmpty ? 'travel' : seed);
  return 'https://picsum.photos/seed/$s/$width/$height';
}

class TripHeaderView extends StatefulWidget {
  const TripHeaderView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.budget,
  });

  final String title;
  final String subtitle;
  final String budget;

  @override
  State<TripHeaderView> createState() => _TripHeaderViewState();
}

class _TripHeaderViewState extends State<TripHeaderView> {
  @override
  void initState() {
    super.initState();
    Metrics.instance.countMount();
  }

  @override
  Widget build(BuildContext context) {
    Metrics.instance.countBuild();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: theme.textTheme.headlineSmall),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.subtitle, style: theme.textTheme.bodyMedium),
          ],
          if (widget.budget.isNotEmpty) ...[
            const SizedBox(height: 12),
            Chip(
              avatar: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(widget.budget),
            ),
          ],
        ],
      ),
    );
  }
}

class StopRow extends StatefulWidget {
  const StopRow({
    super.key,
    required this.time,
    required this.title,
    required this.note,
  });

  final String time;
  final String title;
  final String note;

  @override
  State<StopRow> createState() => _StopRowState();
}

class _StopRowState extends State<StopRow> {
  @override
  void initState() {
    super.initState();
    Metrics.instance.countMount();
  }

  @override
  Widget build(BuildContext context) {
    Metrics.instance.countBuild();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              widget.time,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: theme.textTheme.titleSmall),
                if (widget.note.isNotEmpty)
                  Text(widget.note, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.day, required this.children});

  final String day;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(day, style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A place tile with a photo. [decodeWidth] is the optimisation knob:
/// null decodes the full-size image, a number decodes at display size.
class PlaceTile extends StatefulWidget {
  const PlaceTile({
    super.key,
    required this.name,
    required this.area,
    required this.price,
    required this.imageUrl,
    this.decodeWidth,
  });

  final String name;
  final String area;
  final String price;
  final String imageUrl;
  final int? decodeWidth;

  @override
  State<PlaceTile> createState() => _PlaceTileState();
}

class _PlaceTileState extends State<PlaceTile> {
  @override
  void initState() {
    super.initState();
    Metrics.instance.countMount();
  }

  @override
  Widget build(BuildContext context) {
    Metrics.instance.countBuild();
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 110,
              width: 180,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.cover,
                cacheWidth: widget.decodeWidth,
                frameBuilder: (context, child, frame, wasSync) =>
                    frame == null && !wasSync
                    ? ColoredBox(color: theme.colorScheme.surfaceContainerHigh)
                    : child,
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    [widget.area, widget.price]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BudgetLine extends StatefulWidget {
  const BudgetLine({super.key, required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  State<BudgetLine> createState() => _BudgetLineState();
}

class _BudgetLineState extends State<BudgetLine> {
  @override
  void initState() {
    super.initState();
    Metrics.instance.countMount();
  }

  @override
  Widget build(BuildContext context) {
    Metrics.instance.countBuild();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(widget.label)),
          Text(
            widget.amount,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Placeholder shown in optimised mode until the first real component
/// arrives. Same rough size as the header and a day card, so nothing
/// jumps when the real content lands.
class TripSkeleton extends StatelessWidget {
  const TripSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget block(double height) => Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [block(120), block(200), block(200)]),
    );
  }
}
