namespace Moonfin.Server.Kostv;

/// <summary>Why a title counts as something the person liked.</summary>
public enum KostvSeedKind
{
    /// <summary>A film they watched, or a series they watched to the end.</summary>
    Finished,

    /// <summary>A series they are part way through.</summary>
    Watching,

    /// <summary>One they marked as a favourite.</summary>
    Liked
}

/// <summary>A title the person watched, which what they are offered grows from.</summary>
public sealed record KostvSeed(
    string Key,
    string ItemId,
    string Name,
    bool IsSeries,
    KostvSeedKind Kind,
    double Weight);

/// <summary>Someone who made or acted in a seed.</summary>
public sealed record KostvPerson(string Id, string Name, bool IsDirector);

/// <summary>What TMDB says of a seed: what people who liked it also liked, and who made it.</summary>
public sealed record KostvSeedFacts(IReadOnlyList<string> Recommendations, IReadOnlyList<KostvPerson> People);

/// <summary>A film or series on the home server the person could be offered.</summary>
public sealed record KostvCandidate(
    string ItemId,
    string Key,
    bool IsSeries,
    bool Seen,
    double Rating,
    IReadOnlyList<string> Genres);

/// <summary>A row of the home page.</summary>
public sealed record KostvHomeRow(
    string Kind,
    string? Label,
    string? SeedItemId,
    IReadOnlyList<string> ItemIds);

/// <summary>
/// kOS TV: turns what a person has watched into the rows of their home page.
///
/// Everything offered is on the home server and not seen yet. What ties a row to the person is
/// TMDB's "people who liked this also liked" for the titles they watched, not a shared genre: a
/// title recommended by several of them, or by a recent one, ranks higher. Pure, so it can be
/// tested without a server: the service around it reads the history, the library and TMDB.
/// </summary>
public static class KostvHomeEngine
{
    public const string BecauseWatched = "because_watched";
    public const string BecauseWatching = "because_watching";
    public const string ForYou = "for_you";
    public const string WithPerson = "with_person";
    public const string Genre = "genre";
    public const string HiddenGems = "hidden_gems";

    /// <summary>A row with fewer titles than this isn't shown.</summary>
    public const int MinRow = 6;

    /// <summary>A row carries at most this many.</summary>
    public const int MaxRow = 20;

    /// <summary>How much a watch counts by how long ago it was: half after three weeks.</summary>
    public static double Recency(double daysAgo) =>
        Math.Max(0.05, Math.Pow(0.5, Math.Max(0, daysAgo) / 21.0));

    /// <summary>
    /// The people worth a row of their own: the directors and lead actors of what the person
    /// watched lately, the heaviest first.
    /// </summary>
    public static IReadOnlyList<KostvPerson> PeopleToAsk(
        IReadOnlyList<KostvSeed> seeds,
        IReadOnlyDictionary<string, KostvSeedFacts> facts,
        int limit = 8)
    {
        var weight = new Dictionary<string, (KostvPerson Person, double Weight)>();
        foreach (var seed in seeds)
        {
            if (!facts.TryGetValue(seed.Key, out var seedFacts))
            {
                continue;
            }

            foreach (var person in seedFacts.People)
            {
                var share = seed.Weight * (person.IsDirector ? 1.0 : 0.8);
                weight[person.Id] = weight.TryGetValue(person.Id, out var had)
                    ? (had.Person, had.Weight + share)
                    : (person, share);
            }
        }

        return weight.Values
            .OrderByDescending(p => p.Weight)
            .ThenBy(p => p.Person.Id, StringComparer.Ordinal)
            .Take(limit)
            .Select(p => p.Person)
            .ToList();
    }

    /// <summary>How much a title the person said they aren't interested in pulls down what TMDB finds like it.</summary>
    public const double AvoidWeight = 0.6;

