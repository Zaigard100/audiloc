/// Settings tab under Настройки → "Воспроизведение" — see
/// docs/adr/0029-playback-state-sync.md. Device-level (like theme/
/// language), not per-profile: how you like to control playback isn't
/// something that should reset when a housemate switches profiles.
class PlaybackShortcutsSettings {
  const PlaybackShortcutsSettings({this.enabled = true, this.seekStepSeconds = 10});

  final bool enabled;
  final int seekStepSeconds;

  static const seekStepChoices = [5, 10, 15, 30];

  PlaybackShortcutsSettings copyWith({bool? enabled, int? seekStepSeconds}) => PlaybackShortcutsSettings(
        enabled: enabled ?? this.enabled,
        seekStepSeconds: seekStepSeconds ?? this.seekStepSeconds,
      );
}
