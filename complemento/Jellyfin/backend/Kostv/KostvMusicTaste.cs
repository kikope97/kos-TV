using System.Globalization;
using System.Text.Json.Serialization;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: what each thing a person does with a song weighs in what they like, as the plan has
/// it (<c>docs/musica-plan-fundido-y-aprender.md</c>, 3.2). Starting values, to be tuned once
/// measured.
/// </summary>
public static class KostvTasteWeights
{
    /// <summary>Heard: at least half of it or 4 minutes (Last.fm's rule), or to its end.</summary>
    public const double Heard = 1;

    /// <summary>Skipped before 30 s, put on by hand (an album, the search, a list of theirs).</summary>
    public const double EarlySkipByHand = -0.5;

    /// <summary>Skipped before 30 s, in a mix, the radio or ∞ (or from where the app didn't say).</summary>
    public const double EarlySkipAutomatic = -0.3;

    /// <summary>Skipped before 30 s with shuffle on.</summary>
    public const double EarlySkipShuffle = -0.1;

    /// <summary>Skipped between 30 s and half of it.</summary>
    public const double MidSkip = -0.1;

    /// <summary>Played again right after, or taken back to hear a bit again.</summary>
    public const double Replay = 0.5;

    /// <summary>What a listen chosen on purpose (searched for, or picked on its album) adds is this much more.</summary>
    public const double OnPurpose = 1.5;

    /// <summary>A heart on the song, never fading.</summary>
    public const double Heart = 3;

    /// <summary>Added to a playlist.</summary>
    public const double Playlist = 2;

    /// <summary>A heart on its album (to each of its songs) or on the artist (to the artist).</summary>
    public const double FavoriteAlbumOrArtist = 2;

    /// <summary>An album of the artist asked for in Stremfin, to the artist.</summary>
    public const double Request = 1;

    /// <summary>Each week a song was shown in the mixes and never played.</summary>
    public const double ShownWeek = 0.2;

    /// <summary>The most weeks shown and never played that count (so at most −1).</summary>
    public const int ShownWeeksCap = 5;

    /// <summary>A song shown and never played is forgotten when it wasn't shown for this long.</summary>
    public static readonly TimeSpan ShownForgottenAfter = TimeSpan.FromDays(12 * 7);

    /// <summary>The background taste halves every this many days...</summary>
    public const double LongHalfLife = 90;

    /// <summary>...and the taste of now every this many.</summary>
    public const double ShortHalfLife = 14;

    /// <summary>The old engine's half life, kept so it can be worked out from the summary too.</summary>
    public const double OldHalfLife = 30;

    /// <summary>With this many listens kept, the taste is all learned; with none, all the server's.</summary>
    public const int FullyLearnedAt = 300;

    /// <summary>A song skipped more than this share of times (with some margin) is out of the mixes...</summary>
    public const double SkipRateLimit = 0.6;

    /// <summary>...when it was played at least this many times.</summary>
    public const int SkipRateMinPlays = 3;

    /// <summary>A song unheard this long, and liked, is a forgotten one («olvidada»).</summary>
    public static readonly TimeSpan ForgottenAfter = TimeSpan.FromDays(30);

    /// <summary>The share of a song's artist kept for each of its songs with «no me gusta»: 1, 2, and 3 or more.</summary>
    public static double DislikedSongsFactor(int songs) => songs switch
    {
        <= 0 => 1,
        1 => 0.8,
        2 => 0.6,
        _ => 0.25
    };

    /// <summary>The margin-smoothed share of skips: (skips + 1) / (plays + 4).</summary>
    public static double SkipRate(int skips, int plays) => (skips + 1.0) / (plays + 4.0);
}

/// <summary>kOS TV: what one listen says of the person's taste.</summary>
/// <param name="Weight">What it adds or takes away.</param>
/// <param name="Heard">Heard (Last.fm's rule, or to its end).</param>
/// <param name="Skip">A skip (it counts for the share of skips).</param>
public readonly record struct KostvListenWeight(double Weight, bool Heard, bool Skip)
{
    public static readonly KostvListenWeight Nothing = new(0, false, false);

    /// <summary>Whether it counts for the share of skips: heard or skipped (not a stop that says nothing).</summary>
    public bool Tells => Heard || Skip;
}

