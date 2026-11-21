namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: the engine that learns from every signal (<c>docs/musica-plan-fundido-y-aprender.md</c>,
/// 3.2 and 3.3): what each listen weighs, the person's taste summed up song by song, their
/// profile mixed with what the server knows as they listen more, the seeds rotating each week,
/// and the rules of variety every mix follows, whatever engine scores it. Pure, like the rest of
/// <see cref="KostvMusicEngine"/>: the same lines, library and time always give the same.
/// </summary>
public static partial class KostvMusicEngine
{
    /// <summary>Of a daily mix, the share of songs near (new to the person) rather than known.</summary>
    public const double MixNearShare = 0.25;

    /// <summary>With this many listens of its own, a time of day no longer leans on the taste overall.</summary>
    public const int MomentOwnListens = 100;

    /// <summary>The seeds of «Descubrimiento semanal» are drawn each week from this many artists.</summary>
    public const int MaxSeedPool = 20;

    /// <summary>Of the seeds, these many of the artists liked most are always in.</summary>
    public const int FixedSeeds = 3;

    /// <summary>At least this many songs between two of the same artist.</summary>
    public const int VarietyGap = 3;

    /// <summary>At most <see cref="VarietyPerBlock"/> songs of one artist each <see cref="VarietyBlock"/>.</summary>
    public const int VarietyBlock = 25;

    public const int VarietyPerBlock = 3;

    /// <summary>The songs of each engine compared with what was heard whole the next day.</summary>
    public const int TopCompared = 25;

    // Of the next songs that fit, the one closest to the one before goes (so it flows).
    private const int ChainLookahead = 6;

    // One of each this many known songs of a mix is a forgotten one, when there are.
    private const int ForgottenEvery = 5;

    private static readonly HashSet<string> ByHandSources = new(StringComparer.Ordinal) { "search", "album", "playlist", "favorites", "artist" };
    private static readonly HashSet<string> OnPurposeSources = new(StringComparer.Ordinal) { "search", "album" };

    // ---------------------------------------------------------------- what a listen weighs

    /// <summary>
    /// What <paramref name="e"/> says of the person's taste (see <see cref="KostvTasteWeights"/>):
    /// heard (half of it or 4 minutes, or to its end) +1, more if played again or taken back,
    /// ×1.5 when chosen on purpose; stopped by the app closing, the session ending, a failure or
    /// nothing following, nothing; otherwise a skip, weighing by how soon and from where. A fade
    /// into the next song ends it as heard, so it is never a skip.
    /// </summary>
    public static KostvListenWeight WeighListen(KostvMusicEvent e)
    {
        if (!e.Counts)
        {
            return KostvListenWeight.Nothing;
        }

        var played = Math.Max(0, e.Played ?? 0);
        double? duration = e.Duration is > 0 and var d ? d : null;
        var heard = e.Outcome == KostvListenOutcome.Completed ||
            e.EndedBy == KostvListenEnd.Natural ||
            (duration is { } length ? played >= Math.Min(length / 2, 240) : played >= 240);
        var source = e.Source;
        if (heard)
        {
            var weight = KostvTasteWeights.Heard + (e.Replay == true || e.SeekBack > 0 ? KostvTasteWeights.Replay : 0);
            if (source != null && OnPurposeSources.Contains(source) && e.Shuffle != true)
            {
                weight *= KostvTasteWeights.OnPurpose;
            }

            return new KostvListenWeight(weight, true, false);
        }

        if (e.EndedBy is KostvListenEnd.Stop or KostvListenEnd.Closed or KostvListenEnd.Error)
        {
            return KostvListenWeight.Nothing;
        }

        if (duration is { } total && played >= 0.9 * total)
        {
            return KostvListenWeight.Nothing;
        }

        if (played < KostvListenOutcome.SkippedSeconds)
        {
            var weight = e.Shuffle == true
                ? KostvTasteWeights.EarlySkipShuffle
                : source != null && ByHandSources.Contains(source) ? KostvTasteWeights.EarlySkipByHand : KostvTasteWeights.EarlySkipAutomatic;
            return new KostvListenWeight(weight, false, true);
        }

        return new KostvListenWeight(KostvTasteWeights.MidSkip, false, true);
    }

    /// <summary>The person's taste summed up from all of <paramref name="events"/>, worked out at <paramref name="now"/>.</summary>
    public static KostvTasteSummary Summarize(IEnumerable<KostvMusicEvent> events, DateTimeOffset now)
    {
        var summary = new KostvTasteSummary();
        foreach (var e in events.OrderBy(e => e.At))
        {
            summary.Apply(e);
        }

        summary.DropOldShown(now);
        summary.WorkedOut = now;
        return summary;
    }

    // ---------------------------------------------------------------- the profile

    /// <summary>What the server's plays of a song say: how many, and how lately.</summary>
    private static double JellyfinScore(KostvMusicTrack track, DateTimeOffset now)
    {
        if (track.PlayCount > 0)
        {
            var recency = track.LastPlayed is { } last ? Recency(new DateTimeOffset(DateTime.SpecifyKind(last, DateTimeKind.Utc)), now, 60) : 0;
            return Math.Log2(1 + track.PlayCount) * (0.35 + 0.65 * recency);
        }

        return track.LastPlayed != null ? 0.5 : 0;
    }

    /// <summary>
    /// What the person likes by the new engine: for each song, what the server knows of their
    /// plays mixed with what was learned from <paramref name="summary"/> by how much was learned
    /// (all the server's with no listens at home, all learned with 300 or more; see
    /// <see cref="KostvTasteSummary.Learned"/>); a heart (+3), a playlist
    /// (+2) and a heart on its album (+2) count from the first day. A song skipped too often
    /// (more than 60 %, with margin, of 3 or more) is out unless it has a heart; one with «no me
    /// gusta», or of an artist with it, is out; and the songs out of an artist weigh it down.
    /// Artists and genres add up their songs under a square root, so one album played a lot
    /// doesn't hide the rest; a song's second artist counts half.
    /// </summary>
    public static KostvMusicProfile LearnedProfile(
        IEnumerable<KostvMusicTrack> tracks,
        KostvTasteSummary? summary,
        DateTimeOffset now,
        KostvDislikeSet? dislikes = null)
    {
        summary ??= new KostvTasteSummary();
        dislikes ??= KostvDislikeSet.Empty;
        var learned = summary.Learned;
        var mix = new Dictionary<Guid, double>();
        var background = new Dictionary<Guid, double>();
        var recent = new Dictionary<Guid, double>();
        var heard = new HashSet<Guid>();
        var dropped = new HashSet<Guid>();
        var lastHeard = new Dictionary<Guid, DateTimeOffset>();
        var unique = Unique(tracks);
        foreach (var track in unique)
        {
            var song = summary.SongOf(track.Id);
            DateTimeOffset? last = track.LastPlayed is { } played ? new DateTimeOffset(DateTime.SpecifyKind(played, DateTimeKind.Utc)) : null;
            if (song?.LastHeard is { } learnedLast && (last == null || learnedLast > last))
            {
                last = learnedLast;
            }

            if (track.PlayCount > 0 || last != null)
            {
                heard.Add(track.Id);
            }

            if (last is { } lastAt)
            {
                lastHeard[track.Id] = lastAt;
            }

            if (dislikes.Blocks(track))
            {
                dropped.Add(track.Id);
                continue;
            }

            if (song is { Plays: >= KostvTasteWeights.SkipRateMinPlays } &&
                KostvTasteWeights.SkipRate(song.Skips, song.Plays) > KostvTasteWeights.SkipRateLimit &&
                !track.Favorite)
            {
                dropped.Add(track.Id);
                continue;
            }

            var jellyfin = JellyfinScore(track, now);
            var chosen = (track.Favorite ? KostvTasteWeights.Heart : 0) +
                (song?.Playlist == true ? KostvTasteWeights.Playlist : 0) +
                (summary.FavoriteAlbum(track.Album) ? KostvTasteWeights.FavoriteAlbumOrArtist : 0);
            var longScore = song?.LongAt(now) ?? 0;
            var shortScore = song?.ShortAt(now) ?? 0;
            var factor = dislikes.Factor(track);
            double Blend(double learnedPart) => ((1 - learned) * jellyfin + learned * learnedPart + chosen) * factor;

            Keep(mix, track.Id, Blend((longScore + shortScore) / 2));
            Keep(background, track.Id, Blend(longScore));
            Keep(recent, track.Id, Blend(shortScore));
        }

        // Songs shown many weeks and never played, whether in the library read for the taste or not.
        var penalty = new Dictionary<Guid, double>();
        foreach (var (id, song) in summary.Songs)
        {
            if (!song.Played && song.ShownWeeks > 0 && Guid.TryParseExact(id, "N", out var guid) && !heard.Contains(guid))
            {
                penalty[guid] = KostvTasteWeights.ShownWeek * Math.Min(song.ShownWeeks, KostvTasteWeights.ShownWeeksCap);
            }
        }

        // Kos TV: the songs not at home (heard through Stremfin) weigh their artists and genres by
        // name, learned as the rest (by all the listens, those not at home too: the server knows
        // nothing of them to mix with): none skipped too often, nor out.
        var streamed = new List<KostvStreamedScore>();
        foreach (var (deezerId, song) in summary.Streamed())
        {
            if (dislikes.BlocksStreamed(deezerId, song.Artists) ||
                (song.Plays >= KostvTasteWeights.SkipRateMinPlays && KostvTasteWeights.SkipRate(song.Skips, song.Plays) > KostvTasteWeights.SkipRateLimit))
            {
                continue;
            }

            var factor = summary.LearnedOfAll * dislikes.ArtistFactor(song.Artists![0]);
            var longScore = song.LongAt(now);
            var shortScore = song.ShortAt(now);
            streamed.Add(new KostvStreamedScore(song.Artists!, song.Genres ?? [], factor * (longScore + shortScore) / 2, factor * longScore, factor * shortScore));
        }

        var liked = unique.Where(t => mix.ContainsKey(t.Id)).ToList();
        var genres = Weigh(liked.SelectMany(t => t.Genres.Select(g => (Name: g, Weight: mix[t.Id]))).Concat(StreamedGenres(streamed, s => s.Score)))
            .Select(g => g with { Weight = Math.Sqrt(g.Weight) })
            .ToList();
        return new KostvMusicProfile(
            mix,
            heard,
            dropped,
            genres,
            ArtistsOf(unique, mix, summary, dislikes, a => (a.LongAt(now) + a.ShortAt(now)) / 2, StreamedArtists(streamed, s => s.Score)))
        {
            LastHeard = lastHeard,
            ShownPenalty = penalty,
            Background = ArtistsOf(unique, background, summary, dislikes, a => a.LongAt(now), StreamedArtists(streamed, s => s.Background)),
            Recent = ArtistsOf(unique, recent, summary, dislikes, a => a.ShortAt(now), StreamedArtists(streamed, s => s.Recent))
        };
    }

    private static void Keep(Dictionary<Guid, double> scores, Guid id, double score)
    {
        if (score > 0)
        {
            scores[id] = score;
        }
    }

    /// <summary>
    /// The artists of the songs liked, by the square root of what their songs add up to (half for a
    /// second artist; the songs not at home, <paramref name="streamed"/>, by name), plus the albums
    /// asked for and a heart on the artist, less for their songs with «no me gusta»; none with it.
    /// </summary>
    private static List<KostvWeighted> ArtistsOf(
        List<KostvMusicTrack> tracks,
        IReadOnlyDictionary<Guid, double> scores,
        KostvTasteSummary summary,
        KostvDislikeSet dislikes,
        Func<KostvArtistTaste, double> requests,
        IEnumerable<(string Name, double Weight)> streamed)
    {
        var sums = Weigh(tracks.Where(t => scores.ContainsKey(t.Id)).SelectMany(t => t.Artists.Select((a, i) => (Name: a, Weight: i == 0 ? scores[t.Id] : scores[t.Id] / 2))).Concat(streamed));
        return sums
            .Where(a => !dislikes.BlocksArtist(a.Name))
            .Select(a =>
            {
                var extra = summary.Artists.TryGetValue(Key(a.Name), out var artist)
                    ? requests(artist) + (artist.Favorite == true ? KostvTasteWeights.FavoriteAlbumOrArtist : 0)
                    : 0;
                return a with { Weight = (Math.Sqrt(Math.Max(0, a.Weight)) + extra) * dislikes.ArtistFactor(a.Name) };
            })
            .Where(a => a.Weight > 0)
            .OrderByDescending(a => a.Weight)
            .ThenBy(a => a.Name, StringComparer.Ordinal)
            .ToList();
    }

    // ---------------------------------------------------------------- seeds

    /// <summary>
    /// Up to <see cref="MaxSeeds"/> artists for «Descubrimiento semanal» of <paramref name="week"/>:
    /// of the <see cref="MaxSeedPool"/> the person likes most by their background taste, the
    /// first <see cref="FixedSeeds"/> always and the rest drawn for the week (more often the more
    /// they are liked), so each week it discovers from other sides; never one with «no me gusta».
    /// </summary>
    public static IReadOnlyList<string> Seeds(KostvMusicProfile profile, Guid userId, string week, KostvDislikeSet? dislikes = null)
    {
        dislikes ??= KostvDislikeSet.Empty;
        var pool = (profile.Background ?? profile.Artists)
            .Where(a => a.Weight > 0 && !dislikes.BlocksArtist(a.Name))
            .Take(MaxSeedPool)
            .ToList();
        if (pool.Count <= MaxSeeds)
        {
            return pool.Select(a => a.Name).ToList();
        }

        var random = RandomFor(userId, week, "seeds", string.Empty);
        var drawn = pool.Skip(FixedSeeds)
            .Select(a => (Artist: a, Key: Math.Pow(random.NextDouble(), 1 / Math.Max(0.01, a.Weight))))
            .OrderByDescending(x => x.Key)
            .ThenBy(x => x.Artist.Name, StringComparer.Ordinal)
            .Take(MaxSeeds - FixedSeeds)
            .Select(x => x.Artist);
        return pool.Take(FixedSeeds)
            .Concat(drawn)
            .OrderByDescending(a => a.Weight)
            .ThenBy(a => a.Name, StringComparer.Ordinal)
            .Select(a => a.Name)
            .ToList();
    }

    // ---------------------------------------------------------------- variety

    /// <summary>The songs a mix may have: each once, none with «no me gusta» nor left out by <paramref name="rules"/>.</summary>
    private static List<KostvMusicTrack> Allowed(IEnumerable<KostvMusicTrack> tracks, KostvMixRules rules) =>
        Unique(tracks).Where(t => !rules.Dislikes.Blocks(t) && !rules.Excludes(t.Id)).ToList();

    /// <summary>
    /// When only <paramref name="have"/> of the songs a mix needs (<paramref name="need"/>)
    /// are left, those <paramref name="wanted"/> that were out only for not repeating
    /// (<see cref="KostvMixRules.Readmit"/>), given back a day at a time, the oldest first and what
    /// was heard in the last day last, until there are enough (or none is left out). In the order
    /// of their id, as <see cref="Allowed"/> gives them.
    /// </summary>
    private static List<KostvMusicTrack> Readmitted(IEnumerable<KostvMusicTrack> tracks, KostvMixRules rules, Func<KostvMusicTrack, bool> wanted, int have, int need)
    {
        if (have >= need || rules.Readmit is not { Count: > 0 } tiers)
        {
            return [];
        }

        var candidates = Unique(tracks)
            .Where(t => !rules.Dislikes.Blocks(t) && !rules.Exclude.Contains(t.Id) && rules.Excludes(t.Id) && wanted(t))
            .ToList();
        var back = new List<KostvMusicTrack>();
        for (var given = 1; given <= tiers.Count && have + back.Count < need; given++)
        {
            // The first «given» tiers back: what is in none of the others.
            back = candidates.Where(t => !tiers.Skip(given).Any(s => s.Contains(t.Id))).ToList();
        }

        return back;
    }

    /// <summary>What is left of a new song's odds after the weeks it was shown and not played.</summary>
    private static double Fresh(KostvMusicProfile profile, KostvMusicTrack track) =>
        Math.Max(0.1, 1 - (profile.ShownPenalty?.GetValueOrDefault(track.Id) ?? 0));

    /// <summary>
    /// <paramref name="order"/> with one of each <see cref="ForgottenEvery"/> a forgotten song, when
    /// there are: liked as much as half the others or more, and unheard for a month.
    /// </summary>
    private static List<KostvMusicTrack> WithForgotten(List<KostvMusicTrack> order, KostvMusicProfile profile, DateTimeOffset? now)
    {
        if (now is not { } at || profile.LastHeard is not { } lastHeard || order.Count < ForgottenEvery)
        {
            return order;
        }

        var scores = order.Select(t => profile.Scores.GetValueOrDefault(t.Id)).OrderBy(s => s).ToList();
        var median = scores[scores.Count / 2];
        var forgotten = new Queue<KostvMusicTrack>(order.Where(t =>
            profile.Scores.GetValueOrDefault(t.Id) >= median &&
            lastHeard.TryGetValue(t.Id, out var last) &&
            at - last >= KostvTasteWeights.ForgottenAfter));
        if (forgotten.Count == 0)
        {
            return order;
        }

        var taken = new HashSet<Guid>();
        var result = new List<KostvMusicTrack>(order.Count);
        var rest = order.GetEnumerator();
        while (result.Count < order.Count)
        {
            if (result.Count % ForgottenEvery == ForgottenEvery / 2 && forgotten.TryDequeue(out var old))
            {
                if (taken.Add(old.Id))
                {
                    result.Add(old);
                }

                continue;
            }

            if (!rest.MoveNext())
            {
                break;
            }

            if (taken.Add(rest.Current.Id))
            {
                result.Add(rest.Current);
            }
        }

        return result;
    }

    /// <summary>
    /// Up to <paramref name="size"/> songs of <paramref name="known"/> and <paramref name="near"/>
    /// (each in the order they should go, the first more likely), about
    /// <paramref name="nearShare"/> of them near, by the rules of variety: it starts with the
    /// safest of the known (by <paramref name="safety"/>); never the same artist twice in a row,
    /// at least <see cref="VarietyGap"/> songs between two of one artist, at most
    /// <see cref="VarietyPerBlock"/> of one artist each <see cref="VarietyBlock"/>, never two of
    /// one album in a row; and each next song, of the few next that fit, the closest to the one
    /// before (a genre in common, an artist like theirs). When nothing at all fits, the limit per
    /// 25 gives way first and then the gap, but never the same artist or album twice in a row;
    /// only while the songs are fewer than <paramref name="fillTo"/> (the least a mix is offered
    /// with), as a last resort, one artist may go twice in a row, so a genre of one artist almost
    /// alone (songs for children, say) still has its mix. Never two of one album in a row.
    /// </summary>
    internal static List<KostvMusicTrack> Arrange(
        List<KostvMusicTrack> known,
        List<KostvMusicTrack> near,
        int size,
        double nearShare,
        Func<KostvMusicTrack, double> safety,
        IReadOnlyDictionary<string, IReadOnlyList<string>> similar,
        int fillTo = 0)
    {
        var knownIds = known.Select(t => t.Id).ToHashSet();
        var pools = new[] { known.ToList(), near.Where(t => !knownIds.Contains(t.Id)).ToList() };
        var result = new List<KostvMusicTrack>(size);
        if (size <= 0)
        {
            return result;
        }

        var nearCount = 0;
        if (pools[0].Count > 0)
        {
            var first = pools[0].Select((t, i) => (Track: t, Index: i)).OrderByDescending(x => safety(x.Track)).ThenBy(x => x.Index).First().Index;
            result.Add(pools[0][first]);
            pools[0].RemoveAt(first);
        }
        else if (pools[1].Count > 0)
        {
            result.Add(pools[1][0]);
            pools[1].RemoveAt(0);
            nearCount++;
        }

        // The rules, from all of them to the least: gap and limit per block, gap, not in a row;
        // and, while short of fillTo, only not two of one album in a row.
        (int Gap, bool Cap)[] levels = [(VarietyGap, true), (VarietyGap, false), (1, false), (0, false)];
        while (result.Count > 0 && result.Count < size)
        {
            var wantNear = nearCount < (int)Math.Floor((result.Count + 1) * nearShare);
            int[] order = wantNear ? [1, 0] : [0, 1];
            int pool = -1, index = -1;
            foreach (var (gap, cap) in levels)
            {
                if (gap == 0 && result.Count >= fillTo)
                {
                    break;
                }

                foreach (var p in order)
                {
                    index = Choose(pools[p], result, gap, cap, similar);
                    if (index >= 0)
                    {
                        pool = p;
                        break;
                    }
                }

                if (pool >= 0)
                {
                    break;
                }
            }

            if (pool < 0)
            {
                break;
            }

            result.Add(pools[pool][index]);
            pools[pool].RemoveAt(index);
            if (pool == 1)
            {
                nearCount++;
            }
        }

        return result;
    }

    private static int Choose(List<KostvMusicTrack> pool, List<KostvMusicTrack> result, int gap, bool cap, IReadOnlyDictionary<string, IReadOnlyList<string>> similar)
    {
        var before = result[^1];
        var best = -1;
        var bestCloseness = -1;
        var seen = 0;
        for (var i = 0; i < pool.Count && seen < ChainLookahead; i++)
        {
            if (!Fits(pool[i], result, gap, cap))
            {
                continue;
            }

            seen++;
            var closeness = Closeness(before, pool[i], similar);
            if (closeness > bestCloseness)
            {
                best = i;
                bestCloseness = closeness;
            }
        }

        return best;
    }

    private static bool Fits(KostvMusicTrack track, List<KostvMusicTrack> result, int gap, bool cap)
    {
        var artist = MainArtist(track);
        for (var j = Math.Max(0, result.Count - gap); j < result.Count; j++)
        {
            if (MainArtist(result[j]) == artist)
            {
                return false;
            }
        }

        if (track.Album is { } album && result[^1].Album == album)
        {
            return false;
        }

        if (cap)
        {
            var blockStart = result.Count / VarietyBlock * VarietyBlock;
            var inBlock = 0;
            for (var j = blockStart; j < result.Count; j++)
            {
                if (MainArtist(result[j]) == artist && ++inBlock >= VarietyPerBlock)
                {
                    return false;
                }
            }
        }

        return true;
    }

    /// <summary>How close <paramref name="track"/> is to <paramref name="before"/>: a genre in common, and an artist like theirs.</summary>
    private static int Closeness(KostvMusicTrack before, KostvMusicTrack track, IReadOnlyDictionary<string, IReadOnlyList<string>> similar)
    {
        var closeness = before.Genres.Any(g => track.Genres.Any(h => Key(g) == Key(h))) ? 1 : 0;
        var a = MainArtist(before);
        var b = MainArtist(track);
        if ((similar.TryGetValue(a, out var ofA) && ofA.Any(n => Key(n) == b)) || (similar.TryGetValue(b, out var ofB) && ofB.Any(n => Key(n) == a)))
        {
            closeness++;
        }

        return closeness;
    }

    private static string MainArtist(KostvMusicTrack track) => track.PrimaryArtist is { } a ? Key(a) : track.Id.ToString("N");

    // ---------------------------------------------------------------- explanations and measures

    /// <summary>
    /// The three artists that weigh most in <paramref name="items"/> (by how much the person likes
    /// their songs in it), as most often written, for «Con X, Y y más».
    /// </summary>
    public static IReadOnlyList<string> BecauseOf(IEnumerable<KostvMusicTrack> items, KostvMusicProfile profile) =>
        items
            .Where(t => t.PrimaryArtist != null)
            .GroupBy(t => Key(t.PrimaryArtist!))
            .Select(g => (Name: g.First().PrimaryArtist!.Trim(), Weight: g.Sum(t => profile.Scores.GetValueOrDefault(t.Id) + 0.1), Key: g.Key))
            .OrderByDescending(x => x.Weight)
            .ThenBy(x => x.Key, StringComparer.Ordinal)
            .Take(3)
            .Select(x => x.Name)
            .ToList();

    /// <summary>The first <paramref name="count"/> songs of the mixes as the person meets them: the first of each, then the second...</summary>
    public static IReadOnlyList<Guid> Top(IReadOnlyList<KostvMix> mixes, int count = TopCompared)
    {
        var top = new List<Guid>(count);
        for (var i = 0; top.Count < count && mixes.Any(m => i < m.Items.Count); i++)
        {
            foreach (var mix in mixes)
            {
                if (i < mix.Items.Count && top.Count < count && !top.Contains(mix.Items[i]))
                {
                    top.Add(mix.Items[i]);
                }
            }
        }

        return top;
    }

    /// <summary>When the music day <paramref name="day"/> starts (at <see cref="DayStartHour"/> at home).</summary>
    public static DateTimeOffset DayStart(DateOnly day, TimeZoneInfo zone)
    {
        var local = day.ToDateTime(new TimeOnly(DayStartHour, 0));
        return new DateTimeOffset(local, zone.GetUtcOffset(local));
    }

    /// <summary>How many of <paramref name="top"/> were heard whole on the music day <paramref name="day"/>.</summary>
    public static int Hits(IEnumerable<Guid> top, IEnumerable<KostvMusicEvent> events, DateOnly day, TimeZoneInfo zone)
    {
        var from = DayStart(day, zone);
        var to = DayStart(day.AddDays(1), zone);
        var whole = events
            .Where(e => e.Counts && e.Outcome == KostvListenOutcome.Completed && e.At >= from && e.At < to)
            .Select(e => Guid.TryParse(e.Item, out var id) ? id : Guid.Empty)
            .ToHashSet();
        return top.Distinct().Count(whole.Contains);
    }
}
