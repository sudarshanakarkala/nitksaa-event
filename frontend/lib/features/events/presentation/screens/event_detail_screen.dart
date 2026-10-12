import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/page_insets.dart';
import '../../../../theme/app_palette.dart';
import '../../../../theme/app_text_styles.dart';
import '../../../auth/services/auth_controller.dart';
import '../../../admin/presentation/event_admin_actions.dart' show EventAdminActions;
import '../providers/event_detail_provider.dart';
import '../../domain/event.dart';
import '../widgets/venue_section.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not launch $urlString')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final state = ref.watch(eventDetailProvider(widget.eventId));
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.session?.access.canAdminEvent(widget.eventId) ?? false;

    if (state.isLoading && state.event == null) {
      return Scaffold(
        body: Center(
          child: isIOS
              ? const CupertinoActivityIndicator(radius: 16)
              : const CircularProgressIndicator(),
        ),
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

    if (isIOS) {
      return _buildCupertinoLayout(event, state, isAdmin: isAdmin);
    } else {
      return _buildMaterialLayout(event, state, isAdmin: isAdmin);
    }
  }

  // ==========================================
  // CUPERTINO LAYOUT (iOS)
  // ==========================================
  Widget _buildCupertinoLayout(AppEvent event, EventDetailState state, {required bool isAdmin}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = context.palette.background;
    final cardBg = context.palette.card;
    final textPrimary = context.palette.textPrimary;
    final textSecondary = context.palette.textSecondary;
    final accentGold = context.palette.primary;

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.left_chevron, size: 20, color: context.palette.primary),
              Text('Back', style: TextStyle(color: context.palette.primary)),
            ],
          ),
          onPressed: () => context.pop(),
        ),
        middle: Text(
          event.title,
          style: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (event.bannerUrl != null || event.thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          event.bannerUrl ?? event.thumbnailUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 180,
                            color: context.palette.textMuted.withOpacity(0.2),
                            child: const Icon(CupertinoIcons.photo, size: 48),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      event.title,
                      style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary),
                    ),
                    if (event.tagline != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.tagline!,
                        style: TextStyle(fontSize: 14, color: textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildCupertinoMetaRow(CupertinoIcons.calendar, _eventDateLabel(event), textSecondary),
                    _buildCupertinoMetaRow(CupertinoIcons.clock, _eventTimeLabel(event), textSecondary),
                    _buildCupertinoMetaRow(
                      event.isVirtual ? CupertinoIcons.videocam : CupertinoIcons.location,
                      event.locationText ?? (event.isVirtual ? 'Virtual Zoom Link' : 'To Be Decided'),
                      textSecondary,
                      onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
                          ? () => _launchUrl(event.locationMapsUrl!)
                          : null,
                    ),
                    _buildCupertinoMetaRow(
                      CupertinoIcons.money_dollar,
                      _eventFeeLabel(event),
                      textSecondary,
                    ),
                    const SizedBox(height: 16),
                    _buildCupertinoDivider(isDark),
                    if (isAdmin) ...[
                      const SizedBox(height: 8),
                      _buildCupertinoSectionHeader('Capacity Status', textSecondary),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Registered', style: TextStyle(color: textSecondary, fontSize: 13)),
                          Text(
                            event.capacity != null
                                ? '${event.registeredCount} / ${event.capacity}'
                                : '${event.registeredCount} Registered',
                            style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 6,
                          child: LinearProgressIndicator(
                            value: event.capacity != null && event.capacity! > 0
                                ? event.registeredCount / event.capacity!
                                : 0,
                            backgroundColor: context.palette.surfaceHover,
                            valueColor: AlwaysStoppedAnimation<Color>(accentGold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCupertinoDivider(isDark),
                    ],
                    const SizedBox(height: 8),
                    _buildCupertinoSectionHeader('Sponsors', textSecondary),
                    const SizedBox(height: 8),
                    _buildCupertinoSponsorChips(event, cardBg, textPrimary, textSecondary),
                    const SizedBox(height: 16),
                    _buildCupertinoDivider(isDark),
                    const SizedBox(height: 8),
                    _buildCupertinoSectionHeader('About', textSecondary),
                    const SizedBox(height: 6),
                    Text(
                      event.description ?? 'No description provided for this event.',
                      style: TextStyle(fontSize: 14, color: textPrimary, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    _buildCupertinoDivider(isDark),
                    const SizedBox(height: 8),
                    _buildCupertinoSectionHeader('Agenda', textSecondary),
                    const SizedBox(height: 8),
                    if (event.sessions.isEmpty)
                      Text('Agenda will be updated soon.', style: TextStyle(color: textSecondary, fontSize: 13))
                    else
                      ...event.sessions.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatSessionTime(item),
                              style: TextStyle(color: accentGold, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_formatSessionTitle(item), style: TextStyle(color: textPrimary, fontSize: 13)),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    _buildCupertinoDivider(isDark),
                    const SizedBox(height: 8),
                    _buildCupertinoSectionHeader('Speakers', textSecondary),
                    const SizedBox(height: 8),
                    if (event.speakers.isEmpty)
                      Text('Speaker details will be updated soon.', style: TextStyle(color: textSecondary, fontSize: 13))
                    else
                      ...event.speakers.map((sp) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            _buildSpeakerAvatar(
                              sp,
                              radius: 16,
                              accentColor: accentGold,
                              initialsStyle: TextStyle(color: accentGold, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(sp.fullname, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textPrimary)),
                                  Text(sp.subtitle, style: TextStyle(fontSize: 11, color: textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border(top: BorderSide(color: textSecondary.withOpacity(0.15), width: 0.5)),
              ),
              child: _buildRegistrationCTA(state, isIOS: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCupertinoMetaRow(IconData icon, String text, Color color, {VoidCallback? onTap}) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: onTap != null ? context.palette.primary : color,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 16, color: context.palette.primary),
        const SizedBox(width: 8),
        Expanded(
          child: textWidget,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: onTap != null
          ? GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: row,
            )
          : row,
    );
  }

  Widget _buildCupertinoDivider(bool isDark) {
    return Container(
      height: 0.5,
      color: context.palette.border,
    );
  }

  Widget _buildCupertinoSectionHeader(String title, Color color) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.5),
    );
  }

  // ==========================================
  // MATERIAL LAYOUT (WEB / ANDROID)
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
                                errorBuilder: (_, __, ___) => Container(
                                  height: 320,
                                  color: context.palette.textMuted.withOpacity(0.2),
                                  child: const Icon(Icons.photo, size: 64),
                                ),
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
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildAboutSection(event),
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
                                _buildRegistrationCTA(state, isIOS: false),
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
                      errorBuilder: (_, __, ___) => Container(
                        height: 180,
                        color: context.palette.textMuted.withOpacity(0.2),
                        child: const Icon(Icons.photo, size: 48),
                      ),
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
                if (!unpublished) _buildRegistrationCTA(state, isIOS: false),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildAboutSection(event),
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

  Widget _buildAboutSection(AppEvent event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About the Event',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.palette.primary),
        ),
        const SizedBox(height: 10),
        Text(
          event.description ?? 'No description provided for this event.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildCupertinoSponsorChips(AppEvent event, Color cardBg, Color textPrimary, Color textSecondary) {
    if (event.sponsors.isEmpty && event.partners.isEmpty) {
      return Text('Sponsor details will be updated soon.',
          style: TextStyle(color: textSecondary, fontSize: 13));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (event.sponsors.isNotEmpty) ...[
          Text('SPONSORS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: event.sponsors.map((sp) {
              return _buildCupertinoSponsorChip(sp.name, sp.sponsorTypeLabel, sp.logoUrl, sp.websiteUrl,
                  cardBg, textPrimary, textSecondary);
            }).toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (event.partners.isNotEmpty) ...[
          Text('PARTNERS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: event.partners.map((pt) {
              return _buildCupertinoSponsorChip(pt.name, pt.partnerTypeLabel, pt.logoUrl, pt.websiteUrl,
                  cardBg, textPrimary, textSecondary);
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildCupertinoSponsorChip(String name, String typeLabel, String? logoUrl, String? websiteUrl,
      Color cardBg, Color textPrimary, Color textSecondary) {
    final chipContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textSecondary.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl != null && logoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                logoUrl,
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(Icons.business, size: 16, color: context.palette.primary),
              ),
            )
          else
            Icon(Icons.business, size: 16, color: context.palette.primary),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: TextStyle(fontSize: 12, color: textPrimary, fontWeight: FontWeight.w500)),
              Text(typeLabel, style: TextStyle(fontSize: 9, color: textSecondary)),
            ],
          ),
        ],
      ),
    );

    if (websiteUrl != null && websiteUrl.isNotEmpty) {
      return GestureDetector(
        onTap: () => _launchUrl(websiteUrl),
        child: chipContent,
      );
    }
    return chipContent;
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
                errorBuilder: (_, __, ___) =>
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
    if (who == null && !isAdmin) return const SizedBox.shrink();
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
        ],
      ),
    );
    if (!isAdmin || !event.isVirtual || link.isEmpty) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [line, _organiserMeetingLink(link)],
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Meeting link copied')),
              );
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
    String rupees(double v) =>
        '₹${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}';
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
                Text(rupees(f.amount), style: rowStyle),
              ],
            ),
          ),
        Divider(height: 16, color: p.border),
        Row(
          children: [
            Expanded(child: Text('Total', style: rowStyle.copyWith(fontWeight: FontWeight.w600))),
            Text(rupees(total), style: rowStyle.copyWith(fontWeight: FontWeight.w600)),
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
      backgroundColor: accentColor.withOpacity(0.15),
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
        errorBuilder: (_, __, ___) => fallback,
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
  Widget _buildRegistrationCTA(EventDetailState state, {required bool isIOS}) {
    final event = state.event;
    if (event == null) return const SizedBox.shrink();

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
        dateValue: _formatDateTime(event.registrationClosesAt!),
        isIOS: isIOS,
      );
    } else if (event.registrationStatus != 'open' &&
        event.registrationOpensAt != null &&
        event.registrationOpensAt!.isAfter(now)) {
      countdownWidget = _buildCountdownSection(
        title: 'Registration opens in',
        countdown: _formatRemainingTime(event.registrationOpensAt!),
        dateLabel: 'Registration opening on',
        dateValue: _formatDateTime(event.registrationOpensAt!),
        isIOS: isIOS,
      );
    }

    final registrationStatus =
        state.myRegistration?['status']?.toString().toLowerCase();
    final hasActiveRegistration = registrationStatus == 'registered';
    final hasCancelledRegistration = registrationStatus == 'cancelled';
    // After a cancellation the backend lets the attendee register again. The
    // Register button comes back only when the backend says so.
    final canRegisterAgain = hasCancelledRegistration &&
        state.eligibilityStatus == 'eligible' &&
        !isPastEvent;

    // Once it's over there is nothing to register for: just say it ended.
    final isRegistered =
        hasActiveRegistration || state.eligibilityStatus == 'already_registered';
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
          _buildQRBadgeSection(state, event, isIOS),
        ],
      );
    } else if (state.eligibilityStatus == 'already_registered') {
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
          _buildQRBadgeSection(state, event, isIOS),
        ],
      );
    } else if (state.eligibilityStatus == 'full') {
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
    } else if (state.eligibilityStatus == 'closed') {
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
    } else if (state.eligibilityStatus == 'not_open_yet') {
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
    } else if (state.eligibilityStatus == 'ineligible') {
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
      if (isIOS) {
        ctaWidget = SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: context.palette.primary,
            onPressed: () => _showRegistrationForm(event, state, isIOS: true),
            child: Text('Register', style: TextStyle(fontWeight: FontWeight.bold, color: context.palette.onPrimary)),
          ),
        );
      } else {
        ctaWidget = SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.palette.primary,
              foregroundColor: context.palette.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _showRegistrationForm(event, state, isIOS: false),
            child: const Text('Register', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      }
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

  void _showRegistrationForm(AppEvent event, EventDetailState state, {required bool isIOS}) {
    final auth = ref.read(authControllerProvider);
    _notesController.clear();
    _emailController.text = state.alumniProfile?['email'] ?? auth.session?.email ?? '';
    _phoneController.text = state.alumniProfile?['phone'] ?? '';

    if (isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (context) {
          final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
          final bg = context.palette.surface;
          final barBg = context.palette.background;
          final textPrimary = context.palette.textPrimary;

          return Material(
            color: Colors.transparent,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: barBg,
                      border: Border(bottom: BorderSide(color: context.palette.border, width: 0.5)),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.left_chevron, size: 18, color: context.palette.primary),
                              SizedBox(width: 4),
                              Text('Back', style: TextStyle(color: context.palette.primary, fontSize: 15)),
                            ],
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(width: 60),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEventHeader(event, isDark),
                          _buildReadOnlyField('Badge name', state.alumniProfile?['fullname'] ?? auth.session?.fullname ?? '', isDark),
                          _buildEditableField('Email', _emailController, 'your@email.com', isDark),
                          _buildEditableField('Phone', _phoneController, 'Phone number', isDark),
                          _buildEditableField('Notes (optional)', _notesController, 'Dietary preferences, accessibility needs…', isDark),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              color: context.palette.primary,
                              onPressed: () {
                                Navigator.pop(context);
                                _proceedToCheckout(event);
                              },
                              child: Text('Proceed to Checkout', style: TextStyle(fontWeight: FontWeight.bold, color: context.palette.onPrimary)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoBox(isDark),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      showDialog(
        context: context,
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Dialog(
            backgroundColor: context.palette.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Register for Event',
                          style: TextStyle(fontFamily: AppTextStyles.serif, fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildEventHeader(event, isDark),
                    _buildReadOnlyField('Badge name', state.alumniProfile?['fullname'] ?? auth.session?.fullname ?? '', isDark),
                    _buildEditableField('Email', _emailController, 'your@email.com', isDark),
                    _buildEditableField('Phone', _phoneController, 'Phone number', isDark),
                    _buildEditableField('Notes (optional)', _notesController, 'Dietary preferences, accessibility needs…', isDark),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.palette.primary,
                          foregroundColor: context.palette.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _proceedToCheckout(event);
                        },
                        child: const Text('Proceed to Checkout', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoBox(isDark),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildReadOnlyField(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: context.palette.surfaceSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.palette.border,
              ),
            ),
            child: Text(
              value.isNotEmpty ? value : '—',
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller, String hint, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            style: TextStyle(fontSize: 14, color: context.palette.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: context.palette.textMuted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true,
              fillColor: context.palette.surfaceSubtle,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.palette.border,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.palette.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: context.palette.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
              "You'll receive a confirmation email. Your QR badge will appear in My Events.",
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

  /// Navigates to the checkout screen with the notes.
  void _proceedToCheckout(AppEvent event) {
    final notes = Uri.encodeComponent(_notesController.text);
    context.push('/events/${event.eventId}/checkout?notes=$notes');
  }

  Future<void> _submitRegistration() async {
    final success = await ref
        .read(eventDetailProvider(widget.eventId).notifier)
        .register(widget.eventId, _notesController.text);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registration confirmed successfully!')),
        );
      } else {
        final state = ref.read(eventDetailProvider(widget.eventId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration failed: ${state.errorMessage ?? 'Unknown error'}')),
        );
      }
    }
  }

  // ==========================================
  // HELPER FORMATTERS
  // ==========================================
  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime start, DateTime? end) {
    String formatSingle(DateTime dt) {
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $period';
    }

    if (end == null) {
      return formatSingle(start);
    }
    return '${formatSingle(start)} – ${formatSingle(end)}';
  }

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
      return _formatDate(start);
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final days = DateTime(last.year, last.month, last.day)
            .difference(DateTime(start.year, start.month, start.day))
            .inDays +
        1;
    final String range;
    if (start.year != last.year) {
      range = '${_formatDate(start)} – ${_formatDate(last)}';
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
    if (end == null) return _formatTime(start, null);
    final sameDay = end.year == start.year && end.month == start.month && end.day == start.day;
    if (sameDay) return _formatTime(start, end);
    return 'Starts ${_formatTime(start, null)}, ends ${_formatTime(end, null)}';
  }

  String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)} at ${_formatTime(dt, null)}';
  }

  String _formatSessionTime(EventSession session) {
    return _formatTime(session.startDatetime, session.endDatetime);
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
      final amountText = price == price.roundToDouble()
          ? price.toInt().toString()
          : price.toStringAsFixed(2);
      return 'Event Fee: ₹$amountText';
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
    required bool isIOS,
  }) {
    final cardBg = context.palette.surfaceSubtle;
    final borderColor = context.palette.primary.withOpacity(0.3);
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

  Widget _buildQRBadgeSection(EventDetailState state, AppEvent event, bool isIOS) {
    final infoBg = context.palette.info.withValues(alpha: 0.08);
    final infoTextColor = context.palette.textSecondary;
    final regNo = state.myRegistration?['registration_number'] ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 340;

        final viewButton = isIOS
            ? CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: context.palette.primary,
                borderRadius: BorderRadius.circular(10),
                onPressed: () => _showQRBadgeDialog(event, regNo, state),
                child: Text(
                  'View QR badge',
                  style: TextStyle(
                    color: context.palette.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            : ElevatedButton(
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

        final eventsButton = isIOS
            ? CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                onPressed: () {
                  context.go(AppRoutes.home);
                },
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: context.palette.textMuted,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Go to My Events',
                    style: TextStyle(
                      color: context.palette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            : OutlinedButton(
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

  void _showQRBadgeDialog(AppEvent event, String regNo, EventDetailState state) {
    final auth = ref.read(authControllerProvider);
    final userName = state.alumniProfile?['fullname'] ?? auth.session?.fullname ?? 'Attendee';
    final email = state.alumniProfile?['email'] ?? auth.session?.email ?? '';

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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(regNo.isNotEmpty ? regNo : "Event-${event.eventId}")}',
                          width: 200,
                          height: 200,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              width: 200,
                              height: 200,
                              color: Colors.white,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 200,
                              height: 200,
                              color: Colors.white,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code, size: 80, color: Colors.black),
                                  SizedBox(height: 8),
                                  Text(
                                    'QR Code Offline',
                                    style: TextStyle(color: Colors.black, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
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