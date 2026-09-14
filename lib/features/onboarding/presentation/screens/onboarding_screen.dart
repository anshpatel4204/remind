import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../data/repositories/app_repositories.dart';

/// First-launch, skippable, 3-page walkthrough (Part 13): what REmind is,
/// that it's fully offline/local, and a couple of quick preferences - in
/// that order, matching the spec's "explain REmind / explain
/// offline-first storage / configure basic preferences" requirement.
///
/// Reached only from [AppBootGate] (`main.dart`), and only when
/// `SettingsRepository.getOnboardingCompleted()` is still false - a
/// returning user never sees this again. [onDone] is called once, after
/// [SettingsRepository.setOnboardingCompleted] has been persisted,
/// whether the user finished normally or tapped Skip - both mean "don't
/// show this again", so both are treated identically here.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen(
      {super.key, required this.repositories, required this.onDone});

  final AppRepositories repositories;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 3;

  final _pageController = PageController();
  final _nameController = TextEditingController();
  late final ThemeController _themeController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Onboarding runs before RemindApp (and its ThemeControllerScope)
    // exist, but "pick a theme" is still one of this screen's own pages -
    // so it owns a small ThemeController of its own, backed by the same
    // persisted setting RemindApp's own controller reads on the very next
    // screen. Nothing about this duplicates state: both controllers read
    // and write the identical `theme_mode` key.
    _themeController = ThemeController(widget.repositories.settingsRepository);
    _themeController.load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.repositories.settingsRepository
        .setDisplayName(_nameController.text);
    await widget.repositories.settingsRepository.setOnboardingCompleted(true);
    widget.onDone();
  }

  void _next() {
    if (_page == _pageCount - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _page = index),
                children: [
                  const _OnboardingPage(
                    icon: Icons.check_circle_outline,
                    headline: 'Never Miss What Matters',
                    description:
                        'Set reminders, organize your tasks, and achieve your goals.',
                  ),
                  const _OnboardingPage(
                    icon: Icons.lock_outline,
                    headline: 'Everything Stays With You',
                    description:
                        'REmind works fully offline. Your tasks, reminders, and data stay '
                        'private on this device - nothing is ever uploaded anywhere.',
                  ),
                  _PreferencesPage(
                    nameController: _nameController,
                    themeController: _themeController,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.brandPurple
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_page == _pageCount - 1 ? 'Get Started' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One explanatory onboarding page: an icon composition standing in for
/// the design reference's illustration (REmind has no bundled
/// illustration asset for this - see this part's final report), a
/// headline, and a short description.
class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.headline,
    required this.description,
  });

  final IconData icon;
  final String headline;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.brandPurple, AppColors.brandBlue],
              ),
            ),
            child: Icon(icon, size: 72, color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Onboarding's third page: the "configure basic preferences" step the
/// spec asks for, kept deliberately short - just a theme choice and an
/// optional name, both skippable/changeable later from Settings.
class _PreferencesPage extends StatelessWidget {
  const _PreferencesPage({
    required this.nameController,
    required this.themeController,
  });

  final TextEditingController nameController;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'Make REmind Yours',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Both of these are optional and can always be changed later in Settings.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          TextField(
            controller: nameController,
            key: const Key('onboardingNameField'),
            decoration: const InputDecoration(
              labelText: 'Your name (optional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Appearance', style: Theme.of(context).textTheme.labelLarge),
          ListenableBuilder(
            listenable: themeController,
            builder: (context, _) {
              return RadioGroup<ThemeMode>(
                groupValue: themeController.mode,
                onChanged: (mode) =>
                    mode == null ? null : themeController.setMode(mode),
                child: const Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: Text('System default'),
                      value: ThemeMode.system,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Light'),
                      value: ThemeMode.light,
                    ),
                    RadioListTile<ThemeMode>(
                      title: Text('Dark'),
                      value: ThemeMode.dark,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
