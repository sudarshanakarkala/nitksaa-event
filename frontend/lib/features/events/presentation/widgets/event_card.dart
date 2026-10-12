import 'package:flutter/material.dart';

import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../domain/event.dart';

/// Where the person stands with an event, for the card's badge and buttons.
enum EventAttendance { none, registered, cancelled }

/// An admin action in the card's "more" menu.
class EventCardAction {
  const EventCardAction({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool destructive;
}

/// Look of one event's card. Today every event uses the theme; a branded
/// event (e.g. NITKonnect) can later pass its own accent and logo here
/// without changing the card.
class EventCardBrand {
  const EventCardBrand({this.accent, this.logoUrl});

  /// Banner tint and date-tile month colour. Null: the theme's gold.
  final Color? accent;

  /// Shown on the banner when the event has no image.
  final String? logoUrl;
}

/// The one event card, used by Events, My Events and the admin Events tab
/// (website StoryCard pattern: cover on top, small pill badges, a 15px
/// title clamped to two lines, a footer above a divider).
///
/// Cards have a fixed height ([height] / [adminHeight]) so a grid row lines
/// up without intrinsic sizing; content that doesn't fit is clipped rather
/// than overflowing. Use [EventCardGrid] to lay them out.
class EventCard extends StatelessWidget {
  const EventCard({
    super.key,
    required this.title,
    required this.isVirtual,
    required this.onView,
    this.tagline,
    this.start,
    this.end,
    this.location,
    this.imageUrl,
    this.isFree,
    this.price,
    this.registrationStatus,
    this.registrationClosesAt,
    this.attendance = EventAttendance.none,
    this.mine = false,
    this.viewLabel = 'View Details',
    this.onUnregister,
    this.unregistering = false,
    this.onViewRefund,
    this.onJoin,
    this.footerNote,
    this.showAdmin = false,
    this.eventStatus,
    this.registeredCount = 0,
    this.capacity,
    this.adminActions = const [],
    this.brand = const EventCardBrand(),
  });

  /// A card for [event], with everything the event itself knows filled in.
  factory EventCard.forEvent(
    AppEvent event, {
    Key? key,
    required VoidCallback onView,
    EventAttendance attendance = EventAttendance.none,
    bool mine = false,
    VoidCallback? onUnregister,
    bool unregistering = false,
    VoidCallback? onViewRefund,
    String? footerNote,
    bool showAdmin = false,
    List<EventCardAction> adminActions = const [],
  }) {
    return EventCard(
      key: key,
      title: event.title,
      tagline: event.tagline,
      start: event.startDatetime,
      end: event.endDatetime,
      isVirtual: event.isVirtual,
      location: event.locationText,
      imageUrl: event.thumbnailUrl ?? event.bannerUrl,
      isFree: event.isFree,
      price: event.ticketPrice,
      registrationStatus: event.registrationStatus,
      registrationClosesAt: event.registrationClosesAt,
      attendance: attendance,
      mine: mine,
      onView: onView,
      onUnregister: onUnregister,
      unregistering: unregistering,
      onViewRefund: onViewRefund,
      footerNote: footerNote,
      showAdmin: showAdmin,
      eventStatus: event.status,
      registeredCount: event.registeredCount,
      capacity: event.capacity,
      adminActions: adminActions,
    );
  }

  /// Card heights, so a grid can give every card in a row the same size.
  static const double height = 352;
  static const double adminHeight = 390;

  /// Website grid: cards at least this wide, as many columns as fit.
  static const double minWidth = 300;
  static const double gap = 12;

  final String title;
  final String? tagline;
  final DateTime? start;
  final DateTime? end;
  final bool isVirtual;
  final String? location;
  final String? imageUrl;
  final bool? isFree;
  final double? price;

  /// Backend `registration_status`: open, closed, full, not_open_yet,
  /// not_applicable.
  final String? registrationStatus;
  final DateTime? registrationClosesAt;
  final EventAttendance attendance;

  /// You created this event: the card gets the gold tint, like your own
  /// stories on the website. Registration is shown by its badge, not the
  /// tint.
  final bool mine;

  final VoidCallback onView;
  final String viewLabel;
  final VoidCallback? onUnregister;
  final bool unregistering;
  final VoidCallback? onViewRefund;

  /// Join meeting: a registered attendee's link to a virtual event.
  final VoidCallback? onJoin;

  /// Short muted text at the left of the footer.
  final String? footerNote;

  /// Admin variant: event status badge, capacity bar and [adminActions].
  final bool showAdmin;
  final String? eventStatus;
  final int registeredCount;
  final int? capacity;
  final List<EventCardAction> adminActions;
  final EventCardBrand brand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _HoverCard(
      onTap: onView,
      highlighted: mine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Banner(
            imageUrl: imageUrl,
            start: start,
            isVirtual: isVirtual,
            brand: brand,
          ),
          Expanded(
            // Fixed-height card: anything that doesn't fit is clipped, never
            // an overflow error.
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 5, runSpacing: 5, children: _badges(p)),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: p.textPrimary,
                      ),
                    ),
                    if (tagline != null && tagline!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        tagline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 13,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _Meta(
                      icon: Icons.schedule,
                      text: start == null ? 'Date to be announced' : _when(start!, end),
                    ),
                    const SizedBox(height: 6),
                    _Meta(
                      icon: isVirtual ? Icons.videocam_outlined : Icons.place_outlined,
                      text: (location != null && location!.trim().isNotEmpty)
                          ? location!
                          : (isVirtual ? 'Online' : 'Venue to be announced'),
                    ),
                    if (showAdmin) ...[
                      const SizedBox(height: 12),
                      _CapacityBar(registered: registeredCount, capacity: capacity),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  List<Widget> _badges(AppPalette p) {
    final badges = <Widget>[];
    if (showAdmin && eventStatus != null) {
      final (label, tone) = switch (eventStatus!.toLowerCase()) {
        'draft' => ('Draft', p.warning),
        'published' => ('Published', p.success),
        'cancelled' => ('Cancelled', p.error),
        'completed' => ('Completed', p.textMuted),
        final other => (other, p.textMuted),
      };
      badges.add(_Badge(label: label, tone: tone));
    }
    switch (attendance) {
      case EventAttendance.registered:
        badges.add(_Badge(label: 'Registered', tone: p.info));
      case EventAttendance.cancelled:
        badges.add(_Badge(label: 'Unregistered', tone: p.error));
      case EventAttendance.none:
        break;
    }
    final status = _registrationBadge(p);
    if (status != null) badges.add(status);
    // Unknown price (no event details loaded): no badge rather than a guess.
    if (isFree != null || price != null) {
      badges.add(_Badge(label: _priceLabel(), tone: p.primary));
    }
    badges.add(_Badge(label: isVirtual ? 'Virtual' : 'Physical', tone: p.textSecondary));
    return badges;
  }

  Widget? _registrationBadge(AppPalette p) {
    final now = DateTime.now();
    final finished = (end ?? start)?.isBefore(now) ?? false;
    if (finished) return _Badge(label: 'Ended', tone: p.textMuted);
    switch (registrationStatus?.toLowerCase()) {
      case 'open':
        final closes = registrationClosesAt;
        final closingSoon = closes != null &&
            closes.isAfter(now) &&
            closes.difference(now) <= const Duration(hours: 72);
        return closingSoon
            ? _Badge(label: 'Closing soon', tone: p.warning)
            : _Badge(label: 'Registration open', tone: p.success);
      case 'full':
        return _Badge(label: 'Full', tone: p.error);
      case 'not_open_yet':
        return _Badge(label: 'Opens soon', tone: p.info);
      case 'closed':
        return _Badge(label: 'Registration closed', tone: p.textMuted);
      default:
        return null;
    }
  }

  String _priceLabel() {
    if (isFree ?? true) return 'Free';
    final amount = price;
    if (amount == null) return 'Paid';
    final whole = amount == amount.roundToDouble();
    return '₹${amount.toStringAsFixed(whole ? 0 : 2)}';
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    final compact = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      visualDensity: VisualDensity.compact,
      textStyle: WidgetStatePropertyAll(
        AppTextStyles.labelLarge.copyWith(fontSize: 13, letterSpacing: 0),
      ),
    );

    final buttons = <Widget>[
      if (onUnregister != null)
        TextButton(
          onPressed: unregistering ? null : onUnregister,
          style: compact.merge(
            TextButton.styleFrom(foregroundColor: p.textSecondary),
          ),
          // Disabled, not replaced, while it runs: the label stays put.
          child: const Text('Unregister'),
        ),
      if (onViewRefund != null)
        TextButton(
          onPressed: onViewRefund,
          style: compact,
          child: const Text('View refund status'),
        ),
      if (adminActions.isNotEmpty)
        PopupMenuButton<int>(
          tooltip: 'More actions',
          icon: Icon(Icons.more_horiz, color: p.textSecondary),
          onSelected: (i) => adminActions[i].onSelected(),
          itemBuilder: (_) => [
            for (var i = 0; i < adminActions.length; i++)
              PopupMenuItem<int>(
                value: i,
                child: Row(
                  children: [
                    Icon(
                      adminActions[i].icon,
                      size: 18,
                      color: adminActions[i].destructive ? p.error : p.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      adminActions[i].label,
                      style: TextStyle(
                        color: adminActions[i].destructive ? p.error : p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      if (onJoin != null)
        OutlinedButton.icon(
          onPressed: onJoin,
          style: compact,
          icon: const Icon(Icons.videocam_outlined, size: 16),
          label: const Text('Join meeting'),
        ),
      FilledButton(onPressed: onView, style: compact, child: Text(viewLabel)),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Buttons take what they need (shrinking on a narrow card rather
          // than overflowing); the note gets the rest.
          final maxButtons = footerNote == null
              ? constraints.maxWidth - 8
              : constraints.maxWidth * 0.75;
          return Row(
            children: [
              Expanded(
                child: footerNote == null
                    ? const SizedBox.shrink()
                    : Text(
                        footerNote!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          fontSize: 12.5,
                          color: p.textMuted,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxButtons < 0 ? 0 : maxButtons),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        buttons[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _clock(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// "Sun, 11 Oct · 7:00 PM – 10:00 PM", or a date range across days.
  static String _when(DateTime start, DateTime? end) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    String date(DateTime d) => '${days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
    if (end == null) return '${date(start)} · ${_clock(start)}';
    final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    return sameDay
        ? '${date(start)} · ${_clock(start)} – ${_clock(end)}'
        : '${date(start)} – ${date(end)}';
  }
}

/// Lays out [EventCard]s like the website grid: as many columns of at least
/// [EventCard.minWidth] as fit (up to four), 12px apart, every card the same
/// height.
class EventCardGrid extends StatelessWidget {
  const EventCardGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.admin = false,
    this.padding = EdgeInsets.zero,
    this.physics,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool admin;
  final EdgeInsets padding;
  final ScrollPhysics? physics;

  static int columnsFor(double width) {
    final columns = ((width + EventCard.gap) / (EventCard.minWidth + EventCard.gap)).floor();
    return columns.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usable = constraints.maxWidth - padding.horizontal;
        return GridView.builder(
          padding: padding,
          physics: physics,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnsFor(usable),
            crossAxisSpacing: EventCard.gap,
            mainAxisSpacing: EventCard.gap,
            mainAxisExtent: admin ? EventCard.adminHeight : EventCard.height,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

// ── Parts ───────────────────────────────────────────────────────────────────

/// Website `.sc-card`: card fill, hairline border, 12px radius; on hover it
/// lifts 2px with a stronger border (the fill stays). Events you created
/// get a gold tint (website `.card--own`).
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child, required this.onTap, required this.highlighted});

  final Widget child;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = widget.highlighted
        ? Color.alphaBlend(p.primary.withValues(alpha: 0.08), p.card)
        : p.card;
    final border = widget.highlighted
        ? p.primary.withValues(alpha: 0.45)
        : (_hover ? p.borderHover : p.border);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          // Fill only changes for events you created, as on the website;
          // hover is just the lift and the border.
          color: base,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          // No hover wash from the ink either: hover is the lift and border.
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.imageUrl,
    required this.start,
    required this.isVirtual,
    required this.brand,
  });

  static const double height = 116;

  final String? imageUrl;
  final DateTime? start;
  final bool isVirtual;
  final EventCardBrand brand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final accent = brand.accent ?? p.primary;
    final placeholder = _Placeholder(accent: accent, isVirtual: isVirtual, logoUrl: brand.logoUrl);
    final url = imageUrl?.trim();
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null || url.isEmpty)
            placeholder
          else
            Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
          if (start != null)
            Positioned(
              left: 12,
              top: 12,
              child: _DateTile(date: start!, accent: accent),
            ),
        ],
      ),
    );
  }
}

/// No image: an even tint of the event's accent with the mode.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.accent, required this.isVirtual, this.logoUrl});

  final Color accent;
  final bool isVirtual;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // One even tint: a diagonal fade read as a smudge on the light theme.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.14), p.card),
      ),
      child: Align(
        alignment: const Alignment(0.55, 0.1),
        child: logoUrl != null
            ? Image.network(logoUrl!, height: 56, errorBuilder: (_, _, _) => const SizedBox())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVirtual ? Icons.videocam_outlined : Icons.groups_outlined,
                    size: 38,
                    color: accent.withValues(alpha: 0.75),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVirtual ? 'ONLINE' : 'IN PERSON',
                    style: AppTextStyles.eyebrow.copyWith(
                      color: accent.withValues(alpha: 0.85),
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.accent});

  final DateTime date;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            EventCard._months[date.month - 1].toUpperCase(),
            style: AppTextStyles.eyebrow.copyWith(color: accent, fontSize: 10.5),
          ),
          Text(
            '${date.day}',
            style: AppTextStyles.headlineSmall.copyWith(
              fontSize: 22,
              height: 1.1,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Website `.sc-community-badge`: small rounded pill in a faint tint of
/// [tone].
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: tone,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(icon, size: 15, color: p.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 13, color: p.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.registered, required this.capacity});

  final int registered;
  final int? capacity;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cap = capacity;
    final fraction = cap != null && cap > 0 ? (registered / cap).clamp(0.0, 1.0) : 0.0;
    final tone = fraction >= 1
        ? p.error
        : fraction >= 0.9
        ? p.warning
        : p.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Capacity',
              style: AppTextStyles.labelSmall.copyWith(color: p.textMuted),
            ),
            const Spacer(),
            Text(
              cap == null ? '$registered registered' : '$registered / $cap',
              style: AppTextStyles.labelSmall.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: p.surfaceHover,
            valueColor: AlwaysStoppedAnimation<Color>(tone),
          ),
        ),
      ],
    );
  }
}
