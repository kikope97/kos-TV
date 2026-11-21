using System.Globalization;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: a song of the home server as the music engine sees it.</summary>
/// <param name="Id">The song.</param>
/// <param name="Artists">Its artists, the main one first.</param>
/// <param name="Genres">Its genres, as the server has them.</param>
/// <param name="PlayCount">How many times the person played it, as the server counts.</param>
/// <param name="LastPlayed">When the person last played it, as the server says.</param>
/// <param name="Favorite">Whether the person has a heart on it.</param>
/// <param name="Album">Its album, when known (two of one album don't go one after the other).</param>
public sealed record KostvMusicTrack(
    Guid Id,
    IReadOnlyList<string> Artists,
    IReadOnlyList<string> Genres,
    int PlayCount = 0,
    DateTime? LastPlayed = null,
    bool Favorite = false,
    Guid? Album = null)
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
    IReadOnlyList<KostvWeighted> Artists)
{
    /// <summary>When each song was last heard, to tell the forgotten ones; null when unknown.</summary>
    public IReadOnlyDictionary<Guid, DateTimeOffset>? LastHeard { get; init; }

    /// <summary>
    /// What is taken off a song never played for the weeks it was shown in the mixes (new engine
    /// only), so the new songs don't keep coming back.
    /// </summary>
    public IReadOnlyDictionary<Guid, double>? ShownPenalty { get; init; }

    /// <summary>The artists by the background taste (halving every 90 days), for the seeds; null: <see cref="Artists"/>.</summary>
    public IReadOnlyList<KostvWeighted>? Background { get; init; }

    /// <summary>The artists by the taste of now (halving every 14 days); null when not worked out.</summary>
    public IReadOnlyList<KostvWeighted>? Recent { get; init; }
}

/// <summary>kOS TV: a genre or an artist with how much it weighs.</summary>
public sealed record KostvWeighted(string Name, double Weight);

/// <summary>
/// kOS TV: one daily mix: its genre, the artists for its cover (and their ids, once looked up),
/// its songs in order and the three artists that weigh most in it (for «Con X, Y y más»; null in
/// a mix kept before there were).
/// </summary>
public sealed record KostvMix(
    string Id,
    string Genre,
    IReadOnlyList<string> Artists,
    IReadOnlyList<Guid> Items,
    IReadOnlyList<Guid>? ArtistIds = null,
    IReadOnlyList<string>? Because = null);

