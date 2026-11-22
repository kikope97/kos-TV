using System.Globalization;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: why a song is in a station, as the route says it (<c>Why</c>).</summary>
public static class KostvStationWhy
{
    /// <summary>Heard together with the seed by people in general (ListenBrainz), and of its style.</summary>
    public const string ListenBrainz = "listenbrainz";

    /// <summary>Among the most heard of the artists like the seed's (Deezer).</summary>
    public const string Style = "style";

    /// <summary>From the radio of the seed's artist on Deezer.</summary>
    public const string Deezer = "deezer";

    /// <summary>Like the seed by Last.fm (only with a key in the panel), and of its style.</summary>
    public const string LastFm = "lastfm";
}

/// <summary>kOS TV: where a station came from, as the route says it (<c>Source</c>).</summary>
public static class KostvStationSource
{
    public const string ListenBrainz = "listenbrainz";
    public const string LastFm = "lastfm";

    /// <summary>The sources by listening didn't answer (or in time): what there was, maybe nothing.</summary>
    public const string Fallback = "fallback";
}

/// <summary>
/// kOS TV: a song of a station as worked out from outside, for the whole home: who it is, why,
/// and its Deezer id once known (so it can sound when it isn't at home). Whether it is at home,
/// and whether the person may hear it, is seen on each request.
/// </summary>
public sealed class KostvStationEntry
{
    public string Title { get; set; } = string.Empty;

    public string Artist { get; set; } = string.Empty;

    public string? Album { get; set; }

    /// <summary>Its recording on MusicBrainz, when known.</summary>
    public string? Mbid { get; set; }

    public string? DeezerId { get; set; }

    /// <summary>Whether it is explicit, as Deezer says; null when Deezer wasn't asked.</summary>
    public bool? Explicit { get; set; }

    /// <summary>See <see cref="KostvStationWhy"/>.</summary>
    public string Why { get; set; } = KostvStationWhy.Deezer;

    public double Score { get; set; }

    [JsonIgnore]
    public IReadOnlyList<string> Isrcs { get; set; } = [];

    public KostvStationEntry Copy() => (KostvStationEntry)MemberwiseClone();
}

/// <summary>kOS TV: a song as one of the outside sources gives it.</summary>
public sealed record KostvStationTrack(
    string Title,
    string Artist,
    string? Album = null,
    string? Mbid = null,
    string? DeezerId = null,
    bool? Explicit = null,
    double Score = 0,
    string? ArtistDeezerId = null);

/// <summary>kOS TV: what MusicBrainz (through ListenBrainz) knows of a recording.</summary>
public sealed record KostvStationRecordingInfo(
    int? Year,
    IReadOnlyList<string> Isrcs,
    IReadOnlyList<string> ArtistMbids,
    IReadOnlySet<string> ArtistTags);

/// <summary>
/// kOS TV: everything the station of a seed is made of, as fetched (each part may be missing).
/// </summary>
public sealed class KostvStationInputs
{
    public required string SeedTitle { get; init; }

    public required string SeedArtist { get; init; }

    /// <summary>The month it is at home (Christmas songs only in December).</summary>
    public int Month { get; init; } = 1;

    public int? SeedYear { get; set; }

    /// <summary>The styles of the seed's artist on MusicBrainz (its tags), without the generic ones.</summary>
    public IReadOnlySet<string> SeedArtistTags { get; set; } = new HashSet<string>();

    /// <summary>Songs heard together with the seed (ListenBrainz, both datasets), by score (1 the most).</summary>
    public IReadOnlyList<KostvStationTrack> ListenBrainz { get; set; } = [];

    /// <summary>Songs like the seed by Last.fm (only with a key), by match.</summary>
    public IReadOnlyList<KostvStationTrack> LastFm { get; set; } = [];

    /// <summary>What MusicBrainz knows of the candidates, by their recording id.</summary>
    public IReadOnlyDictionary<string, KostvStationRecordingInfo> Recordings { get; set; } = new Dictionary<string, KostvStationRecordingInfo>();