/// <summary>
/// kOS TV: a song in a person's taste summary: what its listens add up to, halving two ways (and
/// the old engine's way), as of <see cref="At"/>; how many times it was played and skipped;
/// when it was last heard; whether it was added to a playlist; and how many weeks it was shown
/// without being played. Short names: there is one per song.
/// </summary>
public sealed class KostvSongTaste
{
    /// <summary>When the sums below are as of.</summary>
    [JsonPropertyName("t")]
    public DateTimeOffset At { get; set; }

    [JsonPropertyName("l")]
    public double Long { get; set; }

    [JsonPropertyName("s")]
    public double Short { get; set; }

    /// <summary>The old engine's score (completed +1, stopped +0.4, skipped −0.6, halving in 30 days).</summary>
    [JsonPropertyName("o")]
    public double Old { get; set; }

    /// <summary>Listens that tell (heard or skipped).</summary>
    [JsonPropertyName("n")]
    public int Plays { get; set; }

    [JsonPropertyName("k")]
    public int Skips { get; set; }

    /// <summary>The old engine's counts: completed, skipped and stopped.</summary>
    [JsonPropertyName("c")]
    public int OldCompleted { get; set; }

    [JsonPropertyName("x")]
    public int OldSkipped { get; set; }

    [JsonPropertyName("p")]
    public int OldStopped { get; set; }

    /// <summary>When it was last played (any listen that counts).</summary>
    [JsonPropertyName("h")]
    public DateTimeOffset? LastHeard { get; set; }

    [JsonPropertyName("pl")]
    public bool Playlist { get; set; }

    /// <summary>
    /// The different weeks it was shown in the mixes or the moment's mix (ISO, yyyy-Www), up to
    /// <see cref="KostvTasteWeights.ShownWeeksCap"/>: more don't weigh more. Kept as weeks, not
    /// counted, so a week told twice or out of order counts once.
    /// </summary>
    [JsonPropertyName("sw")]
    public List<string>? Weeks { get; set; }

    /// <summary>How many weeks it was shown and not played (see <see cref="Weeks"/>).</summary>
    [JsonIgnore]
    public int ShownWeeks => Weeks?.Count ?? 0;

    [JsonPropertyName("ls")]
    public DateTimeOffset? LastShown { get; set; }

    /// <summary>
    /// Kos TV: of a song not at home (keyed <c>stremfin:&lt;DeezerId&gt;</c>), its artists by name,
    /// the main one first, as its last listen said: there is no song of the library to read them
    /// from. Null for a song at home.
    /// </summary>
    [JsonPropertyName("a")]
    public List<string>? Artists { get; set; }

    /// <summary>Kos TV: of a song not at home, its genres by name, as its last listen said.</summary>
    [JsonPropertyName("g")]
    public List<string>? Genres { get; set; }

    [JsonIgnore]
    public bool Played => LastHeard != null || Playlist;

    public double LongAt(DateTimeOffset now) => Long * KostvDecay.Factor(At, now, KostvTasteWeights.LongHalfLife);

    public double ShortAt(DateTimeOffset now) => Short * KostvDecay.Factor(At, now, KostvTasteWeights.ShortHalfLife);

    public double OldAt(DateTimeOffset now) => Old * KostvDecay.Factor(At, now, KostvTasteWeights.OldHalfLife);

    public KostvSongTaste Copy()
    {
        var copy = (KostvSongTaste)MemberwiseClone();
        copy.Weeks = Weeks?.ToList();
        copy.Artists = Artists?.ToList();
        copy.Genres = Genres?.ToList();
        return copy;
    }

    /// <summary>Adds what happened at <paramref name="at"/>, the sums kept as of the latest time seen.</summary>
    public void Add(DateTimeOffset at, double longWeight, double shortWeight, double oldWeight)
    {
        if (At == default)
        {
            At = at;
        }

        if (at > At)
        {
            Long *= KostvDecay.Factor(At, at, KostvTasteWeights.LongHalfLife);
            Short *= KostvDecay.Factor(At, at, KostvTasteWeights.ShortHalfLife);
            Old *= KostvDecay.Factor(At, at, KostvTasteWeights.OldHalfLife);
            At = at;
        }

        Long += longWeight * KostvDecay.Factor(at, At, KostvTasteWeights.LongHalfLife);
        Short += shortWeight * KostvDecay.Factor(at, At, KostvTasteWeights.ShortHalfLife);
        Old += oldWeight * KostvDecay.Factor(at, At, KostvTasteWeights.OldHalfLife);
    }
}