/// <summary>
/// kOS TV: the music the app offers each person, worked out from what the server knows of their
/// plays and from their listens (see <see cref="KostvMusicStore"/>): their daily mixes, the
/// artists to ask about for «Descubrimiento semanal», and the songs for the time of day. Pure:
/// the same person, day and library always give the same.
/// </summary>
public static partial class KostvMusicEngine
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

    /// <summary>
    /// The songs the person knows a mix is made of (three of each four): with fewer left after
    /// those not to repeat, some of these are given back (see <see cref="KostvMixRules.Readmit"/>).
    /// </summary>
    public const int KnownPerMix = 38;

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

    /// <summary>
    /// How each song's listens went, the recent ones weighing more. One that failed to play early
    /// is left out (see <see cref="KostvMusicEvent.Counts"/>): it is not a skip.
    /// </summary>
    public static Dictionary<Guid, KostvTrackListens> Listens(IEnumerable<KostvMusicEvent> events, DateTimeOffset now)
    {
        var byTrack = new Dictionary<Guid, KostvTrackListens>();
        foreach (var e in events)
        {
            if (!e.Counts || !Guid.TryParse(e.Item, out var id))
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
        DateTimeOffset now,
        KostvDislikeSet? dislikes = null)
    {
        dislikes ??= KostvDislikeSet.Empty;
        var scores = new Dictionary<Guid, double>();
        var heard = new HashSet<Guid>();
        var dropped = new HashSet<Guid>();
        var lastHeard = new Dictionary<Guid, DateTimeOffset>();
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

            if (track.LastPlayed is { } played)
            {
                lastHeard[track.Id] = new DateTimeOffset(DateTime.SpecifyKind(played, DateTimeKind.Utc));
            }

            // Kos TV: «no me gusta» counts whatever engine scores the music.
            if (dislikes.Blocks(track))
            {
                dropped.Add(track.Id);
                continue;
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

            score *= dislikes.Factor(track);
            if (score > 0)
            {
                scores[track.Id] = score;
            }
        }

        var liked = unique.Where(t => scores.ContainsKey(t.Id)).ToList();
        var genres = Weigh(liked.SelectMany(t => t.Genres.Select(g => (Name: g, Weight: scores[t.Id]))));
        var artists = Weigh(liked.SelectMany(t => t.Artists.Select((a, i) => (Name: a, Weight: i == 0 ? scores[t.Id] : scores[t.Id] / 2))));
        return new KostvMusicProfile(scores, heard, dropped, genres, artists) { LastHeard = lastHeard };
    }

    /// <summary>Up to <see cref="MaxSeeds"/> artists the person likes most, for «Descubrimiento semanal».</summary>
    public static IReadOnlyList<string> Seeds(KostvMusicProfile profile) =>
        profile.Artists.Where(a => a.Weight > 0).Take(MaxSeeds).Select(a => a.Name).ToList();

    // ---------------------------------------------------------------- daily mixes

    /// <summary>
    /// Up to <see cref="MaxMixes"/> mixes of about <see cref="MixSize"/> songs for
    /// <paramref name="userId"/> on <paramref name="day"/>, one per genre they like most: three
    /// of four songs they play and don't skip (some of them forgotten ones: liked, and unheard for
    /// a month), one of four songs of those artists they haven't heard and of artists like them
    /// (<paramref name="similar"/>, by artist) at home. Arranged by the rules of variety (see
    /// <see cref="Arrange"/>), no song in two mixes, and none of what <paramref name="rules"/>
    /// leaves out. A genre without enough is left out, so there may be fewer mixes, or none.
    /// </summary>
    public static IReadOnlyList<KostvMix> Mixes(
        Guid userId,
        string day,
        IEnumerable<KostvMusicTrack> tracks,
        KostvMusicProfile profile,
        IReadOnlyDictionary<string, IReadOnlyList<string>>? similar = null,
        KostvMixRules? rules = null)
    {
        rules ??= KostvMixRules.None;
        var all = Allowed(tracks, rules);
        var similarByKey = SimilarByKey(similar);
        var used = new HashSet<Guid>();
        var mixes = new List<KostvMix>();
        foreach (var genre in profile.Genres)
        {
            if (mixes.Count >= MaxMixes)
            {
                break;
            }

            var genreKey = Key(genre.Name);
            var random = RandomFor(userId, day, "mix", genreKey);
            bool InGenre(KostvMusicTrack t) => t.Genres.Any(g => Key(g) == genreKey);

            bool Familiar(KostvMusicTrack t) => profile.Scores.ContainsKey(t.Id) && !used.Contains(t.Id) && InGenre(t);
            var familiar = all.Where(Familiar).ToList();
            // Too few left after the days before: some of those given back, the oldest first.
            var back = Readmitted(tracks, rules, Familiar, familiar.Count, KnownPerMix);
            if (back.Count > 0)
            {
                familiar = familiar.Concat(back).OrderBy(t => t.Id).ToList();
            }

            if (familiar.Count < MinFamiliarPerMix)
            {
                continue;
            }

            var familiarOrder = WithForgotten(WeightedOrder(familiar, t => profile.Scores[t.Id], random), profile, rules.Now);
            var artistWeights = ArtistWeights(familiar, t => profile.Scores[t.Id]);
            var familiarIds = familiar.Select(t => t.Id).ToHashSet();
            var fresh = all.Where(t => !used.Contains(t.Id) && !familiarIds.Contains(t.Id) && !profile.Dropped.Contains(t.Id)).ToList();
            var unheard = fresh.Where(t => !profile.Heard.Contains(t.Id)).ToList();
            var alike = SimilarArtists(artistWeights.Keys, similarByKey);

            // Their artists' songs they haven't heard, then songs of the genre by artists like
            // theirs, then any other of the genre they haven't heard; less each week one was
            // shown and not played.
            var newOrder = Concat(
                WeightedOrder(unheard.Where(t => t.Artists.Any(a => artistWeights.ContainsKey(Key(a)))).ToList(), t => t.Artists.Select(a => artistWeights.GetValueOrDefault(Key(a))).Max() * Fresh(profile, t), random),
                WeightedOrder(fresh.Where(t => InGenre(t) && t.Artists.Any(a => alike.Contains(Key(a)))).ToList(), t => (1 + profile.Scores.GetValueOrDefault(t.Id)) * Fresh(profile, t), random),
                WeightedOrder(unheard.Where(InGenre).ToList(), t => Fresh(profile, t), random));

            var items = Arrange(familiarOrder, newOrder, MixSize, MixNearShare, t => profile.Scores.GetValueOrDefault(t.Id), similarByKey, fillTo: MinMixSize);
            if (items.Count < MinMixSize)
            {
                continue;
            }

            used.UnionWith(items.Select(t => t.Id));
            mixes.Add(new KostvMix(
                string.Create(CultureInfo.InvariantCulture, $"daily-{mixes.Count + 1}"),
                genre.Name,
                Cover(items, artistWeights),
                items.Select(t => t.Id).ToList(),
                Because: BecauseOf(items, profile)));
        }

        return mixes;
    }

    // ---------------------------------------------------------------- the time of day

    /// <summary>
    /// The listens of <paramref name="slot"/> in the last <see cref="MomentWindow"/>, by the hour
    /// at home worked out of when they were (not the hour noted, which may be of another zone).
    /// One that failed to play early is left out (see <see cref="KostvMusicEvent.Counts"/>).
    /// </summary>
    public static IEnumerable<KostvMusicEvent> SlotListens(IEnumerable<KostvMusicEvent> events, string slot, DateTimeOffset now, TimeZoneInfo zone) =>
        events.Where(e => e.Counts && e.At >= now - MomentWindow && e.At <= now && SlotOf(e.LocalIn(zone).Hour) == slot);

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
    /// artists, artists like them, their genres), arranged by the rules of variety (see
    /// <see cref="Arrange"/>) and without what <paramref name="rules"/> leaves out. The same all
    /// day for the person and slot. With <paramref name="learned"/> (the new engine) each listen
    /// weighs as in the taste, and what is played then is mixed with their taste overall until the
    /// time of day has enough of its own.
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
        IReadOnlyDictionary<string, IReadOnlyList<string>>? similar = null,
        KostvMixRules? rules = null,
        bool learned = false)
    {
        rules ??= KostvMixRules.None;
        var all = Allowed(tracks, rules);
        var random = RandomFor(userId, day, "moment", slot);
        var slotScores = new Dictionary<Guid, double>();
        var slotListens = 0;
        foreach (var e in SlotListens(events, slot, now, zone))
        {
            if (e.Outcome == KostvListenOutcome.Skipped || !Guid.TryParse(e.Item, out var id))
            {
                continue;
            }

            slotListens++;
            var weight = learned ? Math.Max(0, WeighListen(e).Weight) : e.Outcome == KostvListenOutcome.Completed ? 1 : 0.5;
            slotScores[id] = slotScores.GetValueOrDefault(id) + weight * Recency(e.At, now, 30);
        }

        if (learned)
        {
            // Their taste overall weighs less as the time of day has more of its own.
            var own = Math.Min(1, slotListens / (double)MomentOwnListens);
            foreach (var id in slotScores.Keys.ToList())
            {
                slotScores[id] = own * slotScores[id] + (1 - own) * profile.Scores.GetValueOrDefault(id);
            }
        }

        bool Own(KostvMusicTrack t) => slotScores.GetValueOrDefault(t.Id) > 0 && !profile.Dropped.Contains(t.Id);
        var ownTracks = all.Where(Own).ToList();
        // Too few left after the days before: some of those given back, the oldest first.
        var ownBack = Readmitted(tracks, rules, Own, ownTracks.Count, (int)Math.Ceiling(MomentSize * MomentOwnShare));
        if (ownBack.Count > 0)
        {
            ownTracks = ownTracks.Concat(ownBack).OrderBy(t => t.Id).ToList();
        }

        var ownIds = ownTracks.Select(t => t.Id).ToHashSet();
        var artistWeights = ArtistWeights(ownTracks, t => slotScores[t.Id]);
        var genres = Weigh(ownTracks.SelectMany(t => t.Genres.Select(g => (Name: g, Weight: slotScores[t.Id])))).Take(3).Select(g => Key(g.Name)).ToHashSet();
        var similarByKey = SimilarByKey(similar);
        var alike = SimilarArtists(artistWeights.Keys, similarByKey);
        var rest = all.Where(t => !ownIds.Contains(t.Id) && !profile.Dropped.Contains(t.Id)).ToList();

        var ownOrder = WeightedOrder(ownTracks, t => slotScores[t.Id], random);
        var likeOrder = Concat(
            WeightedOrder(rest.Where(t => t.Artists.Any(a => artistWeights.ContainsKey(Key(a)))).ToList(), t => (t.Artists.Select(a => artistWeights.GetValueOrDefault(Key(a))).Max() + profile.Scores.GetValueOrDefault(t.Id)) * Fresh(profile, t), random),
            WeightedOrder(rest.Where(t => t.Artists.Any(a => alike.Contains(Key(a)))).ToList(), t => (1 + profile.Scores.GetValueOrDefault(t.Id)) * Fresh(profile, t), random),
            WeightedOrder(rest.Where(t => t.Genres.Any(g => genres.Contains(Key(g)))).ToList(), t => (1 + profile.Scores.GetValueOrDefault(t.Id)) * Fresh(profile, t), random));

        var items = Arrange(ownOrder, likeOrder, MomentSize, 1 - MomentOwnShare, t => slotScores.GetValueOrDefault(t.Id), similarByKey, fillTo: MinMomentSize);
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