    /// <summary>The artists Deezer relates to the seed's, in its order.</summary>
    public IReadOnlyList<string> Related { get; set; } = [];

    /// <summary>The artists Deezer relates to those (the first few of them).</summary>
    public IReadOnlyCollection<string> RelatedOfRelated { get; set; } = [];

    /// <summary>The artists ListenBrainz finds like the seed's.</summary>
    public IReadOnlyCollection<string> SimilarArtists { get; set; } = [];

    /// <summary>The radio of the seed's artist on Deezer.</summary>
    public IReadOnlyList<KostvStationTrack> Radio { get; set; } = [];

    /// <summary>The seed artist's most heard songs on Deezer.</summary>
    public IReadOnlyList<KostvStationTrack> SeedArtistTop { get; set; } = [];

    /// <summary>The most heard songs of each related artist, in the order of <see cref="Related"/>.</summary>
    public IReadOnlyList<IReadOnlyList<KostvStationTrack>> RelatedTop { get; set; } = [];
}

/// <summary>
/// kOS TV: the station of a song (<c>docs/musica-radio.md</c>, «Contrato de la emisora», tuned
/// with the cold test of phase 0): songs heard together with it by people in general, only of
/// its style, filled with the radio of its artist and the most heard of the artists like it;
/// then, for each person, the variety rules. Nothing here is of the home's history.
/// </summary>
public static class KostvStationRecipe
{
    /// <summary>Fewer candidates by listening than these pass the style filter: Deezer's radio leads.</summary>
    public const int LeadThreshold = 10;

    /// <summary>The most songs of one artist in any run of this many.</summary>
    public const int VarietyWindow = 25;

    /// <summary>... and how many.</summary>
    public const int PerArtistInWindow = 2;

    /// <summary>The seed's artist comes back about every this many songs.</summary>
    public const int SeedArtistEvery = 8;

    /// <summary>Years apart from the seed after which a candidate weighs less.</summary>
    public const int EraYears = 15;

    /// <summary>What a candidate far in time from the seed keeps of its score.</summary>
    public const double EraFactor = 0.6;

    /// <summary>... and one very far (twice <see cref="EraYears"/> or more).</summary>
    public const double FarEraFactor = 0.4;

    /// <summary>How many related artists' most heard songs fill in, and how many of each.</summary>
    public const int RelatedTopArtists = 12;

    public const int RelatedTopEach = 5;

    // Tags of MusicBrainz too broad to tell a style (or not of style at all).
    private static readonly HashSet<string> GenericTags = new(StringComparer.Ordinal)
    {
        "pop", "rock", "latin", "latino", "spanish", "espanol", "español", "english", "seen live",
        "male vocalists", "female vocalists", "singer songwriter", "singer-songwriter", "world",
        "international", "dance", "electronic", "music", "favorites", "favourites", "usa", "american",
        "british", "uk", "spain", "mexico", "argentina", "colombia", "puerto rico", "male vocalist",
        "female vocalist", "vocal", "soundtrack", "classic", "female vocals", "male vocals", "top 5",
        "top 10", "top 40", "top 100"
    };

    private static readonly Regex DecadeTag = new(@"^(\d0s|\d{4}s|\d{2}s|\d{4})$", RegexOptions.CultureInvariant);

    // What makes a title another version of a song, said in its brackets or after a dash.
    private static readonly string[] VersionWords =
    [
        "live", "en vivo", "en directo", "directo", "acoustic", "acustico", "acustica", "unplugged",
        "remix", "rmx", "mix", "karaoke", "instrumental", "version", "cover", "sped up", "slowed",
        "reverb", "demo", "rework", "bootleg", "medley", "tribute", "homenaje", "orchestral",
        "orquestal", "sinfonico", "symphonic", "lullaby"
    ];

    private static readonly string[] AnywhereVersionWords =
    [
        "remix", "rmx", "karaoke", "instrumental", "en vivo", "en directo", "sped up", "slowed"
    ];

