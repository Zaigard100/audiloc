import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../l10n/l10n.dart';
import '../../services/sync/pairing/pairing_models.dart';
import '../devices/devices_screen.dart';
import '../devices/providers/devices_providers.dart';
import '../library/library_screen.dart';
import '../player/mini_player.dart';
import '../player/providers/player_providers.dart';
import '../player/widgets/resume_playback_prompt.dart';
import '../playlists/playlists_screen.dart';
import '../search/search_screen.dart';
import 'widgets/share_offer_dialog.dart';

const _tabs = ['library', 'playlists', 'search', 'devices'];

/// Bottom-tab shell (ТЗ п.6.2): Библиотека / Плейлисты / Поиск / Устройства,
/// with the mini-player pinned above the tab bar so it's always reachable.
/// Swiping left/right switches tabs too, not just tapping the bar — a
/// `PageView` (not `.builder`, so every tab stays built and keeps its
/// state exactly like the `IndexedStack` it replaced) driven by the same
/// `tab` route param, kept in sync in both directions: tapping the bar
/// animates the page, swiping the page updates the route (and so the
/// bar's selection) via [_onPageChanged].
///
/// Also owns the incoming-pairing-request dialog (ТЗ +
/// docs/adr/0011-mutual-pairing-confirmation.md) and the incoming
/// "Поделиться" offer dialog (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md)
/// — both need to show up no matter which tab the user is on.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.tab});

  final String tab;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final PageController _pageController;

  int get _index => _tabs.indexOf(widget.tab).clamp(0, _tabs.length - 1);

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
    // `listenManual` (not `ref.listen` in build) specifically so
    // `fireImmediately` is available — a state already sitting in the DB
    // when this profile session opens (this device's own last session, or
    // synced in before this device ever opened the app) needs to be
    // restored too, not just live updates that arrive after this
    // subscription already exists. See docs/adr/0029-playback-state-sync.md.
    ref.listenManual(playbackStateProvider, (previous, next) {
      final state = next.value;
      if (state != null) handleIncomingPlaybackState(context, ref, state);
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The bar (or anything else navigating via go_router) changed the
    // route's tab — animate the page to match, unless we're already
    // there (e.g. because *this* update was itself triggered by
    // [_onPageChanged] reacting to a swipe that just finished).
    final target = _index;
    if (_pageController.hasClients && _pageController.page?.round() != target) {
      _pageController.animateToPage(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (index != _index) context.go('/${_tabs[index]}');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingPairingRequestsProvider, (previous, next) {
      final request = next.value;
      if (request != null) _showPairingRequestDialog(context, ref, request);
    });
    ref.listen(incomingShareOffersProvider, (previous, next) {
      final offer = next.value;
      if (offer != null) showShareOfferDialog(context, ref, offer);
    });
    final l10n = context.l10n;

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: const [
          LibraryScreen(),
          PlaylistsScreen(),
          SearchScreen(),
          DevicesScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => context.go('/${_tabs[i]}'),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.library_music_outlined),
                selectedIcon: const Icon(Icons.library_music),
                label: l10n.navLibrary,
              ),
              NavigationDestination(
                icon: const Icon(Icons.queue_music_outlined),
                selectedIcon: const Icon(Icons.queue_music),
                label: l10n.navPlaylists,
              ),
              NavigationDestination(icon: const Icon(Icons.search), label: l10n.navSearch),
              NavigationDestination(
                icon: const Icon(Icons.devices_outlined),
                selectedIcon: const Icon(Icons.devices),
                label: l10n.navDevices,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPairingRequestDialog(BuildContext context, WidgetRef ref, IncomingPairingRequest request) {
    // A mismatched-hash request only ever reaches this dialog at all
    // while this device is a placeholder waiting via "Ждать сопряжения"
    // (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md) — any
    // other cross-profile request is auto-declined before the user ever
    // sees it. Same profile already (re-pairing a lost device) — no
    // switch is about to happen, keep the message simple. Different —
    // approving switches this device onto the requester's profile; say
    // so plainly.
    final sameProfile = ref.read(currentProfileProvider).profileHash == request.profileHash;
    final l10n = context.l10n;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.pairingRequestTitle),
        content: Text(
          sameProfile
              ? l10n.pairingRequestSameProfile(request.fromName)
              : l10n.pairingRequestDifferentProfile(request.fromName),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(pairingServiceProvider).reject(request);
              Navigator.of(context).pop();
            },
            child: Text(l10n.commonDecline),
          ),
          TextButton(
            onPressed: () {
              ref.read(pairingServiceProvider).approve(request);
              Navigator.of(context).pop();
            },
            child: Text(l10n.commonAllow),
          ),
        ],
      ),
    );
  }
}
