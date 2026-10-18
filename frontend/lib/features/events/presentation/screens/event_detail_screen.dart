import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../routes/app_routes.dart';
import '../../../../routes/return_after_sign_in.dart';
import '../../../../shared/widgets/page_insets.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../auth/services/auth_controller.dart';
import '../../../admin/presentation/event_admin_actions.dart' show EventAdminActions;
import '../providers/event_detail_provider.dart';
import '../../domain/event.dart';
import '../../domain/my_event_registration.dart' show EventGuest;
import '../widgets/entry_pass_qr.dart';
import '../widgets/refund_status_dialog.dart' show showRefundStatus;
import '../widgets/unregister_flow.dart' show confirmAndCancelGuest;
import '../widgets/venue_section.dart';
import '../../../../shared/widgets/form_fields.dart';
import '../../../../shared/widgets/notice.dart';
import '../../../../shared/widgets/simple_markdown.dart';
import '../../../../shared/web/browser.dart';
import '../../domain/event_link.dart' show eventLinkUrl;
import '../../../../shared/format.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          showNotice(context, 'Could not launch $urlString', kind: NoticeKind.error);
        }
      }
    } catch (_) {
      if (mounted) {
        showNotice(context, 'Could not launch $urlString', kind: NoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventDetailProvider(widget.eventId));
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.session?.access.canAdminEvent(widget.eventId) ?? false;

    if (state.isLoading && state.event == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (state.errorMessage != null && state.event == null) {
      final notAvailable =
          state.errorMessage == EventDetailNotifier.notAvailableMessage;
      return Scaffold(
        body: _pageFrame(
          title: null,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    notAvailable ? Icons.event_busy_outlined : Icons.error_outline,
                    size: 48,
                    color: notAvailable ? context.palette.textMuted : context.palette.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge.copyWith(color: context.palette.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (notAvailable)
                    FilledButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: const Text('See all events'),
                    )
                  else
                    FilledButton(
                      onPressed: () => ref
                          .read(eventDetailProvider(widget.eventId).notifier)
                          .fetchEventDetails(widget.eventId),
                      child: const Text('Try again'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final event = state.event;
    if (event == null) {
      return const Scaffold(
        body: Center(child: Text('Event not found')),
      );
    }

    return _buildMaterialLayout(event, state, isAdmin: isAdmin);
  }

  // ==========================================
  // LAYOUT
  // ==========================================
  Widget _buildMaterialLayout(AppEvent event, EventDetailState state, {required bool isAdmin}) {
    final isWebScreen = MediaQuery.of(context).size.width >= 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Website detail page: no back bar; a breadcrumb lined up with the
    // content, and "Back" at the end of the page.
    final unpublished = event.status != 'published';

    if (isWebScreen) {
      return Scaffold(
        body: _pageFrame(
          title: event.title,
          banner: unpublished ? _statusNotice(event) : null,
          child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 7,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (event.bannerUrl != null || event.thumbnailUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                event.bannerUrl ?? event.thumbnailUrl!,
                                height: 320,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                // An image that fails to load is left out (F9).
                                errorBuilder: (_, _, _) => const SizedBox.shrink(),
                              ),
                            ),
                          const SizedBox(height: 24),
                          Text(
                            event.title,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: context.palette.textPrimary,
                                ),
                          ),
                          if (event.tagline != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              event.tagline!,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: context.palette.textMuted,
                                    fontStyle: FontStyle.italic,
                                  ),
                            ),
                          ],
                          _organiserLine(event, isAdmin: isAdmin),
                          const SizedBox(height: 16),
                          _buildMaterialMetaGrid(event),
                          if (_hasDescription(event)) ...[
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                            _buildAboutSection(event),
                          ],
                          if (VenueSection.hasVenue(event)) ...[
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                            VenueSection(event: event),
                          ],
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildSponsorsSection(event, isDark),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          if (event.fees.isNotEmpty) ...[
                            _buildFeesSection(event),
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),
                          ],
                          _buildAgendaSection(event),
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildSpeakersSection(event),
                          const SizedBox(height: 32),
                          _backLink(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 3,
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: context.palette.card,
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Registration',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
                              ),
                              const SizedBox(height: 12),
                              if (isAdmin) _buildCapacityBar(event, isDark),
                              const SizedBox(height: 16),
                              if (unpublished)
                                Text(
                                  'Registration opens once the event is published.',
                                  style: TextStyle(color: context.palette.textSecondary),
                                )
                              else
                                _buildRegistrationCTA(state),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        ),
      );
    } else {
      // Phones and narrow windows: everything scrolls, breadcrumb included.
      return Scaffold(
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _breadcrumb(event.title),
                if (unpublished) ...[
                  const SizedBox(height: 12),
                  _statusNotice(event),
                ],
                const SizedBox(height: 16),
                if (event.bannerUrl != null || event.thumbnailUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      event.bannerUrl ?? event.thumbnailUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // An image that fails to load is left out (F9).
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  event.title,
                  style: const TextStyle(fontFamily: AppTextStyles.serif, fontSize: 22, fontWeight: FontWeight.w600),
                ),
                if (event.tagline != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.tagline!,
                    style: TextStyle(fontSize: 14, color: context.palette.textMuted, fontStyle: FontStyle.italic),
                  ),
                ],
                _organiserLine(event, isAdmin: isAdmin),
                const SizedBox(height: 16),
                _buildMaterialMetaRow(Icons.calendar_today, _eventDateLabel(event)),
                _buildMaterialMetaRow(Icons.access_time, _eventTimeLabel(event)),
                _buildMaterialMetaRow(
                  event.isVirtual ? Icons.videocam : Icons.location_on,
                  event.locationText ?? (event.isVirtual ? 'Virtual Link' : 'To Be Decided'),
                  onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
                      ? () => _launchUrl(event.locationMapsUrl!)
                      : null,
                ),
                _buildMaterialMetaRow(Icons.currency_rupee, _eventFeeLabel(event)),
                const SizedBox(height: 16),
                const Divider(),
                if (isAdmin) ...[
                  const SizedBox(height: 8),
                  _buildCapacityBar(event, isDark),
                  const SizedBox(height: 16),
                ],
                if (!unpublished) _buildRegistrationCTA(state),
                if (_hasDescription(event)) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildAboutSection(event),
                ],
                if (VenueSection.hasVenue(event)) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  VenueSection(event: event),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildSponsorsSection(event, isDark),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                if (event.fees.isNotEmpty) ...[
                  _buildFeesSection(event),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                _buildAgendaSection(event),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildSpeakersSection(event),
                const SizedBox(height: 24),
                _backLink(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    }
  }

  // ── Page frame (website detail page) ──────────────────────────────────

  /// Wide screens: the site header's container (1520px, page side padding),
  /// breadcrumb and optional status notice on top, [child] filling the rest.
  Widget _pageFrame({required String? title, required Widget child, Widget? banner}) {
    return PageContainer(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _breadcrumb(title),
            if (banner != null) ...[const SizedBox(height: 12), banner],
            const SizedBox(height: 20),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// Website breadcrumb: "Events › Event title".
  Widget _breadcrumb(String? title) {
    final p = context.palette;
    final style = AppTextStyles.bodySmall.copyWith(fontSize: 13);
    return Row(
      children: [
        InkWell(
          onTap: () => context.go(AppRoutes.home),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Events', style: style.copyWith(color: p.primary)),
          ),
        ),
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('›', style: style.copyWith(color: p.textMuted)),
          ),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  /// Website "← Back to …" at the end of the page: back to wherever you came
  /// from (Events or Admin), or to Events when opened directly.
  Widget _backLink() {
    return TextButton.icon(
      onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
      icon: const Icon(Icons.arrow_back, size: 16),
      label: const Text('Back'),
    );
  }

  /// Shown to admins on an event that isn't published.
  Widget _statusNotice(AppEvent event) {
    final p = context.palette;
    final (tone, text) = switch (event.status) {
      'draft' => (
          p.warning,
          'Draft: only admins can see this page. Publish it from Admin › Events.',
        ),
      'cancelled' => (p.error, 'Cancelled: this event was cancelled and is no longer listed.'),
      'completed' => (p.textMuted, 'Completed: this event is closed.'),
      _ => (p.textMuted, 'Not published: only admins can see this page.'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 18, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(text, style: AppTextStyles.bodySmall.copyWith(fontSize: 13.5, color: p.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialMetaRow(IconData icon, String text, {VoidCallback? onTap}) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: onTap != null ? context.palette.primary : null,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 18, color: context.palette.primary),
        const SizedBox(width: 10),
        Expanded(
          child: textWidget,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: row,
            )
          : row,
    );
  }

  Widget _buildMaterialMetaGrid(AppEvent event) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _buildMetaGridItem(Icons.calendar_today, _eventDateLabel(event)),
        _buildMetaGridItem(Icons.access_time, _eventTimeLabel(event)),
        _buildMetaGridItem(
          event.isVirtual ? Icons.videocam : Icons.location_on,
          event.locationText ?? (event.isVirtual ? 'Virtual Link' : 'To Be Decided'),
          onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
              ? () => _launchUrl(event.locationMapsUrl!)
              : null,
        ),
        _buildMetaGridItem(Icons.currency_rupee, _eventFeeLabel(event)),
      ],
    );
  }

  Widget _buildMetaGridItem(IconData icon, String text, {VoidCallback? onTap}) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: onTap != null ? context.palette.primary : null,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 18, color: context.palette.primary),
        const SizedBox(width: 8),
        Expanded(child: textWidget),
      ],
    );

    return SizedBox(
      width: 250,
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(4),
              child: row,
            )
          : row,
    );
  }

  /// The description is optional; without one there is no About part.
  bool _hasDescription(AppEvent event) => (event.description ?? '').trim().isNotEmpty;

  Widget _buildAboutSection(AppEvent event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About the Event',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
        ),
        const SizedBox(height: 10),
        // Simple Markdown (headings, lists, **bold**, links), as the schema
        // says; plain text shows as typed, line breaks kept (F10).
        SimpleMarkdown(event.description!.trim(), keepLineBreaks: true),
      ],
    );
  }

  Widget _buildSponsorsSection(AppEvent event, bool isDark) {
    if (event.sponsors.isEmpty && event.partners.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sponsors',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
          ),
          const SizedBox(height: 12),
          Text('Sponsor details will be updated soon.',
              style: TextStyle(fontSize: 14, color: context.palette.textMuted)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sponsors',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
        ),
        const SizedBox(height: 12),
        if (event.sponsors.isNotEmpty) ...[
          Text('SPONSORS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: context.palette.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          _buildSponsorGrid(event.sponsors, isDark, isSponsor: true),
          const SizedBox(height: 16),
        ],
        if (event.partners.isNotEmpty) ...[
          Text('PARTNERS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: context.palette.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          _buildSponsorGrid(event.partners, isDark, isSponsor: false),
        ],
      ],
    );
  }

  Widget _buildSponsorGrid(List<dynamic> items, bool isDark, {required bool isSponsor}) {
    if (items.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final crossAxisCount = screenWidth > 900 ? 3 : (screenWidth > 600 ? 2 : 1);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 3.2,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (isSponsor) {
          return _buildSponsorGridCard(
            name: (item as EventSponsor).name,
            typeLabel: item.sponsorTypeLabel,
            logoUrl: item.logoUrl,
            websiteUrl: item.websiteUrl,
            isDark: isDark,
          );
        } else {
          return _buildSponsorGridCard(
            name: (item as EventPartner).name,
            typeLabel: item.partnerTypeLabel,
            logoUrl: item.logoUrl,
            websiteUrl: item.websiteUrl,
            isDark: isDark,
          );
        }
      },
    );
  }

  Widget _buildSponsorGridCard({
    required String name,
    required String typeLabel,
    String? logoUrl,
    String? websiteUrl,
    required bool isDark,
  }) {
    final bg = context.palette.surfaceHover;
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (logoUrl != null && logoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                logoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.business, size: 22, color: context.palette.primary),
              ),
            )
          else
            Icon(Icons.business, size: 22, color: context.palette.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: (websiteUrl != null && websiteUrl.isNotEmpty)
                        ? context.palette.primary
                        : null,
                    decoration: (websiteUrl != null && websiteUrl.isNotEmpty)
                        ? TextDecoration.underline
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  typeLabel,
                  style: TextStyle(fontSize: 11, color: context.palette.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (websiteUrl != null && websiteUrl.isNotEmpty) {
      return GestureDetector(
        onTap: () => _launchUrl(websiteUrl),
        child: card,
      );
    }
    return card;
  }

  /// "Organised by …" for everyone; "Edit event" for the event's admins,
  /// opening the same form as Admin → Events.
  Widget _organiserLine(AppEvent event, {required bool isAdmin}) {
    final p = context.palette;
    final who = event.creatorName(ref.read(authControllerProvider).session?.firebaseUid);
    // A draft's link doesn't open for anyone else yet, so no Share.
    final shareable = event.status == 'published';
    if (who == null && !isAdmin && !shareable) return const SizedBox.shrink();
    final link = event.virtualUrl?.trim() ?? '';
    final line = Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          if (who != null)
            Text(
              'Organised by $who',
              style: TextStyle(fontSize: 13, color: p.textSecondary),
            ),
          if (isAdmin)
            TextButton.icon(
              onPressed: () => EventAdminActions(
                context: context,
                ref: ref,
                onChanged: () => ref
                    .read(eventDetailProvider(widget.eventId).notifier)
                    .fetchEventDetails(widget.eventId),
                isBusy: (_) => false,
                setBusy: (_, _) {},
              ).edit(event),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit event'),
            ),
          if (shareable) _shareButton(event),
        ],
      ),
    );
    if (!isAdmin || !event.isVirtual || link.isEmpty) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [line, _organiserMeetingLink(link)],
    );
  }

  /// Share: the phone's share sheet (WhatsApp…); Copy link on computers.
  /// Both use the event's readable link (`/e/<slug>`).
  Widget _shareButton(AppEvent event) {
    final url = eventLinkUrl(event.slug);
    if (canShareNatively()) {
      return TextButton.icon(
        onPressed: () => shareNatively(title: event.title, url: url),
        icon: const Icon(Icons.share_outlined, size: 16),
        label: const Text('Share'),
      );
    }
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) {
          showNotice(context, 'Link copied: $url', kind: NoticeKind.success);
        }
      },
      icon: const Icon(Icons.link, size: 16),
      label: const Text('Copy link'),
    );
  }

  /// The meeting link, for the event's organisers only. Attendees get it
  /// through Join meeting once registered.
  Widget _organiserMeetingLink(String link) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.videocam_outlined, size: 18, color: p.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(link, style: TextStyle(fontSize: 13, color: p.textPrimary)),
                Text(
                  'Meeting link · only organisers see this',
                  style: TextStyle(fontSize: 11, color: p.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              showNotice(context, 'Meeting link copied', kind: NoticeKind.success);
            },
          ),
        ],
      ),
    );
  }

  /// Join meeting for registered attendees; a note for everyone else.
  Widget? _attendeeMeetingLink(AppEvent event, {required bool registered, String? joinUrl}) {
    if (!event.isVirtual) return null;
    final p = context.palette;
    final url = joinUrl?.trim() ?? '';
    if (registered && url.isNotEmpty) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _launchUrl(url),
          icon: const Icon(Icons.videocam_outlined, size: 18),
          label: const Text('Join meeting'),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      );
    }
    if (registered) return null;
    // Organisers already see the link at the top of the page.
    final isOrganiser =
        ref.read(authControllerProvider).session?.access.canAdminEvent(event.eventId) ?? false;
    if (isOrganiser) return null;
    return Text(
      'The meeting link is shared once you register.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: p.textSecondary),
    );
  }

  /// Fee tiers: what the ticket price covers. Their total is the price.
  Widget _buildFeesSection(AppEvent event) {
    final p = context.palette;
    final total = event.fees.fold<double>(0, (sum, f) => sum + f.amount);
    final rowStyle = TextStyle(fontSize: 14, color: p.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What the price covers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.primary),
        ),
        const SizedBox(height: 12),
        for (final f in event.fees)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: Text(f.name, style: rowStyle)),
                Text(formatMoney(f.amount), style: rowStyle),
              ],
            ),
          ),
        Divider(height: 16, color: p.border),
        Row(
          children: [
            Expanded(child: Text('Total', style: rowStyle.copyWith(fontWeight: FontWeight.w600))),
            Text(formatMoney(total), style: rowStyle.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _buildAgendaSection(AppEvent event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agenda',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
        ),
        const SizedBox(height: 12),
        if (event.sessions.isEmpty)
          Text('Agenda will be updated soon.', style: TextStyle(fontSize: 14, color: context.palette.textMuted))
        else
          ...event.sessions.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatSessionTime(item),
                  style: TextStyle(color: context.palette.primary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(_formatSessionTitle(item), style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSpeakersSection(AppEvent event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Speakers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
        ),
        const SizedBox(height: 12),
        if (event.speakers.isEmpty)
          Text('Speaker details will be updated soon.', style: TextStyle(fontSize: 14, color: context.palette.textMuted))
        else
          ...event.speakers.map((sp) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              children: [
                _buildSpeakerAvatar(
                  sp,
                  radius: 20,
                  accentColor: context.palette.primary,
                  initialsStyle: TextStyle(color: context.palette.primary, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sp.fullname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(sp.subtitle, style: TextStyle(fontSize: 12, color: context.palette.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSpeakerAvatar(
    EventPerson speaker, {
    required double radius,
    required Color accentColor,
    required TextStyle initialsStyle,
  }) {
    final photoUrl = speaker.photoUrl?.trim();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: accentColor.withValues(alpha: 0.15),
      child: Text(speaker.initials, style: initialsStyle),
    );

    if (photoUrl == null || photoUrl.isEmpty) {
      return fallback;
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _buildCapacityBar(AppEvent event, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Registered Capacity', style: TextStyle(fontSize: 13)),
            Text(
              event.capacity != null
                  ? '${event.registeredCount} / ${event.capacity}'
                  : '${event.registeredCount} Registered',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: event.capacity != null && event.capacity! > 0
                ? event.registeredCount / event.capacity!
                : 0,
            minHeight: 6,
            backgroundColor: context.palette.surfaceHover,
            valueColor: AlwaysStoppedAnimation<Color>(context.palette.primary),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // REGISTRATION BUTTONS & DIALOG FLOWS
  // ==========================================
  Widget _buildRegistrationCTA(EventDetailState state) {
    final event = state.event;
    if (event == null) return const SizedBox.shrink();
    final signedIn = ref.read(authControllerProvider).isAuthenticated;
    // Signed out there is no eligibility check: the event's own status
    // (open, full, closed, not_open_yet) says the same in the same words.
    final eligibility =
        state.eligibilityStatus ?? (signedIn ? null : event.registrationStatus);

    final isPastEvent = event.endDatetime != null
        ? event.endDatetime!.isBefore(DateTime.now())
        : event.startDatetime.isBefore(DateTime.now());

    // A countdown only makes sense while its moment is still ahead; once
    // the event is over, say so instead.
    final now = DateTime.now();
    Widget? countdownWidget;
    if (isPastEvent) {
      countdownWidget = _endedNotice();
    } else if (event.registrationStatus == 'open' &&
        event.registrationClosesAt != null &&
        event.registrationClosesAt!.isAfter(now)) {
      countdownWidget = _buildCountdownSection(
        title: 'Registration closes in',
        countdown: _formatRemainingTime(event.registrationClosesAt!),
        dateLabel: 'Last date to register',
        dateValue: formatDateTime(event.registrationClosesAt!),
      );
    } else if (event.registrationStatus != 'open' &&
        event.registrationOpensAt != null &&
        event.registrationOpensAt!.isAfter(now)) {
      countdownWidget = _buildCountdownSection(
        title: 'Registration opens in',
        countdown: _formatRemainingTime(event.registrationOpensAt!),
        dateLabel: 'Registration opening on',
        dateValue: formatDateTime(event.registrationOpensAt!),
      );
    }

    final registrationStatus =
        state.myRegistration?['status']?.toString().toLowerCase();
    final hasActiveRegistration = registrationStatus == 'registered';
    final hasCancelledRegistration = registrationStatus == 'cancelled';
    // Started but not paid (or the payment failed): the seat is held, and
    // checkout picks this registration up again. Not registered yet.
    final paymentDue = const {'seat_held', 'payment_pending', 'payment_failed'}
        .contains(registrationStatus);
    // Paid, but the payment provider hasn't confirmed it yet (ISSUE-010).
    // Not registered yet either: no QR, and no Complete payment, since the
    // money is already taken. A reload shows the result.
    final confirmingPayment = registrationStatus == 'payment_verification';
    // After a cancellation the backend lets the attendee register again. The
    // Register button comes back only when the backend says so.
    final canRegisterAgain = hasCancelledRegistration &&
        eligibility == 'eligible' &&
        !isPastEvent;

    // Once it's over there is nothing to register for: just say it ended.
    final isRegistered = hasActiveRegistration ||
        (!paymentDue && !confirmingPayment && eligibility == 'already_registered');
    if (isPastEvent && !isRegistered) return _endedNotice();

    Widget ctaWidget;
    if (hasCancelledRegistration && !canRegisterAgain) {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel, color: context.palette.error, size: 20),
            SizedBox(width: 8),
            Text(
              'Unregistered from this event',
              style: TextStyle(
                color: context.palette.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (hasActiveRegistration) {
      final regNo = state.myRegistration!['registration_number'] ?? '';
      ctaWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.success.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: context.palette.success, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Registered Successfully',
                      style: TextStyle(color: context.palette.success, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (regNo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Badge #: $regNo',
                    style: TextStyle(color: context.palette.success, fontSize: 12),
                  ),
                ]
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildQRBadgeSection(state, event),
          ..._buildGuestsSection(state, event),
        ],
      );
    } else if (confirmingPayment) {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.info.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.info.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              'Payment received, confirming…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.palette.info,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This usually takes a minute. Reload the page to see your '
              'registration and QR badge.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    } else if (paymentDue) {
      // Red when the payment failed, yellow when it just isn't finished
      // (same colours as the notices).
      final tone = registrationStatus == 'payment_failed'
          ? context.palette.error
          : context.palette.warning;
      ctaWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tone.withValues(alpha: 0.3)),
            ),
            child: Text(
              registrationStatus == 'payment_failed'
                  ? 'Your payment didn\'t go through, so you aren\'t registered yet.'
                  : 'Your payment isn\'t complete yet, so you aren\'t registered yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tone, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _proceedToCheckout(event),
              child: const Text('Complete payment'),
            ),
          ),
        ],
      );
    } else if (eligibility == 'already_registered') {
      ctaWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.info.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.info.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                'You are registered for this event.',
                style: TextStyle(color: context.palette.info, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildQRBadgeSection(state, event),
        ],
      );
    } else if (eligibility == 'full') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Event is at full capacity.',
            style: TextStyle(color: context.palette.error, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (eligibility == 'closed') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Registration is closed.',
            style: TextStyle(color: context.palette.error, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (eligibility == 'not_open_yet') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Registration is not open yet.',
            style: TextStyle(color: context.palette.error, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (eligibility == 'ineligible') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            state.eligibilityMessage ?? 'Ineligible to register.',
            style: TextStyle(color: context.palette.error, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (isPastEvent) {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.error.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.palette.error.withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            'Registration is unavailable for past events.',
            style: TextStyle(color: context.palette.error, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else {
      // Default eligible: show Register button
      ctaWidget = SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.palette.primary,
            foregroundColor: context.palette.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: signedIn
              ? () => _showRegistrationForm(event, state)
              : () => _signInToRegister(event),
          child: Text(
            signedIn ? 'Register' : 'Sign in to register',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      if (canRegisterAgain) {
        ctaWidget = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You cancelled your earlier registration.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ctaWidget,
          ],
        );
      }
    }

    final meeting = isPastEvent
        ? null
        : _attendeeMeetingLink(
            event,
            registered: isRegistered,
            joinUrl: state.myRegistration?['join_url']?.toString(),
          );
    if (meeting != null) {
      ctaWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [ctaWidget, const SizedBox(height: 12), meeting],
      );
    }

    if (countdownWidget != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          countdownWidget,
          const SizedBox(height: 16),
          ctaWidget,
        ],
      );
    }
    return ctaWidget;
  }

  /// Signed out: to sign-in, then back to this event. The event page is
  /// public, so the router doesn't remember it; this does.
  void _signInToRegister(AppEvent event) {
    ReturnAfterSignIn.save(AppRoutes.eventDetail
        .replaceFirst(':id', '${event.eventId}'));
    context.go(AppRoutes.login);
  }

  /// The registration form: one dialog for every screen size. Alumni see
  /// their name from the alumni record; everyone else types it, starting from
  /// their last registration's name or their sign-in name. Phone is required
  /// for all and starts from their last registration. A free event registers
  /// from the dialog; a paid one goes on to checkout with the details as a
  /// draft in the event's provider, never in the page address.
  void _showRegistrationForm(AppEvent event, EventDetailState state) {
    final auth = ref.read(authControllerProvider);
    final profile = state.alumniProfile ?? const <String, dynamic>{};
    final isAlumni = profile.isNotEmpty;
    final last = state.lastDetails;
    final initialName = last?.fullname ?? auth.session?.fullname ?? '';
    final initialPhone = last?.phone ??
        (isAlumni ? (profile['phone']?.toString() ?? '') : '');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPaid = _isPaidEvent(event);
    final header = _buildEventHeader(event, isDark);
    final infoBox = _buildInfoBox(isDark);
    final notifier = ref.read(eventDetailProvider(widget.eventId).notifier);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _RegistrationFormDialog(
        eventHeader: header,
        infoBox: infoBox,
        alumniName: isAlumni ? (profile['fullname']?.toString() ?? '') : null,
        initialName: initialName,
        email: auth.session?.email ?? '',
        initialPhone: initialPhone,
        unitPrice: isPaid ? event.ticketPrice! : null,
        maxGuests: event.maxGuests,
        isPaid: isPaid,
        onContinue: (draft) {
          notifier.setRegistrationDraft(draft);
          if (isPaid) {
            _proceedToCheckout(event);
          } else {
            _registerFree(event);
          }
        },
      ),
    );
  }

  /// A free event registers straight from the form: no checkout page. The
  /// event page then shows the green "registered" box and the entry pass.
  Future<void> _registerFree(AppEvent event) async {
    final notifier = ref.read(eventDetailProvider(widget.eventId).notifier);
    final ok = await notifier.register(event.eventId);
    if (!mounted) return;
    if (!ok) {
      final message = ref.read(eventDetailProvider(widget.eventId)).errorMessage;
      showNotice(
        context,
        message ?? 'Could not register. Please try again.',
        kind: NoticeKind.error,
      );
      return;
    }
    showNotice(
      context,
      'You\'re registered. Your QR code for entry is on this page and in My Events.',
      kind: NoticeKind.success,
    );
    // Refresh the seat count and eligibility.
    await notifier.fetchEventDetails(event.eventId);
  }

  Widget _buildInfoBox(bool isDark) {
    final infoBg = context.palette.info.withValues(alpha: 0.08);
    final infoText = context.palette.textSecondary;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: infoText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Your QR code for entry will be on this page and in My Events.",
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: infoText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventHeader(AppEvent event, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          style: TextStyle(
            fontFamily: AppTextStyles.serif,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_eventDateLabel(event)} · ${_eventTimeLabel(event)}',
          style: TextStyle(
            fontSize: 12,
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Opens checkout. The form's details travel in the provider's draft.
  void _proceedToCheckout(AppEvent event) {
    context.push('/events/${event.eventId}/checkout');
  }

  // ==========================================
  // HELPER FORMATTERS
  // ==========================================
  /// The last moment of the event. A full-day event is stored ending at
  /// midnight after its last day, which belongs to the day before.
  DateTime? _lastMoment(AppEvent event) {
    final end = event.endDatetime;
    if (end == null) return null;
    return event.isFullDay ? end.subtract(const Duration(minutes: 1)) : end;
  }

  /// "26 Oct 2026", or for several days "26 – 27 Oct 2026 · 2 days".
  String _eventDateLabel(AppEvent event) {
    final start = event.startDatetime;
    final last = _lastMoment(event);
    if (last == null ||
        (last.year == start.year && last.month == start.month && last.day == start.day)) {
      return formatDate(start);
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = DateTime(last.year, last.month, last.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;
    final String range;
    if (start.year != last.year) {
      range = '${formatDate(start)} – ${formatDate(last)}';
    } else if (start.month != last.month) {
      range = '${start.day} ${months[start.month - 1]} – ${last.day} ${months[last.month - 1]} ${last.year}';
    } else {
      range = '${start.day} – ${last.day} ${months[last.month - 1]} ${last.year}';
    }
    return '$range · $days days';
  }

  /// "9:00 AM – 5:00 PM" for one day; across days, when it starts and ends.
  String _eventTimeLabel(AppEvent event) {
    if (event.isFullDay) return 'All day';
    final start = event.startDatetime;
    final end = event.endDatetime;
    if (end == null) return formatTimeRange(start, null);
    final sameDay = end.year == start.year && end.month == start.month && end.day == start.day;
    if (sameDay) return formatTimeRange(start, end);
    return 'Starts ${formatTimeRange(start, null)}, ends ${formatTimeRange(end, null)}';
  }

  String _formatSessionTime(EventSession session) {
    return formatTimeRange(session.startDatetime, session.endDatetime);
  }

  String _formatSessionTitle(EventSession session) {
    final parts = [
      session.title,
      if (session.speakerName != null && session.speakerName!.trim().isNotEmpty)
        session.speakerName!.trim(),
    ];
    return parts.join(' - ');
  }

  String _formatRemainingTime(DateTime target) {
    final now = DateTime.now();
    final difference = target.difference(now);
    if (difference.isNegative) {
      return '00 Days: 00 hours: 00 Minutes';
    }
    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;
    return '${days.toString().padLeft(2, '0')} Days: ${hours.toString().padLeft(2, '0')} hours: ${minutes.toString().padLeft(2, '0')} Minutes';
  }

  bool _isPaidEvent(AppEvent event) {
    return !(event.isFree ?? true) &&
        (event.ticketPrice?.isFinite ?? false) &&
        (event.ticketPrice! > 0);
  }

  /// 'Event Fee: ₹X' for paid events, otherwise 'Free Event'.
  String _eventFeeLabel(AppEvent event) {
    if (_isPaidEvent(event)) {
      final price = event.ticketPrice!;
      return 'Event Fee: ${formatMoney(price)}';
    }
    return 'Free Event';
  }

  /// Shown in place of a countdown once the event is over.
  Widget _endedNotice() {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_available_outlined, size: 18, color: p.textMuted),
          const SizedBox(width: 8),
          Text(
            'This event has ended',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownSection({
    required String title,
    required String countdown,
    required String dateLabel,
    required String dateValue,
  }) {
    final cardBg = context.palette.surfaceSubtle;
    final borderColor = context.palette.primary.withValues(alpha: 0.3);
    final textColor = context.palette.textPrimary;
    final subTextColor = context.palette.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.primary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            countdown,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 0.5),
        const SizedBox(height: 8),
        Text(
          '$dateLabel: $dateValue',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: subTextColor,
          ),
        ),
      ],
    ),
  );
}

  Widget _buildQRBadgeSection(EventDetailState state, AppEvent event) {
    final infoBg = context.palette.info.withValues(alpha: 0.08);
    final infoTextColor = context.palette.textSecondary;
    final regNo = state.myRegistration?['registration_number'] ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 340;

        final viewButton = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.palette.primary,
            foregroundColor: context.palette.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          onPressed: () => _showQRBadgeDialog(event, regNo, state),
          child: const Text(
            'View QR badge',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        );

        final eventsButton = OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: context.palette.textPrimary,
            side: BorderSide(
              color: context.palette.textMuted,
              width: 1,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 0,
          ),
          onPressed: () {
            context.go(AppRoutes.myEvents);
          },
          child: const Text(
            'Go to My Events',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        );

        Widget buttonsWidget;
        if (useVerticalLayout) {
          buttonsWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              viewButton,
              const SizedBox(height: 12),
              eventsButton,
            ],
          );
        } else {
          buttonsWidget = Row(
            children: [
              Expanded(child: viewButton),
              const SizedBox(width: 12),
              Expanded(child: eventsButton),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: infoBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Your QR badge is ready in My Events — present it at the venue for check-in.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: infoTextColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            buttonsWidget,
          ],
        );
      },
    );
  }

  /// The registrant's guests under their own pass: each with their QR (to
  /// show or forward) and, while still coming and until the event starts,
  /// ✕ to cancel just them.
  List<Widget> _buildGuestsSection(EventDetailState state, AppEvent event) {
    final guests = EventGuest.listFromJson(state.myRegistration?['guests']);
    if (guests.isEmpty) return const [];
    final p = context.palette;
    final active = guests.where((g) => g.isActive).length;
    final leader = state.myRegistration?['fullname_snapshot']?.toString() ?? '';
    final refundLabel =
        _isPaidEvent(event) ? formatMoney(event.ticketPrice!) : null;
    return [
      const SizedBox(height: 20),
      Text(
        active == 0
            ? 'Your guests'
            : 'You + $active ${active == 1 ? 'guest' : 'guests'}',
        style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
      ),
      const SizedBox(height: 8),
      for (final guest in guests)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border.all(color: p.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      guest.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: guest.isActive ? p.textPrimary : p.textMuted,
                        decoration:
                            guest.isActive ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    if (!guest.isActive)
                      Text(
                        'Cancelled',
                        style: TextStyle(fontSize: 12, color: p.textMuted),
                      ),
                  ],
                ),
              ),
              if (guest.isActive && (guest.qrToken ?? '').isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showGuestPassDialog(event, guest, leader),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('QR'),
                ),
              // A paid guest cancelled alone: their refund, on its own.
              if (!guest.isActive && _isPaidEvent(event))
                TextButton(
                  onPressed: () => showRefundStatus(
                    context,
                    ref,
                    registrationId: guest.registrationId,
                  ),
                  child: const Text('View refund'),
                ),
              // Like Unregister (canCancelAt): only until the event starts.
              if (guest.isActive && event.startDatetime.isAfter(DateTime.now()))
                IconButton(
                  tooltip: 'Cancel ${guest.name}',
                  icon: const Icon(Icons.close),
                  onPressed: () => confirmAndCancelGuest(
                    context,
                    ref,
                    guest: guest,
                    refundLabel: refundLabel,
                    onDone: () => ref
                        .read(eventDetailProvider(widget.eventId).notifier)
                        .fetchEventDetails(widget.eventId),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  /// A guest's entry pass, to show at the door or screenshot and forward.
  void _showGuestPassDialog(AppEvent event, EventGuest guest, String leader) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.palette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Guest entry pass',
                      style: TextStyle(
                        fontFamily: AppTextStyles.serif,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                event.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                guest.name,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              if (leader.isNotEmpty)
                Text(
                  'Guest of $leader',
                  style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                ),
              const SizedBox(height: 16),
              EntryPassQr(eventId: event.eventId, qrToken: guest.qrToken!),
              if ((guest.registrationNumber ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Badge Number: ${guest.registrationNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showQRBadgeDialog(AppEvent event, String regNo, EventDetailState state) {
    final auth = ref.read(authControllerProvider);
    final registration = state.myRegistration;
    final userName = registration?['fullname_snapshot']?.toString() ??
        state.alumniProfile?['fullname'] ??
        auth.session?.fullname ??
        'Attendee';
    final email = registration?['email_snapshot']?.toString() ??
        auth.session?.email ??
        '';
    final qrToken = registration?['qr_token']?.toString();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: context.palette.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Your Event Badge',
                      style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.canvas,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        userName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (qrToken != null && qrToken.isNotEmpty)
                        EntryPassQr(eventId: event.eventId, qrToken: qrToken)
                      else
                        Text(
                          'Your entry pass appears here once your registration is confirmed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
                        ),
                      const SizedBox(height: 16),
                      if (regNo.isNotEmpty)
                        Text(
                          'Badge Number: $regNo',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The registration form's dialog. Owns its fields and validation; hands a
/// [RegistrationDraft] to [onContinue] once everything is filled in.
class _RegistrationFormDialog extends StatefulWidget {
  const _RegistrationFormDialog({
    required this.eventHeader,
    required this.infoBox,
    required this.alumniName,
    required this.initialName,
    required this.email,
    required this.initialPhone,
    required this.unitPrice,
    required this.maxGuests,
    required this.isPaid,
    required this.onContinue,
  });

  final Widget eventHeader;
  final Widget infoBox;

  /// The name from the alumni record, or null for non-alumni (who type it).
  final String? alumniName;

  /// Where a non-alumni's name starts: their last registration's name, else
  /// their sign-in name. They can change it.
  final String initialName;
  final String email;
  final String initialPhone;

  /// One person's price (paid events); null for a free event.
  final double? unitPrice;

  /// Guests allowed (0 = no guests section).
  final int maxGuests;
  final bool isPaid;
  final ValueChanged<RegistrationDraft> onContinue;

  @override
  State<_RegistrationFormDialog> createState() => _RegistrationFormDialogState();
}

class _RegistrationFormDialogState extends State<_RegistrationFormDialog> {
  static const _noteMaxLength = 500;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _phone =
      TextEditingController(text: widget.initialPhone);
  final _note = TextEditingController();

  /// One name field per guest, in the order added.
  final _guests = <TextEditingController>[];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    for (final g in _guests) {
      g.dispose();
    }
    super.dispose();
  }

  void _addGuest() => setState(() => _guests.add(TextEditingController()));

  void _removeGuest(int index) => setState(() => _guests.removeAt(index).dispose());

  int get _people => 1 + _guests.length;

  String get _totalLabel {
    final unit = widget.unitPrice;
    if (unit == null) return 'Free';
    if (_people == 1) return formatMoney(unit);
    return '$_people people × ${formatMoney(unit)} = ${formatMoney(unit * _people)}';
  }

  /// Same rule as the server: 10–15 digits once spaces, dashes and a
  /// leading + are removed.
  static bool _phoneIsValid(String phone) {
    var digits = phone.trim();
    if (digits.startsWith('+')) digits = digits.substring(1);
    digits = digits.replaceAll(' ', '').replaceAll('-', '');
    return RegExp(r'^\d{10,15}$').hasMatch(digits);
  }

  void _continue() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = RegistrationDraft(
      fullname: widget.alumniName == null ? _name.text.trim() : null,
      phone: _phone.text.trim(),
      note: _note.text.trim(),
      guests: [for (final g in _guests) g.text.trim()],
    );
    Navigator.of(context).pop();
    widget.onContinue(draft);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final narrow = MediaQuery.sizeOf(context).width < 480;
    final primaryLabel = widget.isPaid ? 'Continue to payment' : 'Register';

    final cancel = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );
    final primary = ElevatedButton(
      onPressed: _continue,
      child: Text(primaryLabel),
    );

    return Dialog(
      backgroundColor: p.card,
      insetPadding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(narrow ? 16 : 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Register',
                        style: TextStyle(
                          fontFamily: AppTextStyles.serif,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                widget.eventHeader,
                const FormSectionLabel('Your details'),
                const SizedBox(height: 16),
                if (widget.alumniName != null)
                  LabeledField(
                    label: 'Name',
                    helper: 'From your alumni record.',
                    child: ReadOnlyValue(widget.alumniName!),
                  )
                else
                  LabeledField(
                    label: 'Name',
                    child: TextFormField(
                      key: const ValueKey('registration-name'),
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        hintText: 'Your full name',
                        counterText: '',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Please enter your name.'
                          : null,
                    ),
                  ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Email',
                  helper: 'Your sign-in email.',
                  child: ReadOnlyValue(widget.email),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Phone',
                  child: TextFormField(
                    key: const ValueKey('registration-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 20,
                    decoration: const InputDecoration(
                      hintText: '+91 98450 12345',
                      counterText: '',
                    ),
                    validator: (v) {
                      final phone = (v ?? '').trim();
                      if (phone.isEmpty) {
                        return 'Please enter a phone number we can reach you on.';
                      }
                      if (!_phoneIsValid(phone)) {
                        return 'Please enter a valid phone number.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Note',
                  optional: true,
                  child: TextFormField(
                    key: const ValueKey('registration-note'),
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: _noteMaxLength,
                    decoration: const InputDecoration(
                      hintText: 'Anything the organisers should know',
                    ),
                  ),
                ),
                if (widget.maxGuests > 0) ...[
                  const SizedBox(height: 8),
                  const FormSectionLabel('Guests'),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _guests.length; i++) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: ValueKey('registration-guest-$i'),
                            controller: _guests[i],
                            textCapitalization: TextCapitalization.words,
                            maxLength: 120,
                            decoration: InputDecoration(
                              hintText: 'Guest ${i + 1}: full name',
                              counterText: '',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Please enter the guest\'s name.'
                                : null,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove guest',
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeGuest(i),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_guests.length < widget.maxGuests)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('registration-add-guest'),
                        onPressed: _addGuest,
                        icon: const Icon(Icons.add),
                        label: Text(
                          'Add a guest (up to ${widget.maxGuests})',
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total',
                      style: AppTextStyles.titleMedium.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _totalLabel,
                        textAlign: TextAlign.right,
                        style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (narrow) ...[
                  primary,
                  const SizedBox(height: 10),
                  cancel,
                ] else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      cancel,
                      const SizedBox(width: 12),
                      primary,
                    ],
                  ),
                const SizedBox(height: 16),
                widget.infoBox,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