    // What a Christmas song says in its title (normalized).
    private static readonly string[] ChristmasWords =
    [
        "christmas", "xmas", "navidad", "villancico", "noche de paz", "jingle bell", "santa claus",
        "papa noel", "nochebuena", "campana sobre campana", "los peces en el rio", "el tamborilero",
        "white christmas", "feliz navidad", "noel", "rudolph", "silent night", "let it snow",
        "mistletoe", "reyes magos"
    ];

    private static readonly Regex Brackets = new(@"\s*[\(\[][^\)\]]*[\)\]]", RegexOptions.CultureInvariant);
    private static readonly Regex DashTail = new(@"\s+[-–—]\s+.*$", RegexOptions.CultureInvariant);
    private static readonly Regex CreditSplit = new(
        @"\s+(?:feat\.?|ft\.?|featuring|&|x|y|con|with|vs\.?|and)\s+|\s*,\s*|\s*/\s*|\s*;\s*",
        RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);

    // ---------------------------------------------------------------- names

    /// <summary>A name as compared: without accents, marks or case (see <see cref="KostvMusicAway.Normalize"/>).</summary>
    public static string Norm(string? text) => KostvMusicAway.Normalize(text);

    /// <summary>A title as compared: without what goes in brackets or after a dash.</summary>
    public static string NormTitle(string? title)
    {
        var plain = DashTail.Replace(Brackets.Replace(title ?? string.Empty, string.Empty), string.Empty);
        var norm = Norm(plain);
        return norm.Length > 0 ? norm : Norm(title);
    }

    /// <summary>The artists of a credit, compared: the whole credit and each one in it.</summary>
    public static IReadOnlyList<string> CreditNames(string? credit)
    {
        var full = Norm(credit);
        var names = new List<string>();
        if (full.Length > 0)
        {
            names.Add(full);
        }

        foreach (var part in CreditSplit.Split(credit ?? string.Empty))
        {
            var name = Norm(part);
            if (name.Length > 0 && !names.Contains(name))
            {
                names.Add(name);
            }
        }

        return names;
    }

    /// <summary>The first artist of a credit, compared: who it is «by», for variety.</summary>
    public static string Primary(string? credit)
    {
        var names = CreditNames(credit);
        return names.Count switch
        {
            0 => string.Empty,
            1 => names[0],
            _ => names[1]
        };
    }

    /// <summary>The first artist of a credit as written (for asking Deezer).</summary>
    public static string PrimaryAsWritten(string? credit)
    {
        var first = CreditSplit.Split(credit ?? string.Empty).Select(p => p.Trim()).FirstOrDefault(p => p.Length > 0);
        return first ?? (credit ?? string.Empty).Trim();
    }

    /// <summary>The artists of a credit, each as written (for the library and «no me gusta»).</summary>
    public static IReadOnlyList<string> CreditAsWritten(string? credit) =>
        CreditSplit.Split(credit ?? string.Empty).Select(p => p.Trim()).Where(p => p.Length > 0).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

    /// <summary>A title without what goes in brackets, as written (for asking Deezer).</summary>
    public static string TitleAsWritten(string? title)
    {
        var plain = Brackets.Replace(title ?? string.Empty, string.Empty).Trim();
        return plain.Length > 0 ? plain : (title ?? string.Empty).Trim();
    }

    /// <summary>The kinds of version a title says it is (live, remix, karaoke…), compared.</summary>
    public static IReadOnlySet<string> VersionsOf(string? title)
    {
        var found = new HashSet<string>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(title))
        {
            return found;
        }

        var parts = Brackets.Matches(title).Select(m => m.Value).ToList();
        var tail = DashTail.Match(Brackets.Replace(title, string.Empty));
        if (tail.Success)
        {
            parts.Add(tail.Value);
        }

        foreach (var part in parts)
        {
            var words = " " + Norm(part) + " ";
            foreach (var word in VersionWords)
            {
                if (words.Contains(" " + word + " ", StringComparison.Ordinal))
                {
                    found.Add(word);
                }
            }
        }

