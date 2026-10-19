/// The event page's Sponsors (B1).
///
/// - Sponsors of one tier or none (the breakfast): today's section,
///   unchanged.
/// - Sponsors across tiers (NITKonnect): one heading per tier in order
///   (Title, Gold, Silver, Bronze, Associate, then any other), the title
///   sponsor on a wider card; partners grouped by type the same way.
library;

import 'package:flutter/material.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/event.dart';

class SponsorsSection extends StatelessWidget {
  const SponsorsSection({
    super.key,
    required this.sponsors,
    required this.partners,
    required this.onOpenLink,
  });

  final List<EventSponsor> sponsors;
  final List<EventPartner> partners;

  /// Opens a sponsor's or partner's website.
  final void Function(String url) onOpenLink;

  static const _tierOrder = [
    'TITLE_SPONSOR',
    'GOLD_SPONSOR',
    'SILVER_SPONSOR',
    'BRONZE_SPONSOR',
    'ASSOCIATE_SPONSOR',
  ];

  /// Whether the sponsors span more than one tier.
  static bool isBig(List<EventSponsor> sponsors) =>
      sponsors.map((s) => s.sponsorType).toSet().length > 1;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = Text(
      'Sponsors',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.primary),
    );
    if (sponsors.isEmpty && partners.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 12),
          Text('Sponsor details will be updated soon.',
              style: TextStyle(fontSize: 14, color: p.textMuted)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 12),
        if (isBig(sponsors)) ..._byTier(context) else ..._simple(context),
      ],
    );
  }

  // ── Today's section ──────────────────────────────────────────────────

  List<Widget> _simple(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final columns = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);
    return [
      if (sponsors.isNotEmpty) ...[
        _eyebrow(context, 'SPONSORS'),
        const SizedBox(height: 8),
        _grid(context, [for (final s in sponsors) _sponsorCard(s)], columns),
        const SizedBox(height: 16),
      ],
      if (partners.isNotEmpty) ...[
        _eyebrow(context, 'PARTNERS'),
        const SizedBox(height: 8),
        _grid(context, [for (final pt in partners) _partnerCard(pt)], columns),
      ],
    ];
  }

  // ── By tier ──────────────────────────────────────────────────────────

  List<Widget> _byTier(BuildContext context) {
    final sponsorGroups = _group<EventSponsor>(
      sponsors,
      typeOf: (s) => s.sponsorType,
      order: _tierOrder,
    );
    final partnerGroups = _group<EventPartner>(
      partners,
      typeOf: (pt) => pt.partnerType,
      order: const [],
    );
    return [
      for (final group in sponsorGroups) ...[
        _eyebrow(context, group.first.sponsorTypeLabel.toUpperCase()),
        const SizedBox(height: 8),
        if (group.first.sponsorType == 'TITLE_SPONSOR')
          for (final s in group)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _sponsorCard(s, large: true),
            )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return _grid(context, [for (final s in group) _sponsorCard(s)], _columnsFor(w));
            },
          ),
        const SizedBox(height: 16),
      ],
      if (partners.isNotEmpty) ...[
        _eyebrow(context, 'PARTNERS'),
        const SizedBox(height: 8),
        for (final group in partnerGroups) ...[
          if (partnerGroups.length > 1) ...[
            Text(
              group.first.partnerTypeLabel,
              style: TextStyle(fontSize: 12, color: context.palette.textMuted),
            ),
            const SizedBox(height: 6),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return _grid(context, [for (final pt in group) _partnerCard(pt)], _columnsFor(w));
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    ];
  }

  static int _columnsFor(double width) => width >= 720 ? 3 : (width >= 440 ? 2 : 1);

  /// [items] grouped by type: the types in [order] first, then the others in
  /// the order they first appear; each group in the server's order.
  static List<List<T>> _group<T>(
    List<T> items, {
    required String Function(T) typeOf,
    required List<String> order,
  }) {
    final groups = <String, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(typeOf(item), () => []).add(item);
    }
    final firstSeen = groups.keys.toList();
    int rank(String type) {
      final i = order.indexOf(type);
      return i >= 0 ? i : order.length + firstSeen.indexOf(type);
    }

    final types = [...firstSeen]..sort((a, b) => rank(a).compareTo(rank(b)));
    return [for (final t in types) groups[t]!];
  }

  // ── Pieces ───────────────────────────────────────────────────────────

  Widget _eyebrow(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.palette.textSecondary,
          letterSpacing: 0.5,
        ),
      );

  Widget _grid(BuildContext context, List<Widget> cards, int columns) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.2,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _sponsorCard(EventSponsor s, {bool large = false}) => _SponsorCard(
        name: s.name,
        typeLabel: s.sponsorTypeLabel,
        logoUrl: s.logoUrl,
        websiteUrl: s.websiteUrl,
        large: large,
        onOpenLink: onOpenLink,
      );

  Widget _partnerCard(EventPartner pt) => _SponsorCard(
        name: pt.name,
        typeLabel: pt.partnerTypeLabel,
        logoUrl: pt.logoUrl,
        websiteUrl: pt.websiteUrl,
        onOpenLink: onOpenLink,
      );
}

class _SponsorCard extends StatelessWidget {
  const _SponsorCard({
    required this.name,
    required this.typeLabel,
    required this.logoUrl,
    required this.websiteUrl,
    required this.onOpenLink,
    this.large = false,
  });

  final String name;
  final String typeLabel;
  final String? logoUrl;
  final String? websiteUrl;
  final void Function(String url) onOpenLink;

  /// The title sponsor: a full-width card with a bigger logo.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final logo = logoUrl;
    final site = websiteUrl;
    final hasSite = site != null && site.isNotEmpty;
    final logoSize = large ? 56.0 : 36.0;
    final card = Container(
      padding: EdgeInsets.all(large ? 16 : 12),
      decoration: BoxDecoration(
        color: p.surfaceHover,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (logo != null && logo.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                logo,
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(Icons.business, size: large ? 32 : 22, color: p.primary),
              ),
            )
          else
            Icon(Icons.business, size: large ? 32 : 22, color: p.primary),
          SizedBox(width: large ? 14 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: large ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: large ? 16 : 13,
                    color: hasSite ? p.primary : null,
                    decoration: hasSite ? TextDecoration.underline : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  typeLabel,
                  style: TextStyle(fontSize: large ? 12 : 11, color: p.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (hasSite) {
      return GestureDetector(onTap: () => onOpenLink(site!), child: card);
    }
    return card;
  }
}