/// <summary>kOS TV: an artist in a person's taste summary: albums asked for, and the heart on it.</summary>
public sealed class KostvArtistTaste
{
    [JsonPropertyName("t")]
    public DateTimeOffset At { get; set; }

    /// <summary>Albums asked for, halving like the background taste.</summary>
    [JsonPropertyName("l")]
    public double Long { get; set; }

    /// <summary>Albums asked for, halving like the taste of now.</summary>
    [JsonPropertyName("s")]
    public double Short { get; set; }

    [JsonPropertyName("f")]
    public bool? Favorite { get; set; }

    [JsonPropertyName("fa")]
    public DateTimeOffset? FavoriteAt { get; set; }

    public double LongAt(DateTimeOffset now) => Long * KostvDecay.Factor(At, now, KostvTasteWeights.LongHalfLife);

    public double ShortAt(DateTimeOffset now) => Short * KostvDecay.Factor(At, now, KostvTasteWeights.ShortHalfLife);

    public KostvArtistTaste Copy() => (KostvArtistTaste)MemberwiseClone();

    public void AddRequest(DateTimeOffset at)
    {
        if (At == default)
        {
            At = at;
        }

        if (at > At)
        {
            Long *= KostvDecay.Factor(At, at, KostvTasteWeights.LongHalfLife);
            Short *= KostvDecay.Factor(At, at, KostvTasteWeights.ShortHalfLife);
            At = at;
        }

        Long += KostvTasteWeights.Request * KostvDecay.Factor(at, At, KostvTasteWeights.LongHalfLife);
        Short += KostvTasteWeights.Request * KostvDecay.Factor(at, At, KostvTasteWeights.ShortHalfLife);
    }
}

/// <summary>kOS TV: a heart on an album, and when it was put on or taken off.</summary>
public sealed class KostvFavoriteMark
{
    [JsonPropertyName("f")]
    public bool Favorite { get; set; }

    [JsonPropertyName("t")]
    public DateTimeOffset At { get; set; }
}

internal static class KostvDecay
{
    /// <summary>What is left at <paramref name="to"/> of something at <paramref name="from"/>, halving every <paramref name="halfLifeDays"/>.</summary>
    public static double Factor(DateTimeOffset from, DateTimeOffset to, double halfLifeDays) =>
        Math.Pow(0.5, Math.Max(0, (to - from).TotalDays) / halfLifeDays);
}

/// <summary>
/// kOS TV: what a person's listens and other signals add up to, song by song (and artist and
/// album), kept in their folder (<c>taste.json</c>) and brought up to date as each line is
/// appended, so the taste needn't read two years of listens each day. Worked out in full again
/// once a day. The same lines in the same order always make the same summary.
/// </summary>
public sealed class KostvTasteSummary
{
    // 2: the weeks a song was shown are kept as weeks (see KostvSongTaste.Weeks); a summary of
    // before is worked out again.
    // 3: the listens of songs at home are counted apart (HomeListens); worked out again.
    public const int CurrentVersion = 3;

    [JsonPropertyName("v")]
    public int Version { get; set; } = CurrentVersion;

    /// <summary>The listens that count (see <see cref="KostvMusicEvent.Counts"/>).</summary>
    [JsonPropertyName("listens")]
    public int Listens { get; set; }

    /// <summary>
    /// Kos TV: of <see cref="Listens"/>, those of songs at home: what <see cref="Learned"/> is
    /// counted by, so listens not at home (through Stremfin) don't take the weight off what the
    /// server knows of the songs at home.
    /// </summary>
    [JsonPropertyName("home")]
    public int HomeListens { get; set; }

    /// <summary>When it was last worked out in full.</summary>
    [JsonPropertyName("full")]
    public DateTimeOffset? WorkedOut { get; set; }