    /// <summary>
    /// The rows, in the order they are shown. <paramref name="day"/> shuffles the ones further
    /// down, so the page isn't the same every day but is the same all day.
    /// <paramref name="dismissed"/> are the titles the person said they aren't interested in:
    /// never offered. <paramref name="avoid"/> is what TMDB says of them, so what is like them
    /// ranks lower.
    /// </summary>
    public static IReadOnlyList<KostvHomeRow> Build(
        IReadOnlyList<KostvSeed> seeds,
        IReadOnlyDictionary<string, KostvSeedFacts> facts,
        IReadOnlyDictionary<string, IReadOnlyList<string>> personCredits,
        IReadOnlyList<KostvCandidate> library,
        int day,
        IReadOnlyCollection<string>? dismissed = null,
        IReadOnlyList<KostvSeedFacts>? avoid = null,
        IReadOnlyCollection<string>? onList = null)
    {
        var notWanted = new HashSet<string>(dismissed ?? [], StringComparer.Ordinal);
        // On their list already: they know about it, so a row's place goes to something else.
        var known = new HashSet<string>(onList ?? [], StringComparer.Ordinal);

        // What can be offered: on the home server, not seen and not turned down. One per TMDB title.
        var byKey = new Dictionary<string, KostvCandidate>(StringComparer.Ordinal);
        foreach (var candidate in library)
        {
            if (!candidate.Seen && !string.IsNullOrEmpty(candidate.Key) && !notWanted.Contains(candidate.Key) && !known.Contains(candidate.Key))
            {
                byKey.TryAdd(candidate.Key, candidate);
            }
        }

        // How much each one fits the person: every seed that recommends it adds its weight,
        // more the higher it stands in that seed's list.
        var score = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var seed in seeds)
        {
            if (!facts.TryGetValue(seed.Key, out var seedFacts))
            {
                continue;
            }

            var count = seedFacts.Recommendations.Count;
            for (var rank = 0; rank < count; rank++)
            {
                var key = seedFacts.Recommendations[rank];
                if (!byKey.ContainsKey(key))
                {
                    continue;
                }

                var share = seed.Weight * (1.0 - (rank / (double)(count + 10)));
                score[key] = score.GetValueOrDefault(key) + share;
            }
        }

        // What is like a title they turned down counts against: ranked lower, and out of the
        // mixed row altogether when nothing they liked speaks for it more.
        foreach (var avoided in avoid ?? [])
        {
            var count = avoided.Recommendations.Count;
            for (var rank = 0; rank < count; rank++)
            {
                var key = avoided.Recommendations[rank];
                if (score.TryGetValue(key, out var had))
                {
                    var left = had - (AvoidWeight * (1.0 - (rank / (double)(count + 10))));
                    if (left > 0)
                    {
                        score[key] = left;
                    }
                    else
                    {
                        score.Remove(key);
                    }
                }
            }
        }

        double Fit(KostvCandidate c) => score.GetValueOrDefault(c.Key) * (0.8 + (0.04 * c.Rating));

        var used = new HashSet<string>(StringComparer.Ordinal);
        var rows = new List<KostvHomeRow>();

        // Takes the best of [keys] not shown in a row above; null when too few are left.
        KostvHomeRow? Row(string kind, string? label, string? seedItemId, IEnumerable<string> keys)
        {
            var picked = new List<KostvCandidate>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var key in keys)
            {
                if (picked.Count >= MaxRow)
                {
                    break;
                }

                if (byKey.TryGetValue(key, out var candidate) && !used.Contains(key) && seen.Add(key))
                {
                    picked.Add(candidate);
                }
            }

            if (picked.Count < MinRow)
            {
                return null;
            }

            foreach (var candidate in picked)
            {
                used.Add(candidate.Key);
            }

