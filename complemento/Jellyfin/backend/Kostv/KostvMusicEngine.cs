using System.Globalization;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: a song of the home server as the music engine sees it.</summary>
/// <param name="Id">The song.</param>
/// <param name="Artists">Its artists, the main one first.</param>
/// <param name="Genres">Its genres, as the server has them.</param>
/// <param name="PlayCount">How many times the person played it, as the server counts.</param>
/// <param name="LastPlayed">When the person last played it, as the server says.</param>
/// <param name="Favorite">Whether the person has a heart on it.</param>
public sealed record KostvMusicTrack(
    Guid Id,
    IReadOnlyList<string> Artists,
    IReadOnlyList<string> Genres,
    int PlayCount = 0,
    DateTime? LastPlayed = null,
    bool Favorite = false)
{
    public string? PrimaryArtist => Artists.Count > 0 ? Artists[0] : null;
}

/// <summary>kOS TV: how a person's listens of one song went.</summary>
public sealed class KostvTrackListens
{
    public int Completed { get; set; }

    public int Skipped { get; set; }

    public int Stopped { get; set; }

    /// <summary>The listens added up, the recent ones weighing more and skips against.</summary>
    public double Score { get; set; }

    public int Total => Completed + Skipped + Stopped;

    /// <summary>Skipped at least twice, and more often than not.</summary>
    public bool MostlySkipped => Skipped >= 2 && Skipped * 2 > Total;
}

/// <summary>kOS TV: what a person likes, worked out from the server's plays and their listens.</summary>
/// <param name="Scores">The songs they like, by how much (none skipped most times).</param>
/// <param name="Heard">Every song they have played, liked or not.</param>
/// <param name="Dropped">The songs they mostly skip.</param>
/// <param name="Genres">Their genres, the one they like most first.</param>
/// <param name="Artists">Their artists, the one they like most first.</param>
public sealed record KostvMusicProfile(
    IReadOnlyDictionary<Guid, double> Scores,
    IReadOnlySet<Guid> Heard,
    IReadOnlySet<Guid> Dropped,
    IReadOnlyList<KostvWeighted> Genres,
    IReadOnlyList<KostvWeighted> Artists);

/// <summary>kOS TV: a genre or an artist with how much it weighs.</summary>
public sealed record KostvWeighted(string Name, double Weight);

/// <summary>
/// kOS TV: one daily mix: its genre, the artists for its cover (and their ids, once looked up)
/// and its songs in order.
/// </summary>
public sealed record KostvMix(string Id, string Genre, IReadOnlyList<string> Artists, IReadOnlyList<Guid> Items, IReadOnlyList<Guid>? ArtistIds = null);

/// <summary>
/// kOS TV: the music the app offers each person, worked out from what the server knows of their
/// plays and from their listens (see <see cref="KostvMusicStore"/>): their daily mixes, the
/// artists to ask about for «Descubrimiento semanal», and the songs for the time of day. Pure:
/// the same person, day and library always give the same.
/// </summary>
public static class KostvMusicEngine
{
    public const string Morning = "manana";
    public const string Afternoon = "tarde";
    public const string Night = "noche";

    /// <summary>The times of day: morning 6–12, afternoon 12–20, night 20–6.</summary>
    public static readonly IReadOnlySet<string> Slots = new HashSet<string>(StringComparer.Ordinal) { Morning, Afternoon, Night };

    /// <summary>A music day starts at this hour at home, so a mix doesn't change at midnight.</summary>
    public const int DayStartHour = 5;

    public const int MaxMixes = 4;
    public const int MixSize = 50;

    /// <summary>A mix with fewer songs than this isn't offered.</summary>
    public const int MinMixSize = 20;

    /// <summary>A genre needs this many songs the person likes to have a mix.</summary>
    public const int MinFamiliarPerMix = 5;

    public const int MaxSeeds = 10;

    public const int MomentSize = 40;

    /// <summary>Of a mix of the moment, how much is what the person plays at that time.</summary>
    public const double MomentOwnShare = 0.4;

    public const int MomentMinListens = 25;
    public const int MomentMinDays = 5;
    public static readonly TimeSpan MomentWindow = TimeSpan.FromDays(60);