    /// <summary>By song, without dashes; a song not at home, as <c>stremfin:&lt;DeezerId&gt;</c>.</summary>
    [JsonPropertyName("songs")]
    public Dictionary<string, KostvSongTaste> Songs { get; set; } = new(StringComparer.Ordinal);

    /// <summary>By artist name, as matched (see <see cref="KostvMusicEngine.Key"/>).</summary>
    [JsonPropertyName("artists")]
    public Dictionary<string, KostvArtistTaste> Artists { get; set; } = new(StringComparer.Ordinal);

    /// <summary>Hearts on albums, by album without dashes.</summary>
    [JsonPropertyName("albums")]
    public Dictionary<string, KostvFavoriteMark> Albums { get; set; } = new(StringComparer.Ordinal);

    /// <summary>
    /// How much of the taste of the songs at home is learned rather than the server's: 0 with no
    /// listens at home, 1 with 300 or more (those not at home don't count, see <see cref="HomeListens"/>).
    /// </summary>
    [JsonIgnore]
    public double Learned => Math.Min(1, HomeListens / (double)KostvTasteWeights.FullyLearnedAt);

    /// <summary>
    /// Kos TV: how much is learned of all the listens, at home or not (0 to 1, as
    /// <see cref="Learned"/>): what the songs not at home weigh by, as nothing else is known of them.
    /// </summary>
    [JsonIgnore]
    public double LearnedOfAll => Math.Min(1, Listens / (double)KostvTasteWeights.FullyLearnedAt);

    public KostvSongTaste? SongOf(Guid id) => Songs.GetValueOrDefault(id.ToString("N"));

    /// <summary>
    /// A copy of it all, to read while it goes on being brought up to date (under the person's
    /// lock) as listens are noted.
    /// </summary>
    public KostvTasteSummary Copy() => new()
    {
        Version = Version,
        Listens = Listens,
        HomeListens = HomeListens,
        WorkedOut = WorkedOut,
        Songs = Songs.ToDictionary(s => s.Key, s => s.Value.Copy(), StringComparer.Ordinal),
        Artists = Artists.ToDictionary(a => a.Key, a => a.Value.Copy(), StringComparer.Ordinal),
        Albums = Albums.ToDictionary(a => a.Key, a => new KostvFavoriteMark { Favorite = a.Value.Favorite, At = a.Value.At }, StringComparer.Ordinal)
    };

    /// <summary>
    /// As read from a file: what is missing in it (a list written as null, an entry null) made
    /// empty, so nothing that reads it fails.
    /// </summary>
    public KostvTasteSummary Normalized()
    {
        Songs = new Dictionary<string, KostvSongTaste>((Songs ?? []).Where(s => s.Value != null), StringComparer.Ordinal);
        Artists = new Dictionary<string, KostvArtistTaste>((Artists ?? []).Where(a => a.Value != null), StringComparer.Ordinal);
        Albums = new Dictionary<string, KostvFavoriteMark>((Albums ?? []).Where(a => a.Value != null), StringComparer.Ordinal);
        foreach (var song in Songs.Values)
        {
            song.Weeks = song.Weeks?.Where(w => !string.IsNullOrEmpty(w)).Distinct(StringComparer.Ordinal).ToList();
            song.Artists = song.Artists?.Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
            song.Genres = song.Genres?.Where(g => !string.IsNullOrWhiteSpace(g)).ToList();
        }

        return this;
    }

    /// <summary>Whether the album <paramref name="album"/> has a heart.</summary>
    public bool FavoriteAlbum(Guid? album) => album is { } id && Albums.TryGetValue(id.ToString("N"), out var mark) && mark.Favorite;

    private KostvSongTaste Song(string id)
    {
        if (!Songs.TryGetValue(id, out var song))
        {
            Songs[id] = song = new KostvSongTaste();
        }

        return song;
    }

    private KostvArtistTaste Artist(string key)
    {
        if (!Artists.TryGetValue(key, out var artist))
        {
            Artists[key] = artist = new KostvArtistTaste();
        }

        return artist;
    }

