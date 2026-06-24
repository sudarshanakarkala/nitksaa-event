import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';
import '../domain/alumni_profile.dart';
import '../services/registration_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  final int eventId;
  final String eventTitle;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final RegistrationService _service = RegistrationService();
  final TextEditingController _noteController = TextEditingController();

  bool _profileLoading = true;
  AlumniProfile? _profile;
  String? _profileError;

  bool _registering = false;
  String? _registerError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await _service.getAlumniProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _profileLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _profileError = registrationErrorMessage(error);
      });
    }
  }

  Future<void> _register() async {
    setState(() {
      _registering = true;
      _registerError = null;
    });
    try {
      final note = _noteController.text.trim();
      final registration = await _service.registerForEvent(
        widget.eventId,
        attendeeNote: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      context.pushReplacement(
        AppRoutes.registrationConfirmation,
        extra: registration,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _registering = false;
        _registerError = registrationErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Register',
      maxContentWidth: 720,
      padding: const EdgeInsets.all(24),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_profileLoading) {
      return const AppLoadingView(
        title: 'Loading your profile',
        message: 'Fetching your alumni record.',
        icon: Icons.person_outline,
      );
    }

    if (_profileError != null) {
      return AppErrorView(
        title: 'Unable to load profile',
        message: _profileError!,
        action: AppPrimaryButton(
          label: 'Retry',
          icon: Icons.refresh_outlined,
          onPressed: _loadProfile,
        ),
      );
    }

    final profile = _profile!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EventTitleCard(title: widget.eventTitle),
          const SizedBox(height: 16),
          _ProfileCard(profile: profile),
          const SizedBox(height: 16),
          _NoteCard(controller: _noteController),
          const SizedBox(height: 8),
          if (_registerError != null)
            _ErrorCard(message: _registerError!),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: _registering ? 'Registering…' : 'Confirm Registration',
            icon: Icons.how_to_reg_outlined,
            onPressed: _registering ? null : _register,
          ),
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: 'Cancel',
            icon: Icons.close,
            onPressed: _registering ? null : () => context.pop(),
          ),
        ],
      ),
    );
  }
}

class _EventTitleCard extends StatelessWidget {
  const _EventTitleCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.event_outlined, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registering for',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final AlumniProfile profile;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your Alumni Profile',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: profile.isActive
                      ? Colors.green.withValues(alpha: 0.12)
                      : Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  profile.isActive ? 'Active' : 'Inactive',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: profile.isActive
                            ? Colors.green.shade800
                            : Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'This information will be recorded with your registration.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          _ProfileRow(label: 'Name', value: profile.fullname),
          _ProfileRow(label: 'Email', value: profile.email),
          if (profile.phone != null)
            _ProfileRow(label: 'Phone', value: profile.phone!),
          if (profile.batchYear != null)
            _ProfileRow(
                label: 'Batch Year', value: profile.batchYear.toString()),
          if (profile.branch != null)
            _ProfileRow(label: 'Branch', value: profile.branch!, isLast: true),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendee Note (optional)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Any dietary requirements, accessibility needs, or special requests.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'e.g. Vegetarian meal, wheelchair access needed…',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: cs.onErrorContainer, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
