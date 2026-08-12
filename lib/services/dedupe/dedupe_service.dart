import '../../data/models/track.dart';

/// Decides whether two tracks are "the same song".
///
/// ТЗ п.3 flags this as the one job with no ready-made Flutter package:
/// real audio fingerprinting needs an FFI binding to libchromaprint that
/// doesn't exist yet for Dart. [HeuristicDuplicateDetector] is the
/// grubaya-эвристика ТЗ suggests as the MVP fallback (п.3, п.8 Этап 4). A
/// future chromaprint-backed detector is a drop-in: implement this
/// interface and swap it into [DedupeService] — nothing else changes.
abstract class DuplicateDetector {
  bool isDuplicate(Track candidate, Track existing);
}

/// Matches on normalized title + duration proximity. Deliberately coarse:
/// false negatives (missed duplicates) are safer than false positives
/// (silently refusing to import a legitimately different track).
class HeuristicDuplicateDetector implements DuplicateDetector {
  HeuristicDuplicateDetector({this.durationToleranceMs = 1500});

  final int durationToleranceMs;

  @override
  bool isDuplicate(Track candidate, Track existing) {
    if (candidate.id == existing.id) return true;
    if (_normalize(candidate.displayTitle) != _normalize(existing.displayTitle)) {
      return false;
    }
    final candidateDuration = candidate.durationMs;
    final existingDuration = existing.durationMs;
    if (candidateDuration == null || existingDuration == null) {
      // No duration on one side: title match alone is too weak.
      return false;
    }
    return (candidateDuration - existingDuration).abs() <= durationToleranceMs;
  }

  String _normalize(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

class DedupeService {
  DedupeService({DuplicateDetector? detector})
      : _detector = detector ?? HeuristicDuplicateDetector();

  final DuplicateDetector _detector;

  /// Returns the first track in [existing] that looks like the same song
  /// as [candidate], or null if none matches.
  Track? findDuplicate(Track candidate, Iterable<Track> existing) {
    for (final track in existing) {
      if (_detector.isDuplicate(candidate, track)) return track;
    }
    return null;
  }
}