    /// <summary>Adds what <paramref name="e"/> says.</summary>
    public void Apply(KostvMusicEvent e)
    {
        switch (e.Type)
        {
            case KostvMusicEvent.ListenType:
                ApplyListen(e);
                break;
            case KostvMusicEvent.FavoriteType when e.Favorite is { } on:
                if (e.Kind == KostvMusicEvent.AlbumKind && NormalId(e.Item) is { } album)
                {
                    if (!Albums.TryGetValue(album, out var mark) || mark.At <= e.At)
                    {
                        Albums[album] = new KostvFavoriteMark { Favorite = on, At = e.At };
                    }
                }
                else if (e.Kind == KostvMusicEvent.ArtistKind && e.Artists is [{ } name, ..] && KostvMusicEngine.Key(name) is { Length: > 0 } key)
                {
                    var artist = Artist(key);
                    if (artist.FavoriteAt is not { } at || at <= e.At)
                    {
                        artist.Favorite = on;
                        artist.FavoriteAt = e.At;
                    }
                }

                break;
            case KostvMusicEvent.PlaylistAddType:
                foreach (var item in e.Items ?? [])
                {
                    if (NormalId(item) is { } id)
                    {
                        Song(id).Playlist = true;
                    }
                }

                break;
            case KostvMusicEvent.RequestType when !string.IsNullOrWhiteSpace(e.ArtistName):
                Artist(KostvMusicEngine.Key(e.ArtistName)).AddRequest(e.At);
                break;
            case KostvMusicEvent.ShownType:
                var shown = e.Surface switch
                {
                    KostvMusicEvent.MixesSurface => (e.Mixes ?? []).SelectMany(m => m?.Items ?? []),
                    KostvMusicEvent.MomentSurface => e.Items ?? [],
                    _ => []
                };
                var week = WeekOf(e);
                foreach (var item in shown)
                {
                    if (NormalId(item) is not { } id)
                    {
                        continue;
                    }

                    // Only of songs not played: the others are known anyway, and this keeps it small.
                    if (Songs.TryGetValue(id, out var known) && known.Played)
                    {
                        continue;
                    }

                    var song = Song(id);
                    song.Weeks ??= [];
                    if (song.Weeks.Count < KostvTasteWeights.ShownWeeksCap && !song.Weeks.Contains(week))
                    {
                        song.Weeks.Add(week);
                    }

                    song.LastShown = song.LastShown is { } last && last > e.At ? last : e.At;
                }

                break;
        }
    }

    private void ApplyListen(KostvMusicEvent e)
    {
        // Kos TV: a song not at home counts too, by its Deezer id, with its artists and genres by name.
        var deezerId = KostvMusicEvent.DeezerIdOf(e.Item);
        if (!e.Counts || (deezerId != null ? KostvMusicEvent.StreamedItem(deezerId) : NormalId(e.Item)) is not { } id)
        {
            return;
        }

        Listens++;
        if (deezerId == null)
        {
            HomeListens++;
        }

        var song = Song(id);
        if (deezerId != null)
        {
            var artists = (e.Artists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).Select(a => a.Trim()).ToList();
            var genres = (e.Genres ?? []).Where(g => !string.IsNullOrWhiteSpace(g)).Select(g => g.Trim()).ToList();
            // As the latest listen says, but not forgotten by one that says nothing.
            song.Artists = artists.Count > 0 ? artists : song.Artists;
            song.Genres = genres.Count > 0 ? genres : song.Genres;
        }

        var weight = KostvMusicEngine.WeighListen(e);
        var old = e.Outcome switch
        {
            KostvListenOutcome.Completed => 1,
            KostvListenOutcome.Skipped => -0.6,
            _ => 0.4
        };
        switch (e.Outcome)
        {
            case KostvListenOutcome.Completed:
                song.OldCompleted++;
                break;
            case KostvListenOutcome.Skipped:
                song.OldSkipped++;
                break;
            default:
                song.OldStopped++;
                break;
        }

        song.Add(e.At, weight.Weight, weight.Weight, old);
        if (weight.Tells)
        {
            song.Plays++;
        }

        if (weight.Skip)
        {
            song.Skips++;
        }

        song.LastHeard = song.LastHeard is { } last && last > e.At ? last : e.At;
        // Played now: what was noted as shown and not played no longer applies.
        song.Weeks = null;
        song.LastShown = null;
    }

