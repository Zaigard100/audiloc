import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/services/dedupe/dedupe_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final existing = [
    const Track(id: 'a', path: '/a.mp3', title: 'Bohemian Rhapsody', durationMs: 355000),
    const Track(id: 'b', path: '/b.mp3', title: 'Another One Bites the Dust', durationMs: 215000),
  ];

  group('HeuristicDuplicateDetector', () {
    final detector = HeuristicDuplicateDetector();

    test('same title and close duration is a duplicate', () {
      const candidate = Track(id: 'c', path: '/c.mp3', title: 'Bohemian Rhapsody', durationMs: 355800);
      expect(detector.isDuplicate(candidate, existing[0]), isTrue);
    });

    test('same title but far-apart duration is not a duplicate (e.g. live vs. studio cut)', () {
      const candidate = Track(id: 'c', path: '/c.mp3', title: 'Bohemian Rhapsody', durationMs: 480000);
      expect(detector.isDuplicate(candidate, existing[0]), isFalse);
    });

    test('different title is never a duplicate regardless of duration', () {
      const candidate = Track(id: 'c', path: '/c.mp3', title: 'Another One Bites the Dust', durationMs: 355000);
      expect(detector.isDuplicate(candidate, existing[0]), isFalse);
    });

    test('title match is case- and whitespace-insensitive', () {
      const candidate =
          Track(id: 'c', path: '/c.mp3', title: '  bohemian   rhapsody  ', durationMs: 355000);
      expect(detector.isDuplicate(candidate, existing[0]), isTrue);
    });

    test('missing duration on either side is too weak a signal alone', () {
      const candidateNoDuration = Track(id: 'c', path: '/c.mp3', title: 'Bohemian Rhapsody');
      expect(detector.isDuplicate(candidateNoDuration, existing[0]), isFalse);
    });

    test('identical id is always a duplicate (same file content)', () {
      const candidate = Track(id: 'a', path: '/different/path.mp3', title: 'Whatever');
      expect(detector.isDuplicate(candidate, existing[0]), isTrue);
    });
  });

  group('DedupeService', () {
    test('findDuplicate returns the matching existing track', () {
      final service = DedupeService();
      const candidate = Track(id: 'c', path: '/c.mp3', title: 'Bohemian Rhapsody', durationMs: 355000);
      expect(service.findDuplicate(candidate, existing)?.id, 'a');
    });

    test('findDuplicate returns null when nothing matches', () {
      final service = DedupeService();
      const candidate = Track(id: 'c', path: '/c.mp3', title: 'Stairway to Heaven', durationMs: 482000);
      expect(service.findDuplicate(candidate, existing), isNull);
    });
  });
}
