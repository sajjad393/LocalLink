import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

/// Bundle 267: the Add Contact list shown while the search box is empty.
class PeoplePage267 {
  final List<DirectoryProfile> people;
  final bool more;

  /// Where the next server page starts (rows the server sent, before the
  /// phone took out its own contacts / blocked people).
  final int nextOffset;

  /// 'server' = everyone on the server who is not my contact;
  /// 'nearby' = people my nearby phones / friends shared (server not reached);
  /// 'none' = this repository can't make the list (tests / old fakes).
  final String source;

  const PeoplePage267({
    this.people = const <DirectoryProfile>[],
    this.more = false,
    this.nextOffset = 0,
    this.source = 'none',
  });
}

/// Extra interface (not in the old contract, so fakes keep working).
abstract class PeopleSource267 {
  Future<PeoplePage267> peopleToAdd267({int offset = 0});
}

abstract final class PeopleToAdd267 {
  static const String titleServer = 'People you can add';
  static const String titleNearby = 'People nearby phones know';
  static const String emptyServer = 'Everyone is already in your contacts.';
  static const String emptyNearby =
      'No one to show yet. Search a name or scan a QR code.';
  static const String waitLine = 'Please wait a few seconds';

  /// One page; never throws. Logs `ADD_LIST_267` (no names).
  static Future<PeoplePage267> load(Object repository, {int offset = 0}) async {
    if (repository is! PeopleSource267) return const PeoplePage267();
    final watch = Stopwatch()..start();
    PeoplePage267 page;
    try {
      page = await repository.peopleToAdd267(offset: offset);
    } catch (_) {
      page = const PeoplePage267(source: 'nearby');
    }
    AppLogger.info('ADD_LIST_267',
        detail: logLine(
            source: page.source,
            shown: page.people.length,
            more: page.more,
            offset: offset,
            ms: watch.elapsedMilliseconds));
    return page;
  }

  static String logLine({
    required String source,
    required int shown,
    required bool more,
    required int offset,
    required int ms,
  }) =>
      'src=$source shown=$shown more=${more ? 'y' : 'n'} from=$offset ms=$ms';
}