    /// <summary>Drops the songs only shown, and not lately (they would only grow the file).</summary>
    public void DropOldShown(DateTimeOffset now)
    {
        foreach (var (id, song) in Songs.Where(s => !s.Value.Played && s.Value.LastShown is { } at && now - at > KostvTasteWeights.ShownForgottenAfter).ToList())
        {
            Songs.Remove(id);
        }
    }

    /// <summary>The listens of each song as the old engine counts them (see <see cref="KostvMusicEngine.Listens"/>).</summary>
    public Dictionary<Guid, KostvTrackListens> OldListens(DateTimeOffset now)
    {
        var listens = new Dictionary<Guid, KostvTrackListens>();
        foreach (var (id, song) in Songs)
        {
            if (song.OldCompleted + song.OldSkipped + song.OldStopped > 0 && Guid.TryParseExact(id, "N", out var guid))
            {
                listens[guid] = new KostvTrackListens
                {
                    Completed = song.OldCompleted,
                    Skipped = song.OldSkipped,
                    Stopped = song.OldStopped,
                    Score = song.OldAt(now)
                };
            }
        }

        return listens;
    }

    /// <summary>
    /// Kos TV: the songs not at home heard (heard through Stremfin), by their Deezer id: they count
    /// for their artists and genres by name, and are never read from the library nor put in a mix.
    /// </summary>
    public IEnumerable<(string DeezerId, KostvSongTaste Song)> Streamed() =>
        Songs
            .Select(s => (DeezerId: KostvMusicEvent.DeezerIdOf(s.Key), Song: s.Value))
            .Where(s => s.DeezerId != null && s.Song.Artists is { Count: > 0 })
            .OrderBy(s => s.DeezerId, StringComparer.Ordinal)
            .Select(s => (s.DeezerId!, s.Song));

    /// <summary>The songs to read from the library for the taste: those played or added to a list.</summary>
    public IEnumerable<Guid> PlayedSongs() =>
        Songs.Where(s => s.Value.Played).Select(s => Guid.TryParseExact(s.Key, "N", out var id) ? id : Guid.Empty).Where(id => id != Guid.Empty);

    private static string? NormalId(string? id) => Guid.TryParse(id, out var guid) && guid != Guid.Empty ? guid.ToString("N") : null;

    private static string WeekOf(KostvMusicEvent e)
    {
        var date = DateTime.TryParseExact(e.Day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day) ? day : e.At.UtcDateTime;
        return string.Create(CultureInfo.InvariantCulture, $"{ISOWeek.GetYear(date):0000}-W{ISOWeek.GetWeekOfYear(date):00}");
    }
}

/// <summary>
/// kOS TV: what a person said «no me gusta» to, as the engine uses it: songs out, artists out, and
/// the artists of the songs out weighing less (three or more songs, much less).
/// </summary>
public sealed class KostvDislikeSet
{
    public static readonly KostvDislikeSet Empty = new([], [], new Dictionary<string, int>());

    public KostvDislikeSet(
        IEnumerable<Guid> songs,
        IEnumerable<string> artists,
        IReadOnlyDictionary<string, int> songsPerArtist,
        IEnumerable<Guid>? artistIds = null,
        IEnumerable<string>? streamedSongs = null)
    {
        Songs = songs.ToHashSet();
        Artists = artists.Select(KostvMusicEngine.Key).Where(k => k.Length > 0).ToHashSet(StringComparer.Ordinal);
        SongsPerArtist = songsPerArtist;
        ArtistIds = (artistIds ?? []).Where(id => id != Guid.Empty).ToHashSet();
        StreamedSongs = (streamedSongs ?? []).Where(KostvMusicEvent.IsDeezerId).ToHashSet(StringComparer.Ordinal);
    }

    public IReadOnlySet<Guid> Songs { get; }

    /// <summary>Kos TV: the songs out that are not at home, by their Deezer id.</summary>
    public IReadOnlySet<string> StreamedSongs { get; }

    /// <summary>The artists out, as matched (see <see cref="KostvMusicEngine.Key"/>).</summary>
    public IReadOnlySet<string> Artists { get; }

    /// <summary>How many songs out there are of each artist, as matched.</summary>
    public IReadOnlyDictionary<string, int> SongsPerArtist { get; }