            return new KostvHomeRow(kind, label, seedItemId, picked.Select(c => c.ItemId).ToList());
        }

        KostvHomeRow? SeedRow(KostvSeed seed) =>
            facts.TryGetValue(seed.Key, out var seedFacts)
                ? Row(
                    seed.Kind == KostvSeedKind.Watching ? BecauseWatching : BecauseWatched,
                    seed.Name,
                    seed.ItemId,
                    seedFacts.Recommendations)
                : null;

        var ordered = seeds.OrderByDescending(s => s.Weight).ThenBy(s => s.Key, StringComparer.Ordinal).ToList();
        var seedsLeft = new List<KostvSeed>(ordered);

        // First, the last thing they finished and the series they are on.
        foreach (var kind in new[] { KostvSeedKind.Finished, KostvSeedKind.Watching })
        {
            foreach (var seed in ordered.Where(s => s.Kind == kind))
            {
                var row = SeedRow(seed);
                seedsLeft.Remove(seed);
                if (row != null)
                {
                    rows.Add(row);
                    break;
                }
            }
        }

        // Then everything they watched, taken together.
        var forYou = Row(
            ForYou,
            null,
            null,
            byKey.Values
                .Where(c => score.ContainsKey(c.Key))
                .OrderByDescending(Fit)
                .ThenBy(c => c.Key, StringComparer.Ordinal)
                .Select(c => c.Key));
        if (forYou != null)
        {
            rows.Add(forYou);
        }

        // Further down, a mix that changes with the day: more seeds, people, genres, gems.
        var more = new List<Func<KostvHomeRow?>>();
        foreach (var seed in seedsLeft)
        {
            more.Add(() => SeedRow(seed));
        }

        foreach (var person in PeopleToAsk(seeds, facts))
        {
            if (personCredits.TryGetValue(person.Id, out var credits))
            {
                more.Add(() => Row(
                    WithPerson,
                    person.Name,
                    null,
                    credits.Where(byKey.ContainsKey).OrderByDescending(k => Fit(byKey[k]) + (byKey[k].Rating / 100.0))));
            }
        }

        // The genres they watch most, each ranked by what fits them and then by how good it is.
        var genreWeight = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        var seedGenres = library.ToLookup(c => c.Key, c => c.Genres, StringComparer.Ordinal);
        foreach (var seed in seeds)
        {
            foreach (var genre in seedGenres[seed.Key].SelectMany(g => g).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                genreWeight[genre] = genreWeight.GetValueOrDefault(genre) + seed.Weight;
            }
        }

        // A title turned down weighs a little against its genres.
        foreach (var candidate in library.Where(c => notWanted.Contains(c.Key)))
        {
            foreach (var genre in candidate.Genres.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (genreWeight.ContainsKey(genre))
                {
                    genreWeight[genre] -= 0.3;
                }
            }
        }

        foreach (var genre in genreWeight.Where(g => g.Value > 0).OrderByDescending(g => g.Value).ThenBy(g => g.Key, StringComparer.Ordinal).Take(4).Select(g => g.Key))
        {
            more.Add(() => Row(
                Genre,
                genre,
                null,
                byKey.Values
                    .Where(c => c.Genres.Contains(genre, StringComparer.OrdinalIgnoreCase))
                    .OrderByDescending(c => (Fit(c) * 10) + c.Rating)
                    .ThenBy(c => c.Key, StringComparer.Ordinal)
                    .Select(c => c.Key)));
        }

        more.Add(() => Row(
            HiddenGems,
            null,
            null,
            byKey.Values
                .Where(c => c.Rating >= 7.5)
                .OrderByDescending(c => c.Rating + Fit(c))
                .ThenBy(c => c.Key, StringComparer.Ordinal)
                .Select(c => c.Key)));

        Shuffle(more, day);
        foreach (var make in more)
        {
            var row = make();
            if (row != null)
            {
                rows.Add(row);
            }
        }

        return rows;
    }

    // The same order for the same day on every server: no System.Random, whose sequence a
    // runtime may change.
    private static void Shuffle<T>(List<T> list, int day)
    {
        var state = unchecked((uint)((day * 2654435761L) + 12345));
        for (var i = list.Count - 1; i > 0; i--)
        {
            state = unchecked((state * 1664525u) + 1013904223u);
            var j = (int)(state % (uint)(i + 1));
            (list[i], list[j]) = (list[j], list[i]);
        }
    }
}
