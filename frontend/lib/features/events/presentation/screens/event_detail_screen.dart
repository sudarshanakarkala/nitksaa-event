import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../providers/event_detail_provider.dart';
import '../../domain/event.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
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
    final isAdmin = auth.session?.userType.toLowerCase() == 'admin';

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
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Failed to load event details:\n${state.errorMessage}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref
                      .read(eventDetailProvider(widget.eventId).notifier)
                      .fetchEventDetails(widget.eventId),
                  child: const Text('Retry'),
                ),
              ],
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
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final cardBg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
    final textPrimary = isDark ? Colors.white : Colors.black;
    final textSecondary = isDark ? const Color(0xFFEBEBF5) : const Color(0xFF3C3C43);
    final accentGold = const Color(0xFFC9952A);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.left_chevron, size: 20, color: Color(0xFFC9952A)),
              Text('Back', style: TextStyle(color: Color(0xFFC9952A))),
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
                            color: Colors.grey.withOpacity(0.2),
                            child: const Icon(CupertinoIcons.photo, size: 48),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      event.title,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textPrimary),
                    ),
                    if (event.tagline != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.tagline!,
                        style: TextStyle(fontSize: 14, color: textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildCupertinoMetaRow(CupertinoIcons.calendar, _formatDate(event.startDatetime), textSecondary),
                    _buildCupertinoMetaRow(CupertinoIcons.clock, _formatTime(event.startDatetime, event.endDatetime), textSecondary),
                    _buildCupertinoMetaRow(
                      event.isVirtual ? CupertinoIcons.videocam : CupertinoIcons.location,
                      event.locationText ?? (event.isVirtual ? 'Virtual Zoom Link' : 'To Be Decided'),
                      textSecondary,
                      onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
                          ? () => _launchUrl(event.locationMapsUrl!)
                          : null,
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
                            backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
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
        color: onTap != null ? const Color(0xFFC9952A) : color,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFC9952A)),
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
      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
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
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final appBar = AppBar(
      title: Text(event.title),
      backgroundColor: isDark ? const Color(0xFF0D1B3E) : Colors.white,
      foregroundColor: isDark ? Colors.white : const Color(0xFF0D1B3E),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
      ),
    );

    if (isWebScreen) {
      return Scaffold(
        appBar: appBar,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                                color: Colors.grey.withOpacity(0.2),
                                child: const Icon(Icons.photo, size: 64),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0D1B3E),
                              ),
                        ),
                        if (event.tagline != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            event.tagline!,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildMaterialMetaGrid(event),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        _buildAboutSection(event),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        _buildSponsorsSection(event, isDark),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        _buildAgendaSection(event),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        _buildSpeakersSection(event),
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
                    color: isDark ? const Color(0xFF131E30) : Colors.white,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Registration',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
                            ),
                            const SizedBox(height: 12),
                            if (isAdmin) _buildCapacityBar(event, isDark),
                            const SizedBox(height: 16),
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
        ),
      );
    } else {
      // Android / Mobile Material Layout
      return Scaffold(
        appBar: appBar,
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      color: Colors.grey.withOpacity(0.2),
                      child: const Icon(Icons.photo, size: 48),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                event.title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              if (event.tagline != null) ...[
                const SizedBox(height: 4),
                Text(
                  event.tagline!,
                  style: const TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 16),
              _buildMaterialMetaRow(Icons.calendar_today, _formatDate(event.startDatetime)),
              _buildMaterialMetaRow(Icons.access_time, _formatTime(event.startDatetime, event.endDatetime)),
              _buildMaterialMetaRow(
                event.isVirtual ? Icons.videocam : Icons.location_on,
                event.locationText ?? (event.isVirtual ? 'Virtual Link' : 'To Be Decided'),
                onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
                    ? () => _launchUrl(event.locationMapsUrl!)
                    : null,
              ),
              const SizedBox(height: 16),
              const Divider(),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                _buildCapacityBar(event, isDark),
                const SizedBox(height: 16),
              ],
              _buildRegistrationCTA(state, isIOS: false),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildAboutSection(event),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildSponsorsSection(event, isDark),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildAgendaSection(event),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildSpeakersSection(event),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMaterialMetaRow(IconData icon, String text, {VoidCallback? onTap}) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: onTap != null ? const Color(0xFFC9952A) : null,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFC9952A)),
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
        _buildMetaGridItem(Icons.calendar_today, _formatDate(event.startDatetime)),
        _buildMetaGridItem(Icons.access_time, _formatTime(event.startDatetime, event.endDatetime)),
        _buildMetaGridItem(
          event.isVirtual ? Icons.videocam : Icons.location_on,
          event.locationText ?? (event.isVirtual ? 'Virtual Link' : 'To Be Decided'),
          onTap: (event.locationMapsUrl != null && event.locationMapsUrl!.isNotEmpty)
              ? () => _launchUrl(event.locationMapsUrl!)
              : null,
        ),
      ],
    );
  }

  Widget _buildMetaGridItem(IconData icon, String text, {VoidCallback? onTap}) {
    final textWidget = Text(
      text,
      style: TextStyle(
        fontSize: 14,
        color: onTap != null ? const Color(0xFFC9952A) : null,
        decoration: onTap != null ? TextDecoration.underline : null,
      ),
    );

    final row = Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFC9952A)),
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
        const Text(
          'About the Event',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
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
                errorBuilder: (_, __, ___) => Icon(Icons.business, size: 16, color: const Color(0xFFC9952A)),
              ),
            )
          else
            Icon(Icons.business, size: 16, color: const Color(0xFFC9952A)),
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
          const Text(
            'Sponsors',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
          ),
          const SizedBox(height: 12),
          const Text('Sponsor details will be updated soon.',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sponsors',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
        ),
        const SizedBox(height: 12),
        if (event.sponsors.isNotEmpty) ...[
          Text('SPONSORS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          _buildSponsorGrid(event.sponsors, isDark, isSponsor: true),
          const SizedBox(height: 16),
        ],
        if (event.partners.isNotEmpty) ...[
          Text('PARTNERS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
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
    final bg = isDark ? const Color(0xFF1C2A40) : const Color(0xFFEEF3FA);
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
                    Icon(Icons.business, size: 22, color: const Color(0xFFC9952A)),
              ),
            )
          else
            Icon(Icons.business, size: 22, color: const Color(0xFFC9952A)),
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
                        ? const Color(0xFFC9952A)
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
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
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

  Widget _buildAgendaSection(AppEvent event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Agenda',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
        ),
        const SizedBox(height: 12),
        if (event.sessions.isEmpty)
          const Text('Agenda will be updated soon.', style: TextStyle(fontSize: 14, color: Colors.grey))
        else
          ...event.sessions.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatSessionTime(item),
                  style: const TextStyle(color: Color(0xFFC9952A), fontWeight: FontWeight.bold, fontSize: 13),
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
        const Text(
          'Speakers',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFC9952A)),
        ),
        const SizedBox(height: 12),
        if (event.speakers.isEmpty)
          const Text('Speaker details will be updated soon.', style: TextStyle(fontSize: 14, color: Colors.grey))
        else
          ...event.speakers.map((sp) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              children: [
                _buildSpeakerAvatar(
                  sp,
                  radius: 20,
                  accentColor: const Color(0xFFC9952A),
                  initialsStyle: const TextStyle(color: Color(0xFFC9952A), fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sp.fullname, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(sp.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
            backgroundColor: isDark ? const Color(0xFF1C2A40) : const Color(0xFFEEF3FA),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC9952A)),
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

    Widget? countdownWidget;
    if (event.registrationStatus == 'open' && event.registrationClosesAt != null) {
      countdownWidget = _buildCountdownSection(
        title: 'Registration closes in',
        countdown: _formatRemainingTime(event.registrationClosesAt!),
        dateLabel: 'Last date to register',
        dateValue: _formatDateTime(event.registrationClosesAt!),
        isIOS: isIOS,
      );
    } else if (event.registrationStatus != 'open' && event.registrationOpensAt != null) {
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
    final isPastEvent = event.endDatetime != null
        ? event.endDatetime!.isBefore(DateTime.now())
        : event.startDatetime.isBefore(DateTime.now());

    Widget ctaWidget;
    if (hasCancelledRegistration) {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF8A1B1B).withOpacity(0.2)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel, color: Color(0xFF8A1B1B), size: 20),
            SizedBox(width: 8),
            Text(
              'Unregistered from this event',
              style: TextStyle(
                color: Color(0xFF8A1B1B),
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
              color: const Color(0xFFD9F4E8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1B5C3A).withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF1B5C3A), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Registered Successfully',
                      style: TextStyle(color: Color(0xFF1B5C3A), fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (regNo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Badge #: $regNo',
                    style: const TextStyle(color: Color(0xFF1B5C3A), fontSize: 12),
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
              color: const Color(0xFFDDEEFF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'You are registered for this event.',
                style: TextStyle(color: Color(0xFF1B5C9B), fontWeight: FontWeight.bold),
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
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Event is at full capacity.',
            style: TextStyle(color: Color(0xFF8A1B1B), fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (state.eligibilityStatus == 'closed') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Registration is closed.',
            style: TextStyle(color: Color(0xFF8A1B1B), fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (state.eligibilityStatus == 'not_open_yet') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Registration is not open yet.',
            style: TextStyle(color: Color(0xFF8A1B1B), fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (state.eligibilityStatus == 'ineligible') {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            state.eligibilityMessage ?? 'Ineligible to register.',
            style: const TextStyle(color: Color(0xFF8A1B1B), fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else if (isPastEvent) {
      ctaWidget = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text(
            'Registration is unavailable for past events.',
            style: TextStyle(color: Color(0xFF8A1B1B), fontWeight: FontWeight.bold),
          ),
        ),
      );
    } else {
      // Default eligible: show Register button
      if (isIOS) {
        ctaWidget = SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: const Color(0xFFC9952A),
            onPressed: () => _showRegistrationForm(event, state, isIOS: true),
            child: const Text('Register', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        );
      } else {
        ctaWidget = SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D1B3E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => _showRegistrationForm(event, state, isIOS: false),
            child: const Text('Register', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      }
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
    _notesController.clear();
    final auth = ref.read(authControllerProvider);

    if (isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (context) {
          final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
          final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
          final barBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
          final textPrimary = isDark ? Colors.white : Colors.black;

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
                      border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 0.5)),
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(CupertinoIcons.left_chevron, size: 18, color: Color(0xFFC9952A)),
                              SizedBox(width: 4),
                              Text('Back', style: TextStyle(color: Color(0xFFC9952A), fontSize: 15)),
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
                          _buildReadOnlyField('Email', state.alumniProfile?['email'] ?? auth.session?.email ?? '', isDark),
                          _buildReadOnlyField('Phone', state.alumniProfile?['phone'] ?? '', isDark),
                          _buildEditableField('Notes (optional)', _notesController, 'Dietary preferences, accessibility needs…', isDark),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoButton(
                              color: const Color(0xFFC9952A),
                              onPressed: () async {
                                Navigator.pop(context);
                                await _submitRegistration();
                              },
                              child: const Text('Confirm registration', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
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
            backgroundColor: isDark ? const Color(0xFF131E30) : Colors.white,
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
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                    _buildReadOnlyField('Email', state.alumniProfile?['email'] ?? auth.session?.email ?? '', isDark),
                    _buildReadOnlyField('Phone', state.alumniProfile?['phone'] ?? '', isDark),
                    _buildEditableField('Notes (optional)', _notesController, 'Dietary preferences, accessibility needs…', isDark),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D1B3E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          await _submitRegistration();
                        },
                        child: const Text('Confirm registration', style: TextStyle(fontWeight: FontWeight.bold)),
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
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Text(
              value.isNotEmpty ? value : '—',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.black87,
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
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFC9952A),
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
    final infoBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF3FA);
    final infoText = isDark ? const Color(0xFF8B9AB8) : const Color(0xFF5A6A8A);
    
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
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0D1B3E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_formatDate(event.startDatetime)} · ${_formatTime(event.startDatetime, event.endDatetime)}',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 16),
      ],
    );
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

  Widget _buildCountdownSection({
    required String title,
    required String countdown,
    required String dateLabel,
    required String dateValue,
    required bool isIOS,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = const Color(0xFFC9952A).withOpacity(0.3);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC9952A),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF3FA);
    final infoTextColor = isDark ? const Color(0xFF8B9AB8) : const Color(0xFF5A6A8A);
    final regNo = state.myRegistration?['registration_number'] ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 340;

        final viewButton = isIOS
            ? CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFF0D1B3E),
                borderRadius: BorderRadius.circular(10),
                onPressed: () => _showQRBadgeDialog(event, regNo, state),
                child: const Text(
                  'View QR badge',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              )
            : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D1B3E),
                  foregroundColor: Colors.white,
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
                      color: isDark ? Colors.white30 : Colors.black26,
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Go to My Events',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0D1B3E),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            : OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF0D1B3E),
                  side: BorderSide(
                    color: isDark ? Colors.white30 : Colors.black26,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = ref.read(authControllerProvider);
    final userName = state.alumniProfile?['fullname'] ?? auth.session?.fullname ?? 'Attendee';
    final email = state.alumniProfile?['email'] ?? auth.session?.email ?? '';

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: isDark ? const Color(0xFF131E30) : Colors.white,
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    color: isDark ? const Color(0xFF0D1B3E) : const Color(0xFFF4F6F9),
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
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54),
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