    /// <summary>The artists out, by their id at home (so one renamed since is still out).</summary>
    public IReadOnlySet<Guid> ArtistIds { get; }

    public bool IsEmpty => Songs.Count == 0 && Artists.Count == 0 && ArtistIds.Count == 0 && StreamedSongs.Count == 0;

    /// <summary>Whether <paramref name="track"/> is out: the song, or any of its artists.</summary>
    public bool Blocks(KostvMusicTrack track) => Songs.Contains(track.Id) || track.Artists.Any(BlocksArtist);

    /// <summary>Whether the song not at home <paramref name="deezerId"/> is out: the song, or any of its <paramref name="artists"/>.</summary>
    public bool BlocksStreamed(string deezerId, IEnumerable<string>? artists) =>
        StreamedSongs.Contains(deezerId) || (artists ?? []).Any(BlocksArtist);

    public bool BlocksArtist(string? name) => name != null && Artists.Contains(KostvMusicEngine.Key(name));

    /// <summary>Whether the artist <paramref name="id"/> (or, by name, <paramref name="name"/>) is out.</summary>
    public bool BlocksArtist(Guid? id, string? name) => (id is { } artistId && ArtistIds.Contains(artistId)) || BlocksArtist(name);

    /// <summary>What is kept of the weight of the artist <paramref name="name"/> for their songs out.</summary>
    public double ArtistFactor(string? name) =>
        name == null ? 1 : KostvTasteWeights.DislikedSongsFactor(SongsPerArtist.GetValueOrDefault(KostvMusicEngine.Key(name)));

    /// <summary>What is kept of a song's weight for the songs out of its main artist.</summary>
    public double Factor(KostvMusicTrack track) => ArtistFactor(track.PrimaryArtist);

    /// <summary>
    /// The set from what the person said, as kept (see <see cref="KostvDislikes"/>), with the names
    /// the artists out have at home now (<paramref name="artistNamesNow"/>), when renamed since.
    /// </summary>
    public static KostvDislikeSet Of(KostvDislikes? dislikes, IEnumerable<string>? artistNamesNow = null)
    {
        if (dislikes == null || (dislikes.Songs.Count == 0 && dislikes.Artists.Count == 0))
        {
            return Empty;
        }

        var perArtist = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var song in dislikes.Songs)
        {
            if (!string.IsNullOrWhiteSpace(song.Artist))
            {
                var key = KostvMusicEngine.Key(song.Artist);
                perArtist[key] = perArtist.GetValueOrDefault(key) + 1;
            }
        }

        return new KostvDislikeSet(
            dislikes.Songs.Select(s => Guid.TryParse(s.Id, out var id) ? id : Guid.Empty).Where(id => id != Guid.Empty),
            dislikes.Artists.Select(a => a.Name).OfType<string>().Concat(artistNamesNow ?? []),
            perArtist,
            dislikes.Artists.Select(a => Guid.TryParse(a.Id, out var id) ? id : Guid.Empty),
            dislikes.Songs.Where(s => string.IsNullOrEmpty(s.Id)).Select(s => s.DeezerId).OfType<string>());
    }
}

/// <summary>
/// kOS TV: a song with «no me gusta», with what is needed to show it in the list: one at home
/// (<see cref="Id"/>), or one not at home (<see cref="DeezerId"/>, and <see cref="Id"/> null).
/// </summary>
public sealed class KostvDislikedSong
{
    /// <summary>The song at home, without dashes; null for one not at home.</summary>
    [JsonPropertyName("id")]
    public string? Id { get; set; }

    /// <summary>Kos TV: the Deezer id of a song not at home, heard through Stremfin; null for one at home.</summary>
    [JsonPropertyName("deezerId")]
    public string? DeezerId { get; set; }

    /// <summary>What tells it from the others: its id at home, or <c>stremfin:&lt;DeezerId&gt;</c>.</summary>
    [JsonIgnore]
    public string Key => !string.IsNullOrEmpty(Id) ? Id : KostvMusicEvent.StreamedItem(DeezerId ?? string.Empty);

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("artist")]
    public string? Artist { get; set; }

    [JsonPropertyName("artistId")]
    public string? ArtistId { get; set; }

    [JsonPropertyName("albumId")]
    public string? AlbumId { get; set; }

    [JsonPropertyName("at")]
    public DateTimeOffset At { get; set; }
}