        // Some say it anywhere in the title («Una Foto Remix»), and can't be a song's own name.
        var whole = " " + Norm(title) + " ";
        foreach (var word in AnywhereVersionWords)
        {
            if (whole.Contains(" " + word + " ", StringComparison.Ordinal))
            {
                found.Add(word);
            }
        }

        return found;
    }

    /// <summary>Whether a title is of a Christmas song.</summary>
    public static bool IsChristmas(string? title)
    {
        var words = " " + Norm(title) + " ";
        return ChristmasWords.Any(w => words.Contains(" " + w + " ", StringComparison.Ordinal));
    }

    /// <summary>A tag of MusicBrainz as compared, or null when it doesn't tell a style.</summary>
    public static string? StyleTag(string? tag)
    {
        var norm = Norm(tag);
        return norm.Length == 0 || GenericTags.Contains(norm) || DecadeTag.IsMatch(norm.Replace(" ", string.Empty, StringComparison.Ordinal)) ? null : norm;
    }

    /// <summary>
    /// The styles an artist is really of, by how many people tagged each on MusicBrainz: those
    /// with at least 2 and a third of the most tagged (a lone «hip hop» on a reggaeton artist
    /// would let in all of hip hop), the first 8.
    /// </summary>
    public static IReadOnlySet<string> StrongTags(IReadOnlyDictionary<string, double> counts)
    {
        if (counts.Count == 0)
        {
            return new HashSet<string>(StringComparer.Ordinal);
        }

        var floor = Math.Max(2, Math.Ceiling(counts.Values.Max() / 3));
        return counts.Where(c => c.Value >= floor).OrderByDescending(c => c.Value).Take(8).Select(c => c.Key).ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>The year of a date as MusicBrainz or Deezer write it (<c>2001-10-11</c>, <c>2008</c>).</summary>
    public static int? YearOf(string? date) =>
        date is { Length: >= 4 } && int.TryParse(date.AsSpan(0, 4), NumberStyles.None, CultureInfo.InvariantCulture, out var year) && year > 1800
            ? year
            : null;

    /// <summary>Whether a song titled <paramref name="title"/> is the seed or another version of it (by anyone).</summary>
    public static bool IsSeedLike(string title, string seedTitle) => NormTitle(title) == NormTitle(seedTitle);

    private static bool Shares(IEnumerable<string> names, IReadOnlySet<string> set) => names.Any(set.Contains);

    // ---------------------------------------------------------------- the station, for the home

    /// <summary>
    /// The station of the seed for the whole home, in order: the candidates by listening that pass
    /// the style filter (by score, softly less when far in time), Deezer's radio of the seed's
    /// artist (first filler, or leading when fewer than <see cref="LeadThreshold"/> pass), and the
    /// most heard of the related artists and of the seed's own. Without versions (unless the seed
    /// is one), Christmas songs outside December, the seed itself or repeats.
    /// </summary>
    public static List<KostvStationEntry> Plan(KostvStationInputs inputs, double jitter = 0, int jitterSeed = 0)
    {
        var seedNames = CreditNames(inputs.SeedArtist).ToHashSet(StringComparer.Ordinal);
        var style = new HashSet<string>(seedNames, StringComparer.Ordinal);
        foreach (var name in inputs.Related)
        {
            style.UnionWith(CreditNames(name));
        }

        // Kos TV: ListenBrainz's like artists alone bring back the global hits of the time (into
        // urban music, say), so they only count also related to the related on Deezer, or sharing
        // a style tag with the seed's artist on MusicBrainz.
        var relatedOfRelated = inputs.RelatedOfRelated.Select(Norm).Where(n => n.Length > 0).ToHashSet(StringComparer.Ordinal);
        var similar = inputs.SimilarArtists.Select(Norm).Where(n => n.Length > 0).ToHashSet(StringComparer.Ordinal);

        bool InStyle(KostvStationTrack track)
        {
            var names = CreditNames(track.Artist);
            if (Shares(names, style))
            {
                return true;
            }

            if (!Shares(names, similar))
            {
                return false;
            }

            if (Shares(names, relatedOfRelated))
            {
                return true;
            }

            return track.Mbid != null && inputs.Recordings.TryGetValue(track.Mbid, out var info) &&
                   info.ArtistTags.Any(inputs.SeedArtistTags.Contains);
        }

        var seedVersions = VersionsOf(inputs.SeedTitle);
        var christmasOk = inputs.Month == 12 || IsChristmas(inputs.SeedTitle);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var seenDeezer = new HashSet<string>(StringComparer.Ordinal);

        bool Admit(KostvStationTrack track)
        {
            if (string.IsNullOrWhiteSpace(track.Title) || string.IsNullOrWhiteSpace(track.Artist) || IsSeedLike(track.Title, inputs.SeedTitle))
            {
                return false;
            }

            if (VersionsOf(track.Title).Any(v => !seedVersions.Contains(v)) || (!christmasOk && IsChristmas(track.Title)))
            {
                return false;
            }

            if (track.DeezerId != null && !seenDeezer.Add(track.DeezerId))
            {
                return false;
            }

            return seen.Add(NormTitle(track.Title) + "|" + Primary(track.Artist));
        }

        // The candidates by listening: ListenBrainz and Last.fm together, each by its best.
        var random = new Random(jitterSeed);
        var byListening = new List<(KostvStationTrack Track, string Why, double Score)>();
        var listened = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var (list, why) in new[] { (inputs.ListenBrainz, KostvStationWhy.ListenBrainz), (inputs.LastFm, KostvStationWhy.LastFm) })
        {
            foreach (var track in list)
            {
                var key = NormTitle(track.Title) + "|" + Primary(track.Artist);
                if (listened.TryGetValue(key, out var at))
                {
                    if (track.Score > byListening[at].Score)
                    {
                        byListening[at] = (byListening[at].Track, byListening[at].Why, track.Score);
                    }

                    continue;
                }

                listened[key] = byListening.Count;
                byListening.Add((track, why, track.Score));
            }
        }

        var passing = new List<KostvStationEntry>();
        foreach (var (track, why, score) in byListening)
        {
            if (!InStyle(track))
            {
                continue;
            }

            var weighed = score;
            var info = track.Mbid != null ? inputs.Recordings.GetValueOrDefault(track.Mbid) : null;
            if (inputs.SeedYear is { } seedYear && info?.Year is { } year)
            {
                var apart = Math.Abs(year - seedYear);
                weighed *= apart >= 2 * EraYears ? FarEraFactor : apart > EraYears ? EraFactor : 1;
            }

            if (jitter > 0)
            {
                weighed *= 1 + ((random.NextDouble() * 2) - 1) * jitter;
            }

            passing.Add(new KostvStationEntry
            {
                Title = track.Title,
                Artist = track.Artist,
                Album = track.Album,
                Mbid = track.Mbid,
                DeezerId = track.DeezerId,
                Explicit = track.Explicit,
                Why = why,
                Score = Math.Round(weighed, 4),
                Isrcs = info?.Isrcs ?? []
            });
        }

        // Stable: equal scores keep the order the sources gave.
        passing = passing.Select((e, i) => (e, i)).OrderByDescending(p => p.e.Score).ThenBy(p => p.i).Select(p => p.e).ToList();

        var plan = new List<KostvStationEntry>();
        void Add(KostvStationEntry entry)
        {
            var track = new KostvStationTrack(entry.Title, entry.Artist, entry.Album, entry.Mbid, entry.DeezerId);
            if (Admit(track))
            {
                plan.Add(entry);
            }
        }

        static KostvStationEntry FromDeezer(KostvStationTrack track, string why, double score) => new()
        {
            Title = track.Title,
            Artist = track.Artist,
            Album = track.Album,
            Mbid = track.Mbid,
            DeezerId = track.DeezerId,
            Explicit = track.Explicit,
            Why = why,
            Score = score
        };

        var radio = inputs.Radio.Select((t, i) => FromDeezer(t, KostvStationWhy.Deezer, Math.Round(1 - (i / 100.0), 4))).ToList();
        if (passing.Count < LeadThreshold)
        {
            // Deezer's radio leads, the few by listening among it (two of the radio, then one).
            int r = 0, p = 0;
            while (r < radio.Count || p < passing.Count)
            {
                for (var k = 0; k < 2 && r < radio.Count; k++)
                {
                    Add(radio[r++]);
                }

                if (p < passing.Count)
                {
                    Add(passing[p++]);
                }
            }
        }
        else
        {
            passing.ForEach(Add);
            radio.ForEach(Add);
        }

        // Last, the most heard of the related artists (by rank, one artist after another), and the seed's.
        var tops = inputs.RelatedTop.Take(RelatedTopArtists).Select(l => l.Take(RelatedTopEach).ToList()).ToList();
        for (var rank = 0; rank < RelatedTopEach; rank++)
        {
            if (rank < inputs.SeedArtistTop.Count)
            {
                Add(FromDeezer(inputs.SeedArtistTop[rank], KostvStationWhy.Style, 0.2));
            }

            foreach (var list in tops.Where(l => rank < l.Count))
            {
                Add(FromDeezer(list[rank], KostvStationWhy.Style, Math.Round(0.3 - (rank / 100.0), 4)));
            }
        }

        foreach (var track in inputs.SeedArtistTop.Skip(RelatedTopEach))
        {
            Add(FromDeezer(track, KostvStationWhy.Style, 0.1));
        }

        return plan;
    }

    /// <summary>How many candidates by listening pass the style filter (to tell who leads, and the source).</summary>
    public static int PassingByListening(IEnumerable<KostvStationEntry> plan) =>
        plan.Count(e => e.Why is KostvStationWhy.ListenBrainz or KostvStationWhy.LastFm);

    // ---------------------------------------------------------------- the station, for a person

    /// <summary>
    /// <paramref name="songs"/> (in the station's order) with variety: never two of one artist in a
    /// row, at most <see cref="PerArtistInWindow"/> of an artist in any <see cref="VarietyWindow"/>,
    /// no two of one album in a row, and the seed's artist back about every
    /// <see cref="SeedArtistEvery"/>; up to <paramref name="limit"/>. What can't be placed stays out.
    /// </summary>
    public static List<T> Arrange<T>(
        IReadOnlyList<T> songs,
        Func<T, string> artistOf,
        Func<T, string?> albumOf,
        IReadOnlySet<string> seedArtist,
        int limit)
    {
        var pool = songs.ToList();
        var result = new List<T>();
        var artists = new List<string>();
        var sinceSeedArtist = 0;
        while (pool.Count > 0 && result.Count < limit)
        {
            var last = artists.Count > 0 ? artists[^1] : null;
            var lastAlbum = result.Count > 0 ? AlbumKey(albumOf(result[^1])) : null;
            var window = artists.Skip(Math.Max(0, artists.Count - (VarietyWindow - 1))).ToList();

            bool Fits(T song)
            {
                var artist = artistOf(song);
                if (artist == last || window.Count(a => a == artist) >= PerArtistInWindow)
                {
                    return false;
                }

                return lastAlbum == null || AlbumKey(albumOf(song)) != lastAlbum;
            }

            var pick = -1;
            if (sinceSeedArtist >= SeedArtistEvery - 1 && seedArtist.Count > 0)
            {
                pick = pool.FindIndex(s => seedArtist.Contains(artistOf(s)) && Fits(s));
            }

            if (pick < 0)
            {
                pick = pool.FindIndex(Fits);
            }

            if (pick < 0)
            {
                break;
            }

            var song = pool[pick];
            pool.RemoveAt(pick);
            var key = artistOf(song);
            sinceSeedArtist = seedArtist.Contains(key) ? 0 : sinceSeedArtist + 1;
            artists.Add(key);
            result.Add(song);
        }

        return result;
    }

    private static string? AlbumKey(string? album)
    {
        var key = NormTitle(album);
        return key.Length == 0 ? null : key;
    }
}
