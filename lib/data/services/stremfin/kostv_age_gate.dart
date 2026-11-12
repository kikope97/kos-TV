import 'package:flutter/foundation.dart';
import 'package:server_core/server_core.dart';

import '../../../util/parental_filter.dart';
import 'stremfin_models.dart';

/// Kos TV: how old the signed-in person has to be for what they see, as
/// their home server account says.
///
/// Jellyfin keeps it per user (Dashboard › Users › Parental control): a
/// maximum rating, which Jellyfin 10.10 counts in years like the requests
/// service does (0 for everyone, 7, 12, 16, 18), and the kinds of item it
/// hides while they carry no rating.
@immutable
class KostvAgeLimit {
  const KostvAgeLimit({this.maxAge, this.blockUnrated = const {}});

  /// Nothing limited.
  static const none = KostvAgeLimit();

  /// The oldest a title may be rated for, in years, or null for no limit.
  final int? maxAge;

  /// The kinds the account hides while they carry no rating.
  final Set<StremfinTitleType> blockUnrated;

  factory KostvAgeLimit.fromPolicy(UserPolicy? policy) {
    if (policy == null) return none;
    final blocked = policy.blockUnratedItems;
    return KostvAgeLimit(
      maxAge: policy.maxParentalRating,
      blockUnrated: {
        if (blocked.contains('Movie')) StremfinTitleType.movie,
        if (blocked.contains('Series')) StremfinTitleType.series,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is KostvAgeLimit &&
      other.maxAge == maxAge &&
      setEquals(other.blockUnrated, blockUnrated);

  @override
  int get hashCode =>
      Object.hash(maxAge, Object.hashAllUnordered(blockUnrated));
}

/// Kos TV: whether [title], from the requests service, may be shown to the
/// person. The service only says how old a title is for; the app decides.
///
/// Someone with any limit (their account's maximum rating, their account
/// hiding unrated titles of that kind, or this device's parental control) is
/// only shown what is known to be within it: a title whose rating isn't
/// known stays hidden, since the service also leaves it out when it couldn't
/// ask for it this time. Someone with no limit sees everything.
bool kostvAgeAllows(
  StremfinTitle title, {
  required KostvAgeLimit limit,
  required ParentalFilter parental,
}) {
  final limited =
      limit.maxAge != null ||
      limit.blockUnrated.contains(title.type) ||
      parental.isActive;
  if (!limited) return true;
  final age = title.age;
  if (age == null) return false;
  final maxAge = limit.maxAge;
  if (maxAge != null && age > maxAge) return false;
  if (parental.isActive) {
    final label = title.ageLabel;
    if (label != null && parental.isBlockedRating(label)) return false;
    if (parental.isBlockedRating('$age')) return false;
  }
  return true;
}