/// <summary>kOS TV: an artist with «no me pongas a este artista».</summary>
public sealed class KostvDislikedArtist
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonPropertyName("at")]
    public DateTimeOffset At { get; set; }
}

/// <summary>
/// kOS TV: what a person doesn't want to hear (<c>dislikes.json</c>): apart from their listens,
/// as it is their choice and not something learned, so it stays with Learn off and when the
/// listens are deleted.
/// </summary>
public sealed class KostvDislikes
{
    [JsonPropertyName("songs")]
    public List<KostvDislikedSong> Songs { get; set; } = [];

    [JsonPropertyName("artists")]
    public List<KostvDislikedArtist> Artists { get; set; } = [];

    /// <summary>
    /// As read from a file: a list written as null made empty, and entries null or without an id
    /// (at home, or a Deezer id for a song not at home) left out.
    /// </summary>
    public KostvDislikes Normalized()
    {
        Songs = (Songs ?? []).Where(s => s != null && (!string.IsNullOrEmpty(s.Id) || KostvMusicEvent.IsDeezerId(s.DeezerId))).ToList();
        Artists = (Artists ?? []).Where(a => a != null && !string.IsNullOrEmpty(a.Id)).ToList();
        return this;
    }

    public KostvDislikes Copy() => new()
    {
        Songs = Songs.Select(s => new KostvDislikedSong { Id = s.Id, DeezerId = s.DeezerId, Name = s.Name, Artist = s.Artist, ArtistId = s.ArtistId, AlbumId = s.AlbumId, At = s.At }).ToList(),
        Artists = Artists.Select(a => new KostvDislikedArtist { Id = a.Id, Name = a.Name, At = a.At }).ToList()
    };
}

/// <summary>kOS TV: what came of taking one off a person's «no me gusta» list.</summary>
public enum KostvDislikeRemoval
{
    /// <summary>It wasn't on it.</summary>
    NotThere,

    /// <summary>Taken off, and stored so.</summary>
    Removed,

    /// <summary>It could not be stored without it: it stays on it.</summary>
    NotStored
}

/// <summary>
/// kOS TV: what a mix may not have, whatever engine scores it: songs with «no me gusta» (or of
/// artists with it), songs left out (<see cref="Exclude"/>) and songs not to repeat
/// (<see cref="Readmit"/>: those of the mixes of each day before, the oldest day first, and those
/// heard in the last day, last), given back in that order only when what the person knows isn't
/// enough for a mix without them; and when it is, to tell the forgotten songs.
/// </summary>
public sealed record KostvMixRules(
    IReadOnlySet<Guid> Exclude,
    KostvDislikeSet Dislikes,
    DateTimeOffset? Now = null,
    IReadOnlyList<IReadOnlySet<Guid>>? Readmit = null)
{
    public static readonly KostvMixRules None = new(new HashSet<Guid>(), KostvDislikeSet.Empty);

    /// <summary>Whether <paramref name="id"/> is left out, or not to repeat.</summary>
    public bool Excludes(Guid id) => Exclude.Contains(id) || (Readmit?.Any(s => s.Contains(id)) ?? false);
}

/// <summary>
/// kOS TV: which engine scores the music (the plugin's setting <c>KostvMusicEngine</c>):
/// <c>actual</c>, the one so far (by default); <c>nuevo</c>, the one that learns from every
/// signal; or <c>alterno</c>, one day each (the even days of the home, counted from the first,
/// the new one).
/// </summary>
public static class KostvMusicEngineMode
{
    public const string Current = "actual";
    public const string New = "nuevo";
    public const string Alternate = "alterno";

    /// <summary>The mode as set; <see cref="Current"/> when unset or unknown.</summary>
    public static string Normalize(string? mode) => mode?.Trim().ToLowerInvariant() switch
    {
        New => New,
        Alternate => Alternate,
        _ => Current
    };

    /// <summary>Whether the new engine scores the music of <paramref name="day"/>.</summary>
    public static bool UsesNew(string? mode, DateOnly day) => Normalize(mode) switch
    {
        New => true,
        Alternate => day.DayNumber % 2 == 0,
        _ => false
    };
}