    /// <summary>A mix of the moment with fewer songs than this isn't offered.</summary>
    public const int MinMomentSize = 10;

    // ---------------------------------------------------------------- time

    /// <summary>The time of day of <paramref name="hour"/> at home.</summary>
    public static string SlotOf(int hour) => hour switch
    {
        >= 6 and < 12 => Morning,
        >= 12 and < 20 => Afternoon,
        _ => Night
    };

    /// <summary>The music day of <paramref name="now"/> at home: it starts at <see cref="DayStartHour"/>.</summary>
    public static DateOnly MusicDay(DateTimeOffset now, TimeZoneInfo zone) =>
        DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, zone).DateTime.AddHours(-DayStartHour));

    public static string DayKey(DateOnly day) => day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// <summary>The ISO week of <paramref name="now"/> at home, as "2026-W47".</summary>
    public static string WeekOf(DateTimeOffset now, TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTime(now, zone).DateTime;
        return string.Create(CultureInfo.InvariantCulture, $"{ISOWeek.GetYear(local):0000}-W{ISOWeek.GetWeekOfYear(local):00}");
    }

    private static double Recency(DateTimeOffset at, DateTimeOffset now, double halfLifeDays) =>
        Math.Pow(0.5, Math.Max(0, (now - at).TotalDays) / halfLifeDays);

    // ---------------------------------------------------------------- what they like

    /// <summary>How each song's listens went, the recent ones weighing more.</summary>
    public static Dictionary<Guid, KostvTrackListens> Listens(IEnumerable<KostvMusicEvent> events, DateTimeOffset now)
    {
        var byTrack = new Dictionary<Guid, KostvTrackListens>();
        foreach (var e in events)
        {
            if (!e.IsListen || !Guid.TryParse(e.Item, out var id))
            {
                continue;
            }

            if (!byTrack.TryGetValue(id, out var stats))
            {
                byTrack[id] = stats = new KostvTrackListens();
            }

            var recency = Recency(e.At, now, 30);
            switch (e.Outcome)
            {
                case KostvListenOutcome.Completed:
                    stats.Completed++;
                    stats.Score += recency;
                    break;
                case KostvListenOutcome.Skipped:
                    stats.Skipped++;
                    stats.Score -= 0.6 * recency;
                    break;
                default:
                    stats.Stopped++;
                    stats.Score += 0.4 * recency;
                    break;
            }
        }

        return byTrack;
    }

    /// <summary>
    /// What the person likes, from the server's plays of <paramref name="tracks"/> (how many
    /// times and how lately, and their hearts) and, when there are, their
    /// <paramref name="listens"/>: a song mostly skipped is dropped, recent plays weigh more.
    /// </summary>
    public static KostvMusicProfile Profile(
        IEnumerable<KostvMusicTrack> tracks,
        IReadOnlyDictionary<Guid, KostvTrackListens> listens,
        DateTimeOffset now)
    {
        var scores = new Dictionary<Guid, double>();
        var heard = new HashSet<Guid>();
        var dropped = new HashSet<Guid>();
        var unique = Unique(tracks);
        foreach (var track in unique)
        {
            listens.TryGetValue(track.Id, out var stats);
            if (track.PlayCount <= 0 && track.LastPlayed == null && stats == null && !track.Favorite)
            {
                continue;
            }

            if (track.PlayCount > 0 || track.LastPlayed != null || stats != null)
            {
                heard.Add(track.Id);
            }

            if (stats is { MostlySkipped: true } && !track.Favorite)
            {
                dropped.Add(track.Id);
                continue;
            }

            var score = 0.0;
            if (track.PlayCount > 0)
            {
                var recency = track.LastPlayed is { } last ? Recency(new DateTimeOffset(DateTime.SpecifyKind(last, DateTimeKind.Utc)), now, 60) : 0;
                score += Math.Log2(1 + track.PlayCount) * (0.35 + 0.65 * recency);
            }
            else if (track.LastPlayed != null)
            {
                score += 0.5;
            }

            if (track.Favorite)
            {
                score += 1.5;
            }

            if (stats != null)
            {
                score += 1.5 * stats.Score;
            }

            if (score > 0)
            {
                scores[track.Id] = score;
            }
        }

        var liked = unique.Where(t => scores.ContainsKey(t.Id)).ToList();
        var genres = Weigh(liked.SelectMany(t => t.Genres.Select(g => (Name: g, Weight: scores[t.Id]))));
        var artists = Weigh(liked.SelectMany(t => t.Artists.Select((a, i) => (Name: a, Weight: i == 0 ? scores[t.Id] : scores[t.Id] / 2))));
        return new KostvMusicProfile(scores, heard, dropped, genres, artists);
    }

    /// <summary>Up to <see cref="MaxSeeds"/> artists the person likes most, for «Descubrimiento semanal».</summary>
    public static IReadOnlyList<string> Seeds(KostvMusicProfile profile) =>
        profile.Artists.Where(a => a.Weight > 0).Take(MaxSeeds).Select(a => a.Name).ToList();

    // ---------------------------------------------------------------- daily mixes

    /// <summary>
    /// Up to <see cref="MaxMixes"/> mixes of about <see cref="MixSize"/> songs for
    /// <paramref name="userId"/> on <paramref name="day"/>, one per genre they like most: half
    /// songs they play and don't skip, half songs of those artists they haven't heard and of
    /// artists like them (<paramref name="similar"/>, by artist) at home. No song in two mixes,
    /// and the same artist not twice in a row when it can be helped. A genre without enough is
    /// left out, so there may be fewer mixes, or none.
    /// </summary>
    public static IReadOnlyList<KostvMix> Mixes(
        Guid userId,
        string day,
        IEnumerable<KostvMusicTrack> tracks,
        KostvMusicProfile profile,
        IReadOnlyDictionary<string, IReadOnlyList<string>>? similar = null)
    {
        var all = Unique(tracks);
        var similarByKey = SimilarByKey(similar);
        var used = new HashSet<Guid>();
        var mixes = new List<KostvMix>();
        var half = MixSize / 2;
        foreach (var genre in profile.Genres)
        {
            if (mixes.Count >= MaxMixes)
            {
                break;
            }

            var genreKey = Key(genre.Name);
            var random = RandomFor(userId, day, "mix", genreKey);
            bool InGenre(KostvMusicTrack t) => t.Genres.Any(g => Key(g) == genreKey);

            var familiar = all.Where(t => profile.Scores.ContainsKey(t.Id) && !used.Contains(t.Id) && InGenre(t)).ToList();
            if (familiar.Count < MinFamiliarPerMix)
            {
                continue;
            }

            var familiarOrder = WeightedOrder(familiar, t => profile.Scores[t.Id], random);
            var artistWeights = ArtistWeights(familiar, t => profile.Scores[t.Id]);
            var familiarIds = familiar.Select(t => t.Id).ToHashSet();
            var fresh = all.Where(t => !used.Contains(t.Id) && !familiarIds.Contains(t.Id) && !profile.Dropped.Contains(t.Id)).ToList();
            var unheard = fresh.Where(t => !profile.Heard.Contains(t.Id)).ToList();
            var alike = SimilarArtists(artistWeights.Keys, similarByKey);

            // Their artists' songs they haven't heard, then songs of the genre by artists like
            // theirs, then any other of the genre they haven't heard.
            var newOrder = Concat(
                WeightedOrder(unheard.Where(t => t.Artists.Any(a => artistWeights.ContainsKey(Key(a)))).ToList(), t => t.Artists.Select(a => artistWeights.GetValueOrDefault(Key(a))).Max(), random),
                WeightedOrder(fresh.Where(t => InGenre(t) && t.Artists.Any(a => alike.Contains(Key(a)))).ToList(), t => 1 + profile.Scores.GetValueOrDefault(t.Id), random),
                WeightedOrder(unheard.Where(InGenre).ToList(), _ => 1, random));

            var (own, others) = Split(familiarOrder, newOrder, half, MixSize);
            if (own.Count + others.Count < MinMixSize)
            {
                continue;
            }

            var items = Spread(Interleave(own, others));
            used.UnionWith(items.Select(t => t.Id));
            mixes.Add(new KostvMix(
                string.Create(CultureInfo.InvariantCulture, $"daily-{mixes.Count + 1}"),
                genre.Name,
                Cover(items, artistWeights),
                items.Select(t => t.Id).ToList()));
        }

        return mixes;
    }

    // ---------------------------------------------------------------- the time of day

    /// <summary>
    /// The listens of <paramref name="slot"/> in the last <see cref="MomentWindow"/>, by the hour
    /// at home worked out of when they were (not the hour noted, which may be of another zone).
    /// </summary>
    public static IEnumerable<KostvMusicEvent> SlotListens(IEnumerable<KostvMusicEvent> events, string slot, DateTimeOffset now, TimeZoneInfo zone) =>
        events.Where(e => e.IsListen && e.At >= now - MomentWindow && e.At <= now && SlotOf(e.LocalIn(zone).Hour) == slot);

    /// <summary>
    /// The day a listen at <paramref name="at"/> counts for in its time of day: the night from 20:00
    /// to 6:00 is one, so what is played after midnight counts for the day before.
    /// </summary>
    public static DateOnly SlotDay(DateTimeOffset at, TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTime(at, zone).DateTime;
        return DateOnly.FromDateTime(local.Hour < 6 ? local.AddDays(-1) : local);
    }

    /// <summary>
    /// Whether the person has listened enough at <paramref name="slot"/> for a mix of it: at
    /// least <see cref="MomentMinListens"/> listens on at least <see cref="MomentMinDays"/>
    /// different days, within the last <see cref="MomentWindow"/>. Only listens not skipped count,
    /// and a night past midnight is one day (see <see cref="SlotDay"/>).
    /// </summary>
    public static bool MomentReady(IEnumerable<KostvMusicEvent> events, string slot, DateTimeOffset now, TimeZoneInfo zone)
    {
        var listens = SlotListens(events, slot, now, zone).Where(e => e.Outcome != KostvListenOutcome.Skipped).ToList();
        return listens.Count >= MomentMinListens && listens.Select(e => SlotDay(e.At, zone)).Distinct().Count() >= MomentMinDays;
    }

    /// <summary>
    /// The songs for <paramref name="slot"/>: about <see cref="MomentOwnShare"/> of what the
    /// person plays at that time (not what they skip), the rest songs like them at home (their
    /// artists, artists like them, their genres). The same all day for the person and slot.
    /// </summary>
    public static IReadOnlyList<Guid> Moment(
        Guid userId,
        string day,
        string slot,
        IEnumerable<KostvMusicEvent> events,
        IEnumerable<KostvMusicTrack> tracks,
        KostvMusicProfile profile,
        DateTimeOffset now,
        TimeZoneInfo zone,
        IReadOnlyDictionary<string, IReadOnlyList<string>>? similar = null)
    {
        var all = Unique(tracks);
        var random = RandomFor(userId, day, "moment", slot);
        var slotScores = new Dictionary<Guid, double>();
        foreach (var e in SlotListens(events, slot, now, zone))
        {
            if (e.Outcome == KostvListenOutcome.Skipped || !Guid.TryParse(e.Item, out var id))
            {
                continue;
            }

            slotScores[id] = slotScores.GetValueOrDefault(id) + (e.Outcome == KostvListenOutcome.Completed ? 1 : 0.5) * Recency(e.At, now, 30);
        }

        var own = all.Where(t => slotScores.ContainsKey(t.Id) && !profile.Dropped.Contains(t.Id)).ToList();
        var ownIds = own.Select(t => t.Id).ToHashSet();
        var artistWeights = ArtistWeights(own, t => slotScores[t.Id]);
        var genres = Weigh(own.SelectMany(t => t.Genres.Select(g => (Name: g, Weight: slotScores[t.Id])))).Take(3).Select(g => Key(g.Name)).ToHashSet();
        var alike = SimilarArtists(artistWeights.Keys, SimilarByKey(similar));
        var rest = all.Where(t => !ownIds.Contains(t.Id) && !profile.Dropped.Contains(t.Id)).ToList();

        var ownOrder = WeightedOrder(own, t => slotScores[t.Id], random);
        var likeOrder = Concat(
            WeightedOrder(rest.Where(t => t.Artists.Any(a => artistWeights.ContainsKey(Key(a)))).ToList(), t => t.Artists.Select(a => artistWeights.GetValueOrDefault(Key(a))).Max() + profile.Scores.GetValueOrDefault(t.Id), random),
            WeightedOrder(rest.Where(t => t.Artists.Any(a => alike.Contains(Key(a)))).ToList(), t => 1 + profile.Scores.GetValueOrDefault(t.Id), random),
            WeightedOrder(rest.Where(t => t.Genres.Any(g => genres.Contains(Key(g)))).ToList(), t => 1 + profile.Scores.GetValueOrDefault(t.Id), random));

        var ownTarget = (int)Math.Round(MomentSize * MomentOwnShare);
        var (mine, like) = Split(ownOrder, likeOrder, ownTarget, MomentSize, othersFirst: MomentSize - ownTarget);
        var items = Spread(Interleave(like, mine));
        return items.Count < MinMomentSize ? [] : items.Select(t => t.Id).ToList();
    }

    // ---------------------------------------------------------------- helpers

    /// <summary>Genres and artists are matched without minding case or spaces around.</summary>
    internal static string Key(string name) => name.Trim().ToLowerInvariant();

    // Each song once, in the order of its id, so what the library gives in any order makes the same.
    private static List<KostvMusicTrack> Unique(IEnumerable<KostvMusicTrack> tracks) =>
        tracks.GroupBy(t => t.Id).Select(g => g.First()).OrderBy(t => t.Id).ToList();

    /// <summary>Names weighed up, matched without case, the heaviest first, each as most often written.</summary>
    private static List<KostvWeighted> Weigh(IEnumerable<(string Name, double Weight)> entries)
    {
        return entries
            .Where(e => !string.IsNullOrWhiteSpace(e.Name))
            .GroupBy(e => Key(e.Name))
            .Select(g => new KostvWeighted(
                g.GroupBy(e => e.Name.Trim()).OrderByDescending(s => s.Count()).ThenBy(s => s.Key, StringComparer.Ordinal).First().Key,
                g.Sum(e => e.Weight)))
            .OrderByDescending(w => w.Weight)
            .ThenBy(w => w.Name, StringComparer.Ordinal)
            .ToList();
    }

    private static Dictionary<string, double> ArtistWeights(IEnumerable<KostvMusicTrack> tracks, Func<KostvMusicTrack, double> weight)
    {
        var weights = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var track in tracks)
        {
            for (var i = 0; i < track.Artists.Count; i++)
            {
                var key = Key(track.Artists[i]);
                if (key.Length > 0)
                {
                    weights[key] = weights.GetValueOrDefault(key) + (i == 0 ? weight(track) : weight(track) / 2);
                }
            }
        }

        return weights;
    }

    private static Dictionary<string, IReadOnlyList<string>> SimilarByKey(IReadOnlyDictionary<string, IReadOnlyList<string>>? similar)
    {
        var byKey = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        foreach (var (artist, alike) in similar ?? new Dictionary<string, IReadOnlyList<string>>())
        {
            byKey[Key(artist)] = alike;
        }

        return byKey;
    }

    private static HashSet<string> SimilarArtists(IEnumerable<string> artistKeys, IReadOnlyDictionary<string, IReadOnlyList<string>> similar)
    {
        var keys = artistKeys.ToHashSet(StringComparer.Ordinal);
        var alike = new HashSet<string>(StringComparer.Ordinal);
        foreach (var key in keys)
        {
            if (similar.TryGetValue(key, out var names))
            {
                alike.UnionWith(names.Select(Key).Where(k => k.Length > 0 && !keys.Contains(k)));
            }
        }

        return alike;
    }

    /// <summary>
    /// <paramref name="items"/> in a random order where the heavier come first more often
    /// (each drawn with odds by its weight), the same for the same <paramref name="random"/>.
    /// </summary>
    private static List<KostvMusicTrack> WeightedOrder(List<KostvMusicTrack> items, Func<KostvMusicTrack, double> weight, Random random) =>
        items
            .Select(t => (Track: t, Key: Math.Pow(random.NextDouble(), 1 / Math.Max(0.01, weight(t)))))
            .OrderByDescending(x => x.Key)
            .ThenBy(x => x.Track.Id)
            .Select(x => x.Track)
            .ToList();

    private static List<KostvMusicTrack> Concat(params List<KostvMusicTrack>[] lists)
    {
        var seen = new HashSet<Guid>();
        return lists.SelectMany(l => l).Where(t => seen.Add(t.Id)).ToList();
    }

    /// <summary>
    /// <paramref name="ownTarget"/> of <paramref name="own"/> and the rest up to
    /// <paramref name="size"/> of <paramref name="others"/>; when one falls short, more of the other.
    /// </summary>
    private static (List<KostvMusicTrack> Own, List<KostvMusicTrack> Others) Split(
        List<KostvMusicTrack> own,
        List<KostvMusicTrack> others,
        int ownTarget,
        int size,
        int? othersFirst = null)
    {
        var ownIds = own.Select(t => t.Id).ToHashSet();
        others = others.Where(t => !ownIds.Contains(t.Id)).ToList();
        var othersCount = Math.Min(othersFirst ?? size - ownTarget, others.Count);
        var ownCount = Math.Min(own.Count, size - othersCount);
        othersCount = Math.Min(others.Count, size - ownCount);
        return (own.Take(ownCount).ToList(), others.Take(othersCount).ToList());
    }

    private static List<KostvMusicTrack> Interleave(List<KostvMusicTrack> first, List<KostvMusicTrack> second)
    {
        var result = new List<KostvMusicTrack>(first.Count + second.Count);
        for (var i = 0; i < Math.Max(first.Count, second.Count); i++)
        {
            if (i < first.Count)
            {
                result.Add(first[i]);
            }

            if (i < second.Count)
            {
                result.Add(second[i]);
            }
        }

        return result;
    }

    /// <summary>The same order, moving a song along when its artist would play twice in a row.</summary>
    internal static List<KostvMusicTrack> Spread(List<KostvMusicTrack> items)
    {
        var left = new List<KostvMusicTrack>(items);
        var result = new List<KostvMusicTrack>(items.Count);
        while (left.Count > 0)
        {
            var last = result.Count > 0 ? ArtistKey(result[^1]) : null;
            // The artist with most songs left goes now when waiting would leave them side by side
            // at the end; otherwise the next song by anyone but the last artist.
            var most = left.GroupBy(ArtistKey).OrderByDescending(g => g.Count()).First();
            var index = most.Key != last && most.Count() * 2 > left.Count
                ? left.FindIndex(t => ArtistKey(t) == most.Key)
                : left.FindIndex(t => last == null || ArtistKey(t) != last);
            if (index < 0)
            {
                index = 0;
            }

            result.Add(left[index]);
            left.RemoveAt(index);
        }

        return result;
    }

    private static string ArtistKey(KostvMusicTrack track) => track.PrimaryArtist is { } a ? Key(a) : track.Id.ToString("N");

    /// <summary>The three artists most in <paramref name="items"/>, for its cover.</summary>
    private static List<string> Cover(List<KostvMusicTrack> items, IReadOnlyDictionary<string, double> weights) =>
        items
            .Where(t => t.PrimaryArtist != null)
            .GroupBy(t => Key(t.PrimaryArtist!))
            .OrderByDescending(g => g.Count())
            .ThenByDescending(g => weights.GetValueOrDefault(g.Key))
            .ThenBy(g => g.Key, StringComparer.Ordinal)
            .Take(3)
            .Select(g => g.First().PrimaryArtist!.Trim())
            .ToList();

    /// <summary>A random sequence fixed by the person, the day and what it is for.</summary>
    internal static Random RandomFor(Guid userId, string day, string kind, string key)
    {
        var hash = Hash($"{userId:N}|{day}|{kind}|{key}");
        return new Random((int)(hash ^ (hash >> 32)));
    }

    /// <summary>
    /// <paramref name="ids"/> in a random order fixed by the person, the day and what it is for
    /// (each id has its own place, so one more or less doesn't move the rest).
    /// </summary>
    public static IEnumerable<Guid> Shuffled(IEnumerable<Guid> ids, Guid userId, string day, string kind) =>
        ids.Distinct().OrderBy(id => Hash($"{userId:N}|{day}|{kind}|{id:N}")).ThenBy(id => id);

    // FNV-1a: string.GetHashCode changes from one run of the server to the next.
    private static ulong Hash(string text)
    {
        var hash = 14695981039346656037UL;
        foreach (var c in text)
        {
            hash ^= c;
            hash *= 1099511628211UL;
        }

        return hash;
    }
}
