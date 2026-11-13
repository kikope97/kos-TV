namespace Moonfin.Server.Kostv;

/// <summary>A favourite, as far as ordering it goes.</summary>
public sealed record KostvFavoriteEntry(string Id, DateTimeOffset? Since, DateTime Created);

/// <summary>A new episode of a favourite series, not seen yet.</summary>
public sealed record KostvNewEpisode(
    string Id,
    string SeriesId,
    string SeasonId,
    int Season,
    int Number,
    DateTime Added);

/// <summary>What arrived of one favourite series.</summary>
public sealed record KostvSeriesNews(
    string SeriesId,
    string FirstEpisodeId,
    int Count,
    bool NewSeason,
    int Season,
    DateTime Latest,
    bool Unseen);

/// <summary>A favourite film or series, as far as offering it again goes.</summary>
public sealed record KostvRewatchCandidate(
    string Id,
    DateTime? LastPlayed,
    bool Started,
    DateTimeOffset? Since);

/// <summary>
/// kOS TV: the plain workings of the favourites: their order, the news of the favourite series
/// and which ones to offer again. Kept apart from the server so they can be tried out.
/// </summary>
public static class KostvFavoritesEngine
{
    /// <summary>An episode added this long ago is still news of a favourite series.</summary>
    public static readonly TimeSpan NewsWindow = TimeSpan.FromDays(30);

    /// <summary>Watched longer ago than this: worth offering again.</summary>
    public static readonly TimeSpan RewatchAfter = TimeSpan.FromDays(180);

    /// <summary>Marked and never started for this long: worth a reminder.</summary>
    public static readonly TimeSpan RemindAfter = TimeSpan.FromDays(14);

    /// <summary>
    /// The favourites newest first: those whose moment is known by it, then the ones marked
    /// before it was kept, by when they arrived on the server. <paramref name="ascending"/>
    /// turns the whole of it round.
    /// </summary>
    public static IReadOnlyList<string> ByFavorited(IEnumerable<KostvFavoriteEntry> items, bool ascending)
    {
        var ordered = items
            .OrderByDescending(e => e.Since.HasValue)
            .ThenByDescending(e => e.Since)
            .ThenByDescending(e => e.Created)
            .ThenBy(e => e.Id, StringComparer.Ordinal)
            .Select(e => e.Id)
            .ToList();
        if (ascending)
        {
            ordered.Reverse();
        }

        return ordered;
    }

    /// <summary>
    /// The news of each favourite series, the latest first: how many arrived, the first of them,
    /// and whether they open a season the person didn't have before (no episode of it is older
    /// than <see cref="NewsWindow"/>: <paramref name="oldSeasons"/> holds the seasons that have
    /// one). Unseen when it came after <paramref name="seenAt"/>.
    /// </summary>
    public static IReadOnlyList<KostvSeriesNews> News(
        IEnumerable<KostvNewEpisode> episodes,
        IReadOnlySet<string> oldSeasons,
        DateTimeOffset? seenAt)
    {
        return episodes
            .GroupBy(e => e.SeriesId, StringComparer.Ordinal)
            .Select(group =>
            {
                var first = group
                    .OrderBy(e => e.Season)
                    .ThenBy(e => e.Number)
                    .First();
                var latest = group.Max(e => e.Added);
                return new KostvSeriesNews(
                    group.Key,
                    first.Id,
                    group.Count(),
                    !oldSeasons.Contains(first.SeasonId),
                    first.Season,
                    latest,
                    seenAt == null || latest > seenAt.Value.UtcDateTime);
            })
            .OrderByDescending(n => n.Latest)
            .ToList();
    }

    /// <summary>
    /// Favourites to offer again: watched more than <see cref="RewatchAfter"/> ago, or marked
    /// more than <see cref="RemindAfter"/> ago and never started. In an order that changes each
    /// <paramref name="day"/>, at most <paramref name="max"/>.
    /// </summary>
    public static IReadOnlyList<string> Rewatch(
        IEnumerable<KostvRewatchCandidate> candidates,
        DateTimeOffset now,
        int day,
        int max = 20)
    {
        return candidates
            .Where(c => c.LastPlayed is { } played
                ? now.UtcDateTime - played.ToUniversalTime() > RewatchAfter
                : !c.Started && (c.Since == null || now - c.Since.Value > RemindAfter))
            .OrderBy(c => Shuffle(c.Id, day))
            .ThenBy(c => c.Id, StringComparer.Ordinal)
            .Take(max)
            .Select(c => c.Id)
            .ToList();
    }

    // The same for a day, different the next.
    private static uint Shuffle(string id, int day)
    {
        var hash = 2166136261u ^ (uint)day;
        foreach (var c in id)
        {
            hash = (hash ^ c) * 16777619u;
        }

        return hash;
    }
}
