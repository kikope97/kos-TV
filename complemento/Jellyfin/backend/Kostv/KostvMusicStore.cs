using System.Collections.Concurrent;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: one thing a person did with their music, one line of their month's file: a listen (how
/// long, how it ended, where, from what, what played before), a heart put on or taken off a song,
/// album or artist, songs added to a playlist, an album asked for, or what the app was shown of
/// their music that day. Lines written before a field existed read without it.
/// </summary>
public sealed class KostvMusicEvent
{
    public const string ListenType = "listen";
    public const string HeartType = "heart";

    /// <summary>A heart put on or taken off an album or an artist (<see cref="Kind"/> says which).</summary>
    public const string FavoriteType = "favorite";

    /// <summary>Songs added to a playlist, as the app says (<see cref="Items"/>).</summary>
    public const string PlaylistAddType = "playlist_add";

    /// <summary>An album asked for in Stremfin, as the app says.</summary>
    public const string RequestType = "request";

    /// <summary>
    /// Kos TV: what the app says (route <c>Event</c>) of a song not at home it played through
    /// Stremfin. Not a type of line: it is noted as a <see cref="ListenType"/> of
    /// <c>stremfin:&lt;DeezerId&gt;</c> (see <see cref="StreamedPrefix"/>).
    /// </summary>
    public const string StreamListenType = "stream_listen";

    /// <summary>
    /// A «no me gusta» of songs or artists as the first versions of the route noted it. No longer
    /// written (it is kept apart, in <c>dislikes.json</c>), and old lines are left unused: no app
    /// sent it then.
    /// </summary>
    public const string DislikeType = "dislike";

    /// <summary>What the person was shown of a surface that day (<see cref="Surface"/>): only ids.</summary>
    public const string ShownType = "shown";

    public const string AlbumKind = "album";
    public const string ArtistKind = "artist";
    public const string SongKind = "song";

    public const string MixesSurface = "mixes";
    public const string MomentSurface = "moment";
    public const string DiscoverySurface = "discovery";

    /// <summary>One of the types above.</summary>
    [JsonPropertyName("type")]
    public string Type { get; set; } = ListenType;

    /// <summary>When it started (a listen) or happened (anything else), in UTC.</summary>
    [JsonPropertyName("at")]
    public DateTimeOffset At { get; set; }

    /// <summary>
    /// The day it was at home (<see cref="KostvMusicTimeZone"/>), yyyy-MM-dd. Only for reading the
    /// file: the engine works the day and hour out of <see cref="At"/>, so lines noted in another
    /// time zone still count right.
    /// </summary>
    [JsonPropertyName("day")]
    public string Day { get; set; } = string.Empty;

    /// <summary>The hour it was at home, 0 to 23.</summary>
    [JsonPropertyName("hour")]
    public int Hour { get; set; }

    /// <summary>The day of the week at home, 1 (Monday) to 7 (Sunday).</summary>
    [JsonPropertyName("weekday")]
    public int Weekday { get; set; }

    /// <summary>The song, without dashes.</summary>
    [JsonPropertyName("item")]
    public string Item { get; set; } = string.Empty;

    [JsonPropertyName("album")]
    public string? Album { get; set; }

    [JsonPropertyName("artistIds")]
    public List<string>? ArtistIds { get; set; }

    [JsonPropertyName("artists")]
    public List<string>? Artists { get; set; }

    [JsonPropertyName("genres")]
    public List<string>? Genres { get; set; }

    /// <summary>A listen: the seconds of it that were heard.</summary>
    [JsonPropertyName("played")]
    public int? Played { get; set; }

    /// <summary>A listen: how long the song is, in seconds, when known.</summary>
    [JsonPropertyName("duration")]
    public int? Duration { get; set; }

    /// <summary>A listen: completed, skipped or stopped (see <see cref="KostvListenOutcome"/>).</summary>
    [JsonPropertyName("outcome")]
    public string? Outcome { get; set; }

    /// <summary>A listen: tv, mobile, web or other (see <see cref="KostvDeviceKind"/>).</summary>
    [JsonPropertyName("device")]
    public string? Device { get; set; }

    /// <summary>A listen: where it was started from, when the app said (see <see cref="KostvMusicContext"/>).</summary>
    [JsonPropertyName("source")]
    public string? Source { get; set; }

    /// <summary>
    /// A listen from a daily mix: that mix's genre on the day (the mix's id is only its place that
    /// day), so how each mix goes can be measured later.
    /// </summary>
    [JsonPropertyName("mixGenre")]
    public string? MixGenre { get; set; }

    /// <summary>A heart: whether it was put on (true) or taken off (false).</summary>
    [JsonPropertyName("favorite")]
    public bool? Favorite { get; set; }

    /// <summary>
    /// A listen: the id of its session, the person's listens one after another with less than
    /// <see cref="KostvMusicStore.SessionGap"/> between them.
    /// </summary>
    [JsonPropertyName("session")]
    public string? Session { get; set; }

    /// <summary>A listen: the song heard just before it in its session, without dashes.</summary>
    [JsonPropertyName("prev")]
    public string? Prev { get; set; }

    /// <summary>A listen: how the one before it in its session ended (see <see cref="KostvListenEnd"/>).</summary>
    [JsonPropertyName("prevEndedBy")]
    public string? PrevEndedBy { get; set; }

    /// <summary>A listen: how it really ended (see <see cref="KostvListenEnd"/>).</summary>
    [JsonPropertyName("endedBy")]
    public string? EndedBy { get; set; }

    /// <summary>A listen: whether shuffle was on while it played; null when the server didn't say.</summary>
    [JsonPropertyName("shuffle")]
    public bool? Shuffle { get; set; }

    /// <summary>A listen: the repeat mode while it played (none, all or one); null when the server didn't say.</summary>
    [JsonPropertyName("repeat")]
    public string? Repeat { get; set; }

    /// <summary>A listen: true when it is the same song again right after it ended (only written when true).</summary>
    [JsonPropertyName("replay")]
    public bool? Replay { get; set; }

    /// <summary>A listen: how many times it was taken back more than a few seconds (only written when any).</summary>
    [JsonPropertyName("seekBack")]
    public int? SeekBack { get; set; }

    /// <summary>A favorite: album or artist; a dislike: artist or song, when the app said.</summary>
    [JsonPropertyName("kind")]
    public string? Kind { get; set; }

    /// <summary>A playlist_add, a dislike or the moment's mix shown: the songs (or artists), without dashes.</summary>
    [JsonPropertyName("items")]
    public List<string>? Items { get; set; }

    /// <summary>A request: the album's name, as the app gave it.</summary>
    [JsonPropertyName("albumName")]
    public string? AlbumName { get; set; }

    /// <summary>A request: the artist's name, as the app gave it.</summary>
    [JsonPropertyName("artistName")]
    public string? ArtistName { get; set; }

    /// <summary>A request: the album's Deezer id.</summary>
    [JsonPropertyName("deezerAlbumId")]
    public string? DeezerAlbumId { get; set; }

    /// <summary>Shown: mixes, moment or discovery.</summary>
    [JsonPropertyName("surface")]
    public string? Surface { get; set; }

    /// <summary>Shown mixes: each mix's id, genre and songs.</summary>
    [JsonPropertyName("mixes")]
    public List<KostvShownMix>? Mixes { get; set; }

    /// <summary>Shown moment: its time of day.</summary>
    [JsonPropertyName("slot")]
    public string? Slot { get; set; }

    /// <summary>Shown discovery: its week.</summary>
    [JsonPropertyName("week")]
    public string? Week { get; set; }

    /// <summary>Shown discovery: the Deezer ids of its songs.</summary>
    [JsonPropertyName("deezerIds")]
    public List<string>? DeezerIds { get; set; }

    /// <summary>A listen of a song not at home (see <see cref="StreamedPrefix"/>): its title, as the app gave it.</summary>
    [JsonPropertyName("title")]
    public string? Title { get; set; }

    /// <summary>
    /// Kos TV: what <see cref="Item"/> starts with for a song not at home, heard through Stremfin
    /// («Toda la música»): <c>stremfin:&lt;DeezerId&gt;</c>. Its artists, genres and album
    /// (<see cref="AlbumName"/>) are by name; there is no song of the library to read.
    /// </summary>
    public const string StreamedPrefix = "stremfin:";

    /// <summary>The longest Deezer id kept.</summary>
    public const int MaxDeezerIdLength = 32;

    /// <summary>Whether <paramref name="deezerId"/> is a Deezer id: digits only, 1 to <see cref="MaxDeezerIdLength"/>.</summary>
    public static bool IsDeezerId(string? deezerId) =>
        deezerId is { Length: > 0 and <= MaxDeezerIdLength } && deezerId.All(char.IsAsciiDigit);

    /// <summary>The item of a song not at home: <c>stremfin:&lt;DeezerId&gt;</c>.</summary>
    public static string StreamedItem(string deezerId) => StreamedPrefix + deezerId;

    /// <summary>The Deezer id of <paramref name="item"/> when it is a song not at home (see <see cref="StreamedPrefix"/>), or null.</summary>
    public static string? DeezerIdOf(string? item) =>
        item != null && item.StartsWith(StreamedPrefix, StringComparison.Ordinal) && IsDeezerId(item[StreamedPrefix.Length..])
            ? item[StreamedPrefix.Length..]
            : null;

    /// <summary>A listen of a song not at home, heard through Stremfin.</summary>
    [JsonIgnore]
    public bool IsStreamed => DeezerIdOf(Item) != null;

    [JsonIgnore]
    public bool IsListen => Type == ListenType;

    /// <summary>A listen that failed to play (see <see cref="KostvListenEnd.Error"/>).</summary>
    [JsonIgnore]
    public bool Failed => IsListen && EndedBy == KostvListenEnd.Error;

    /// <summary>
    /// A listen that tells of the person's taste: every one but one that failed before much of it
    /// was heard, which is the server's or the app's doing, not a skip.
    /// </summary>
    [JsonIgnore]
    public bool Counts => IsListen && !(Failed && Outcome == KostvListenOutcome.Skipped);

    /// <summary>When it was at home, in <paramref name="zone"/>, from <see cref="At"/>.</summary>
    public DateTimeOffset LocalIn(TimeZoneInfo zone) => TimeZoneInfo.ConvertTime(At, zone);

    /// <summary>Fills <see cref="Day"/>, <see cref="Hour"/> and <see cref="Weekday"/> from <see cref="At"/> in <paramref name="zone"/>.</summary>
    public KostvMusicEvent Stamp(DateTimeOffset at, TimeZoneInfo zone)
    {
        At = at.ToUniversalTime();
        var local = TimeZoneInfo.ConvertTime(at, zone);
        Day = local.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        Hour = local.Hour;
        Weekday = local.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)local.DayOfWeek;
        return this;
    }
}

/// <summary>kOS TV: one daily mix as shown: its id that day, its genre and its songs (without dashes).</summary>
public sealed class KostvShownMix
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("genre")]
    public string? Genre { get; set; }

    [JsonPropertyName("items")]
    public List<string> Items { get; set; } = [];
}

/// <summary>kOS TV: how a listen really ended, besides how much of it was heard.</summary>
public static class KostvListenEnd
{
    /// <summary>It played to its end (within a few seconds of it).</summary>
    public const string Natural = "natural";

    /// <summary>Another song started on the same session within a few seconds.</summary>
    public const string Next = "next";

    /// <summary>Stopped, and nothing followed.</summary>
    public const string Stop = "stop";

    /// <summary>The session ended (the app closed, or the server let it go).</summary>
    public const string Closed = "closed";

    /// <summary>It failed to play.</summary>
    public const string Error = "error";
}

/// <summary>
/// kOS TV: what music the app offers a person (their setting «Toda la música»): all, also what
/// isn't at home (through Stremfin), by default; or only what is at home.
/// </summary>
public static class KostvMusicCatalog
{
    public const string All = "all";
    public const string Home = "home";

    /// <summary>The catalog as said (any case, spaces around), or null when it is neither.</summary>
    public static string? Normalize(string? catalog) => catalog?.Trim().ToLowerInvariant() switch
    {
        All => All,
        Home => Home,
        _ => null
    };
}

/// <summary>
/// kOS TV: the home's time zone for music (the times of day, the music day starting at 5:00 and
/// the week of «Descubrimiento semanal»): an IANA id set on the plugin's page, Madrid unless
/// changed. Not the server's own, which in a container is often UTC.
/// </summary>
public static class KostvMusicTimeZone
{
    public const string DefaultId = "Europe/Madrid";

    private static readonly ConcurrentDictionary<string, TimeZoneInfo?> Known = new(StringComparer.Ordinal);

    // Madrid's rules (CET, and CEST from the last Sunday of March to the last of October), for a
    // server without the time zone database.
    private static readonly Lazy<TimeZoneInfo> MadridRules = new(() => TimeZoneInfo.CreateCustomTimeZone(
        DefaultId,
        TimeSpan.FromHours(1),
        DefaultId,
        "CET",
        "CEST",
        [
            TimeZoneInfo.AdjustmentRule.CreateAdjustmentRule(
                DateTime.MinValue.Date,
                DateTime.MaxValue.Date,
                TimeSpan.FromHours(1),
                TimeZoneInfo.TransitionTime.CreateFloatingDateRule(new DateTime(1, 1, 1, 2, 0, 0), 3, 5, DayOfWeek.Sunday),
                TimeZoneInfo.TransitionTime.CreateFloatingDateRule(new DateTime(1, 1, 1, 3, 0, 0), 10, 5, DayOfWeek.Sunday))
        ]));

    /// <summary>The time zone <paramref name="id"/> names, or null when it names none.</summary>
    public static TimeZoneInfo? Find(string? id)
    {
        var value = id?.Trim();
        if (string.IsNullOrEmpty(value))
        {
            return null;
        }

        return Known.GetOrAdd(value, name =>
        {
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(name);
            }
            catch (Exception ex) when (ex is TimeZoneNotFoundException or InvalidTimeZoneException or ArgumentException)
            {
                return string.Equals(name, DefaultId, StringComparison.Ordinal) ? MadridRules.Value : null;
            }
        });
    }

    /// <summary>The time zone <paramref name="id"/> names; Madrid's when it is empty or names none.</summary>
    public static TimeZoneInfo Resolve(string? id) => Find(id) ?? Find(DefaultId)!;

    /// <summary>Madrid's rules as built here, without the time zone database (for tests).</summary>
    internal static TimeZoneInfo Madrid => MadridRules.Value;
}

/// <summary>kOS TV: what one person's music folder holds: how many listens and since when.</summary>
public sealed record KostvMusicSummary(int Listens, DateTimeOffset? Since);

/// <summary>
/// kOS TV: each person's music, on disk: what they listened to and did (one JSON line per listen,
/// heart or other event, a file per month, kept <see cref="KeepMonths"/> months), their taste
/// summed up from it (<c>taste.json</c>), whether they want it kept (Learn), what they don't want
/// to hear (<c>dislikes.json</c>), how each engine did (<c>compare.jsonl</c>) and the app's list
/// of the week for «Descubrimiento semanal». Under
/// <c>kostv-musica/&lt;user&gt;/</c> in the plugin's data folder. A line is appended under the
/// person's lock, so songs ending at once on two devices don't mix their lines.
/// </summary>
public sealed class KostvMusicStore
{
    /// <summary>The folder under the plugin's data folder.</summary>
    public const string FolderName = "kostv-musica";

    /// <summary>Months kept back from the current one: a listen is kept at least two years.</summary>
    public const int KeepMonths = 24;

    /// <summary>Listens with less than this between them are of one session.</summary>
    public static readonly TimeSpan SessionGap = TimeSpan.FromMinutes(30);

    /// <summary>The same song starting again this soon after it ended is a replay.</summary>
    public static readonly TimeSpan ReplayWithin = TimeSpan.FromSeconds(10);

    /// <summary>The most songs the app may store as the week's list.</summary>
    public const int MaxDiscoverySongs = 30;

    /// <summary>The largest week's list the app may store, in bytes.</summary>
    public const int MaxDiscoveryBytes = 64 * 1024;

    private const string SettingsFile = "settings.json";
    private const string DiscoveryFile = "discovery.json";
    private const string DayFile = "today.json";
    private const string ShownFile = "shown.json";
    private const string TasteFile = "taste.json";
    private const string DislikesFile = "dislikes.json";
    private const string ShadowFile = "shadow.json";
    private const string CompareFile = "compare.jsonl";

    /// <summary>The most songs, and artists, a person's «no me gusta» list keeps (the oldest go).</summary>
    public const int MaxDislikes = 2000;

    /// <summary>
    /// While listens are noted, the taste (<c>taste.json</c>) is written once these many are
    /// added to it...
    /// </summary>
    public const int TasteSaveAfter = 50;

    /// <summary>...or once the first not written is this old; and always on the daily round and when the server stops.</summary>
    public static readonly TimeSpan TasteSaveEvery = TimeSpan.FromMinutes(5);

    private static readonly JsonSerializerOptions TasteOptions = new()
    {
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingDefault,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private static readonly Regex MonthFile = new(@"^(\d{4})-(\d{2})\.jsonl$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    internal static readonly JsonSerializerOptions LineOptions = new()
    {
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        // Names of songs and genres in Spanish stay readable in the file.
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private static readonly Encoding Utf8NoBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

    private readonly string _root;
    private readonly Func<DateTimeOffset> _now;
    private readonly ConcurrentDictionary<Guid, object> _locks = new();
    private readonly ConcurrentDictionary<Guid, Settings> _settings = new();
    private readonly ConcurrentDictionary<Guid, KostvMusicSummary> _summaries = new();
    private readonly ConcurrentDictionary<Guid, DateOnly> _trimmedOn = new();
    private readonly Func<TimeZoneInfo> _zone;
    private readonly ILogger? _logger;

    // Users deleted since the server started: nothing of theirs is written again, so a song that
    // was still on its way doesn't make their folder again.
    private readonly ConcurrentDictionary<Guid, byte> _deleted = new();

    // When each person last deleted their listens: one that started before isn't written after.
    private readonly ConcurrentDictionary<Guid, DateTimeOffset> _listensDeletedAt = new();

    // The last heart noted per person and song, read from their files the first time it is asked.
    private readonly ConcurrentDictionary<Guid, Dictionary<Guid, bool>> _hearts = new();

    // The last listen linked per person (see Link), read from their files the first time.
    private readonly ConcurrentDictionary<Guid, LastListen?> _last = new();

    // What was noted as shown per person: what of it to the day (or week) it was, from shown.json.
    private readonly ConcurrentDictionary<Guid, Dictionary<string, string>> _shown = new();

    // Each person's taste summed up (taste.json), once read or worked out.
    private readonly ConcurrentDictionary<Guid, KostvTasteSummary> _tastes = new();

    // What was added to each person's taste and not written yet: how many, and since when.
    private readonly ConcurrentDictionary<Guid, (int Count, DateTimeOffset Since)> _tasteUnsaved = new();

    // Each person's «no me gusta» (dislikes.json), once read.
    private readonly ConcurrentDictionary<Guid, KostvDislikes> _dislikes = new();

    /// <summary>The last listen of a person: its song, how and when it ended, and its session.</summary>
    private sealed record LastListen(string Item, string? EndedBy, DateTimeOffset EndedAt, string? Session);

    /// <param name="root">The folder of everyone's music.</param>
    /// <param name="now">The clock, so tests can move it.</param>
    /// <param name="zone">The home's time zone, fixed (for tests).</param>
    /// <param name="zoneOf">The home's time zone as set now (the plugin's setting).</param>
    /// <param name="logger">Where a file that can't be read is told.</param>
    public KostvMusicStore(
        string root,
        Func<DateTimeOffset>? now = null,
        TimeZoneInfo? zone = null,
        Func<TimeZoneInfo>? zoneOf = null,
        ILogger? logger = null)
    {
        _root = root;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _zone = zoneOf ?? (zone != null ? () => zone : () => KostvMusicTimeZone.Resolve(null));
        _logger = logger;
    }

    /// <summary>The home's time zone (see <see cref="KostvMusicTimeZone"/>).</summary>
    public TimeZoneInfo Zone => _zone();

    /// <summary>Now, as this store tells it (so tests can move it).</summary>
    public DateTimeOffset Now => _now();

    private object LockOf(Guid userId) => _locks.GetOrAdd(userId, _ => new object());

    internal string FolderOf(Guid userId) => Path.Combine(_root, userId.ToString("N"));

    // ---------------------------------------------------------------- Learn

    private sealed class Settings
    {
        [JsonPropertyName("learn")]
        public bool Learn { get; set; } = true;

        /// <summary>Kos TV: what music the app offers (see <see cref="KostvMusicCatalog"/>); null, all.</summary>
        [JsonPropertyName("catalog")]
        public string? Catalog { get; set; }
    }

    private Settings SettingsOf(Guid userId) => _settings.GetOrAdd(userId, id =>
    {
        var settings = AtomicFile.ReadWithRecovery(
            Path.Combine(FolderOf(id), SettingsFile),
            text => JsonSerializer.Deserialize<Settings>(text, LineOptions)) ?? new Settings();
        settings.Catalog = KostvMusicCatalog.Normalize(settings.Catalog);
        return settings;
    });

    /// <summary>Whether what <paramref name="userId"/> listens to is kept. On unless they turned it off.</summary>
    public bool Learns(Guid userId) => SettingsOf(userId).Learn;

    /// <summary>
    /// What music the app offers <paramref name="userId"/>: <see cref="KostvMusicCatalog.All"/>
    /// (also what isn't at home, through Stremfin) unless they chose <see cref="KostvMusicCatalog.Home"/>.
    /// </summary>
    public string Catalog(Guid userId) => SettingsOf(userId).Catalog ?? KostvMusicCatalog.All;

    /// <summary>Turns keeping what <paramref name="userId"/> listens to on or off.</summary>
    public void SetLearn(Guid userId, bool learn) => SetSettings(userId, learn, null);

    /// <summary>
    /// Changes what is given of <paramref name="userId"/>'s settings (<paramref name="learn"/>,
    /// <paramref name="catalog"/>, one of <see cref="KostvMusicCatalog"/>), the rest as it was.
    /// </summary>
    public void SetSettings(Guid userId, bool? learn, string? catalog)
    {
        lock (LockOf(userId))
        {
            var had = SettingsOf(userId);
            var settings = new Settings
            {
                Learn = learn ?? had.Learn,
                Catalog = catalog != null ? KostvMusicCatalog.Normalize(catalog) : had.Catalog
            };
            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            AtomicFile.WriteAllText(Path.Combine(folder, SettingsFile), JsonSerializer.Serialize(settings, LineOptions));
            _settings[userId] = settings;
        }
    }

    // ---------------------------------------------------------------- listens

    /// <summary>
    /// Adds <paramref name="entry"/> to <paramref name="userId"/>'s file of its month. Nothing
    /// when they turned Learn off; false then.
    /// </summary>
    public bool Append(Guid userId, KostvMusicEvent entry)
    {
        if (_deleted.ContainsKey(userId) || !Learns(userId))
        {
            return false;
        }

        var line = JsonSerializer.Serialize(entry, LineOptions) + "\n";
        var local = TimeZoneInfo.ConvertTime(entry.At, Zone);
        lock (LockOf(userId))
        {
            // Turned off, or the user deleted, while this was on its way.
            if (_deleted.ContainsKey(userId) || !Learns(userId))
            {
                return false;
            }

            // The person deleted their listens while this one played or was on its way.
            if (_listensDeletedAt.TryGetValue(userId, out var deletedAt) && entry.At < deletedAt)
            {
                return false;
            }

            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            File.AppendAllText(Path.Combine(folder, MonthName(local.Year, local.Month)), line, Utf8NoBom);
            if (entry.IsListen && _summaries.TryGetValue(userId, out var had))
            {
                _summaries[userId] = new KostvMusicSummary(had.Listens + 1, had.Since is { } since && since <= entry.At ? since : entry.At);
            }

            UpdateTasteLocked(userId, entry);
            TrimLocked(userId, onceADay: true);
        }

        return true;
    }

    /// <summary>
    /// Everything of <paramref name="userId"/>'s at or after <paramref name="since"/>, oldest
    /// first. A line cut short (a crash mid write) is skipped.
    /// </summary>
    public IReadOnlyList<KostvMusicEvent> Read(Guid userId, DateTimeOffset? since = null)
    {
        var from = since.HasValue ? TimeZoneInfo.ConvertTime(since.Value, Zone) : (DateTimeOffset?)null;
        var fromIndex = from.HasValue ? from.Value.Year * 12 + from.Value.Month - 1 : 0;
        var events = new List<KostvMusicEvent>();
        lock (LockOf(userId))
        {
            foreach (var (path, _) in MonthFiles(userId).Where(f => f.Index >= fromIndex - 1))
            {
                string[] lines;
                try
                {
                    lines = File.ReadAllLines(path, Utf8NoBom);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    // Left out, rather than failing the person's music.
                    _logger?.LogWarning(ex, "kOS TV music: {Path} could not be read", path);
                    continue;
                }

                foreach (var line in lines)
                {
                    if (Parse(line) is { } entry && (!since.HasValue || entry.At >= since.Value))
                    {
                        events.Add(entry);
                    }
                }
            }
        }

        return events.OrderBy(e => e.At).ToList();
    }

    private static KostvMusicEvent? Parse(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        try
        {
            var entry = JsonSerializer.Deserialize<KostvMusicEvent>(line, LineOptions);
            if (entry == null)
            {
                return null;
            }

            // A listen or a heart is of a song (or album, or artist); the other events may name none.
            var needsItem = entry.Type is KostvMusicEvent.ListenType or KostvMusicEvent.HeartType or KostvMusicEvent.FavoriteType;
            return needsItem && string.IsNullOrEmpty(entry.Item) ? null : entry;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>How many listens <paramref name="userId"/> has kept, and since when.</summary>
    public KostvMusicSummary Summary(Guid userId)
    {
        if (_summaries.TryGetValue(userId, out var known))
        {
            return known;
        }

        // Under the person's lock, so a listen noted meanwhile isn't missed from the count kept.
        lock (LockOf(userId))
        {
            var listens = Read(userId).Where(e => e.IsListen).ToList();
            var summary = new KostvMusicSummary(listens.Count, listens.Count > 0 ? listens[0].At : null);
            _summaries[userId] = summary;
            return summary;
        }
    }

    /// <summary>
    /// Forgets everything <paramref name="userId"/> listened to, and what was worked out of it (their
    /// taste and the engines compared); Learn, «no me gusta» and the week's list stay.
    /// </summary>
    public void DeleteListens(Guid userId)
    {
        lock (LockOf(userId))
        {
            foreach (var (path, _) in MonthFiles(userId))
            {
                TryDelete(path);
            }

            _listensDeletedAt[userId] = _now();
            _summaries.TryRemove(userId, out _);
            _hearts.TryRemove(userId, out _);
            _last.TryRemove(userId, out _);
            _shown.TryRemove(userId, out _);
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), ShownFile));
            // What was worked out of them goes too; «no me gusta» and Learn stay.
            _tastes.TryRemove(userId, out _);
            _tasteUnsaved.TryRemove(userId, out _);
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), TasteFile));
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), ShadowFile));
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), CompareFile));
        }
    }

    /// <summary>Forgets everything of <paramref name="userId"/>'s: for when the user is deleted.</summary>
    public void DeleteUser(Guid userId)
    {
        lock (LockOf(userId))
        {
            var folder = FolderOf(userId);
            try
            {
                if (Directory.Exists(folder))
                {
                    Directory.Delete(folder, recursive: true);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }

            _deleted[userId] = 0;
            _settings.TryRemove(userId, out _);
            _summaries.TryRemove(userId, out _);
            _trimmedOn.TryRemove(userId, out _);
            _hearts.TryRemove(userId, out _);
            _last.TryRemove(userId, out _);
            _shown.TryRemove(userId, out _);
            _listensDeletedAt.TryRemove(userId, out _);
            _tastes.TryRemove(userId, out _);
            _tasteUnsaved.TryRemove(userId, out _);
            _dislikes.TryRemove(userId, out _);
        }
    }

    /// <summary>
    /// Deletes the folders of users not in <paramref name="users"/> (deleted while the plugin was
    /// off, or written again after): for the daily round. Nothing when no user is given, as the
    /// server's users couldn't be read then. How many folders went.
    /// </summary>
    public int RemoveMissingUsers(IReadOnlyCollection<Guid> users)
    {
        if (users.Count == 0 || !Directory.Exists(_root))
        {
            return 0;
        }

        var known = users.ToHashSet();
        var removed = 0;
        foreach (var userId in UserFolders())
        {
            if (!known.Contains(userId))
            {
                DeleteUser(userId);
                removed++;
            }
        }

        return removed;
    }

    private List<Guid> UserFolders()
    {
        try
        {
            return Directory.EnumerateDirectories(_root)
                .Select(folder => Guid.TryParseExact(Path.GetFileName(folder), "N", out var id) ? id : Guid.Empty)
                .Where(id => id != Guid.Empty)
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: {Path} could not be read", _root);
            return [];
        }
    }

    /// <summary>
    /// Drops the months of <paramref name="userId"/>'s past <see cref="KeepMonths"/> back from
    /// the current one. How many files went.
    /// </summary>
    public int Trim(Guid userId)
    {
        lock (LockOf(userId))
        {
            return TrimLocked(userId, onceADay: false);
        }
    }

    /// <summary>Trims everyone's folder; for the daily round. How many files went.</summary>
    public int TrimAll()
    {
        if (!Directory.Exists(_root))
        {
            return 0;
        }

        var removed = 0;
        foreach (var userId in UserFolders())
        {
            removed += Trim(userId);
        }

        return removed;
    }

    private int TrimLocked(Guid userId, bool onceADay)
    {
        var local = TimeZoneInfo.ConvertTime(_now(), Zone);
        var today = DateOnly.FromDateTime(local.DateTime);
        if (onceADay && _trimmedOn.TryGetValue(userId, out var last) && last == today)
        {
            return 0;
        }

        _trimmedOn[userId] = today;
        var oldest = local.Year * 12 + local.Month - 1 - KeepMonths;
        var removed = 0;
        foreach (var (path, index) in MonthFiles(userId))
        {
            if (index < oldest && TryDelete(path))
            {
                removed++;
            }
        }

        if (removed > 0)
        {
            _summaries.TryRemove(userId, out _);
            // Worked out again from what is left, the next time it is asked.
            _tastes.TryRemove(userId, out _);
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), TasteFile));
        }

        TrimCompareLocked(userId, oldest);
        return removed;
    }

    private IEnumerable<(string Path, int Index)> MonthFiles(Guid userId)
    {
        var folder = FolderOf(userId);
        if (!Directory.Exists(folder))
        {
            return [];
        }

        try
        {
            return Directory.EnumerateFiles(folder, "*.jsonl")
                .Select(path => (Path: path, Match: MonthFile.Match(Path.GetFileName(path))))
                .Where(f => f.Match.Success)
                .Select(f => (f.Path, Index: int.Parse(f.Match.Groups[1].Value, CultureInfo.InvariantCulture) * 12 + int.Parse(f.Match.Groups[2].Value, CultureInfo.InvariantCulture) - 1))
                .OrderBy(f => f.Index)
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: {Path} could not be read", folder);
            return [];
        }
    }

    // ---------------------------------------------------------------- hearts

    /// <summary>
    /// The last heart noted for <paramref name="itemId"/> of <paramref name="userId"/>: on, off,
    /// or null when none was. Read from their files the first time, so a restart doesn't forget.
    /// </summary>
    public bool? HeartOf(Guid userId, Guid itemId)
    {
        lock (LockOf(userId))
        {
            return HeartsOf(userId).TryGetValue(itemId, out var on) ? on : null;
        }
    }

    /// <summary>Remembers that the heart of <paramref name="itemId"/> of <paramref name="userId"/> is <paramref name="favorite"/>.</summary>
    public void SetHeart(Guid userId, Guid itemId, bool favorite)
    {
        lock (LockOf(userId))
        {
            HeartsOf(userId)[itemId] = favorite;
        }
    }

    private Dictionary<Guid, bool> HeartsOf(Guid userId) => _hearts.GetOrAdd(userId, id =>
    {
        var hearts = new Dictionary<Guid, bool>();
        foreach (var e in Read(id))
        {
            if (e.Type is KostvMusicEvent.HeartType or KostvMusicEvent.FavoriteType && e.Favorite is { } on && Guid.TryParse(e.Item, out var item))
            {
                hearts[item] = on;
            }
        }

        return hearts;
    });

    // ---------------------------------------------------------------- sessions

    /// <summary>
    /// Links the listen <paramref name="entry"/> of <paramref name="userId"/>, which ended at
    /// <paramref name="endedAt"/>, to the one before: the same session when it started less than
    /// <see cref="SessionGap"/> after that one ended (a new one otherwise), the song before and how
    /// it ended, and whether it is that song again right after it (<see cref="ReplayWithin"/>).
    /// After a restart, the one before is read from the person's files.
    /// </summary>
    public void Link(Guid userId, KostvMusicEvent entry, DateTimeOffset endedAt)
    {
        lock (LockOf(userId))
        {
            var last = _last.GetOrAdd(userId, LastListenInFiles);
            if (last != null && entry.At - last.EndedAt < SessionGap)
            {
                entry.Session = last.Session ?? NewSessionId();
                entry.Prev = last.Item;
                entry.PrevEndedBy = last.EndedBy;
                entry.Replay = last.Item == entry.Item && entry.At - last.EndedAt <= ReplayWithin ? true : null;
            }
            else
            {
                entry.Session = NewSessionId();
            }

            _last[userId] = new LastListen(entry.Item, entry.EndedBy, endedAt, entry.Session);
        }
    }

    private static string NewSessionId() => Guid.NewGuid().ToString("N")[..12];

    // The last listen in the person's file of this month, or else of the month before. It ended
    // where it started plus what was heard of it (near enough: pauses aren't counted).
    private LastListen? LastListenInFiles(Guid userId)
    {
        var local = TimeZoneInfo.ConvertTime(_now(), Zone);
        var index = local.Year * 12 + local.Month - 1;
        foreach (var (path, _) in MonthFiles(userId).Where(f => f.Index == index || f.Index == index - 1).Reverse())
        {
            string[] lines;
            try
            {
                lines = File.ReadAllLines(path, Utf8NoBom);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _logger?.LogWarning(ex, "kOS TV music: {Path} could not be read", path);
                continue;
            }

            for (var i = lines.Length - 1; i >= 0; i--)
            {
                if (Parse(lines[i]) is { IsListen: true } listen)
                {
                    return new LastListen(listen.Item, listen.EndedBy, listen.At.AddSeconds(listen.Played ?? 0), listen.Session);
                }
            }
        }

        return null;
    }

    // ---------------------------------------------------------------- what was shown

    /// <summary>
    /// Adds <paramref name="entry"/> to <paramref name="userId"/>'s file unless one for
    /// <paramref name="key"/> was noted already for <paramref name="period"/> (the day, or the
    /// week): what was shown is noted once, not on every visit. Remembered in the person's folder
    /// (<c>shown.json</c>), so a restart doesn't note it again. False when not noted (it was
    /// already, or Learn is off).
    /// </summary>
    public bool AppendOnce(Guid userId, string key, string period, KostvMusicEvent entry)
    {
        lock (LockOf(userId))
        {
            var marks = ShownOf(userId);
            if (marks.TryGetValue(key, out var noted) && noted == period)
            {
                return false;
            }

            if (!Append(userId, entry))
            {
                return false;
            }

            marks[key] = period;
            try
            {
                AtomicFile.WriteAllText(Path.Combine(FolderOf(userId), ShownFile), JsonSerializer.Serialize(marks, LineOptions));
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _logger?.LogWarning(ex, "kOS TV music: what was shown could not be stored");
            }

            return true;
        }
    }

    // Under the person's lock.
    private Dictionary<string, string> ShownOf(Guid userId) => _shown.GetOrAdd(userId, id =>
    {
        var stored = AtomicFile.ReadWithRecovery(
            Path.Combine(FolderOf(id), ShownFile),
            text => JsonSerializer.Deserialize<Dictionary<string, string>>(text, LineOptions));
        return stored != null ? new Dictionary<string, string>(stored, StringComparer.Ordinal) : new Dictionary<string, string>(StringComparer.Ordinal);
    });

    // ---------------------------------------------------------------- the day's music

    /// <summary>What was worked out for <paramref name="userId"/> for the day, as stored, or null.</summary>
    public string? DayText(Guid userId)
    {
        lock (LockOf(userId))
        {
            return AtomicFile.ReadWithRecovery(Path.Combine(FolderOf(userId), DayFile), text => text);
        }
    }

    /// <summary>Stores what was worked out for <paramref name="userId"/> for the day, over the last.</summary>
    public bool SetDayText(Guid userId, string json)
    {
        lock (LockOf(userId))
        {
            if (_deleted.ContainsKey(userId))
            {
                return false;
            }

            try
            {
                var folder = FolderOf(userId);
                Directory.CreateDirectory(folder);
                AtomicFile.WriteAllText(Path.Combine(folder, DayFile), json);
                return true;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _logger?.LogWarning(ex, "kOS TV music: the day's music could not be stored");
                return false;
            }
        }
    }

    /// <summary>Forgets what was worked out for <paramref name="userId"/> for the day.</summary>
    public void ForgetDay(Guid userId)
    {
        lock (LockOf(userId))
        {
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), DayFile));
        }
    }

    // ---------------------------------------------------------------- the taste summed up

    /// <summary>
    /// <paramref name="userId"/>'s taste summed up (see <see cref="KostvTasteSummary"/>): from
    /// memory, their folder or, the first time, worked out from all their listens. A copy, made
    /// under their lock: the one kept goes on being brought up to date as listens are noted, and
    /// reading it meanwhile would fail.
    /// </summary>
    public KostvTasteSummary Taste(Guid userId)
    {
        lock (LockOf(userId))
        {
            return TasteLocked(userId, create: true)!.Copy();
        }
    }

    private KostvTasteSummary? TasteLocked(Guid userId, bool create)
    {
        if (_tastes.TryGetValue(userId, out var known))
        {
            return known;
        }

        var stored = AtomicFile.ReadWithRecovery(
            Path.Combine(FolderOf(userId), TasteFile),
            text => JsonSerializer.Deserialize<KostvTasteSummary>(text, TasteOptions));
        if (stored is { Version: KostvTasteSummary.CurrentVersion })
        {
            // A file edited by hand, or cut short, may have lists as null.
            _tastes[userId] = stored.Normalized();
            return stored;
        }

        return create ? RecomputeTasteLocked(userId) : null;
    }

    /// <summary>How the taste is worked out in full from the listens (for tests, to make it fail).</summary>
    internal Func<IReadOnlyList<KostvMusicEvent>, DateTimeOffset, KostvTasteSummary> Summarize { get; set; } = KostvMusicEngine.Summarize;

    private KostvTasteSummary RecomputeTasteLocked(Guid userId)
    {
        var summary = Summarize(Read(userId), _now());
        _tastes[userId] = summary;
        SaveTasteLocked(userId, summary);
        return summary;
    }

    private void SaveTasteLocked(Guid userId, KostvTasteSummary summary)
    {
        _tasteUnsaved.TryRemove(userId, out _);
        if (_deleted.ContainsKey(userId))
        {
            return;
        }

        try
        {
            // The songs only shown, and not lately, would only grow the file.
            summary.DropOldShown(_now());
            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            AtomicFile.WriteAllText(Path.Combine(folder, TasteFile), JsonSerializer.Serialize(summary, TasteOptions));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: the taste could not be stored");
        }
    }

    // Under the person's lock: what was just appended, added to their taste if it was worked out.
    private void UpdateTasteLocked(Guid userId, KostvMusicEvent entry)
    {
        try
        {
            if (TasteLocked(userId, create: false) is { } summary)
            {
                summary.Apply(entry);
                // Not written each time: once enough is added, or the first not written is old
                // enough (and on the daily round and when the server stops, see FlushTastes).
                var now = _now();
                var unsaved = _tasteUnsaved.TryGetValue(userId, out var had) ? (Count: had.Count + 1, had.Since) : (Count: 1, Since: now);
                if (unsaved.Count >= TasteSaveAfter || now - unsaved.Since >= TasteSaveEvery)
                {
                    SaveTasteLocked(userId, summary);
                }
                else
                {
                    _tasteUnsaved[userId] = unsaved;
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            // Worked out in full the next time instead.
            _tastes.TryRemove(userId, out _);
            _logger?.LogWarning(ex, "kOS TV music: the taste could not be brought up to date");
        }
    }

    /// <summary>Works out <paramref name="userId"/>'s taste again from all their listens.</summary>
    public KostvTasteSummary RecomputeTaste(Guid userId)
    {
        lock (LockOf(userId))
        {
            return RecomputeTasteLocked(userId);
        }
    }

    /// <summary>Writes what was added to anyone's taste and not written yet: when the server stops.</summary>
    public void FlushTastes()
    {
        foreach (var userId in _tasteUnsaved.Keys.ToList())
        {
            lock (LockOf(userId))
            {
                if (_tasteUnsaved.ContainsKey(userId) && _tastes.TryGetValue(userId, out var summary))
                {
                    SaveTasteLocked(userId, summary);
                }
                else
                {
                    _tasteUnsaved.TryRemove(userId, out _);
                }
            }
        }
    }

    /// <summary>
    /// Works out again the taste of everyone who keeps what they listen to: for the daily round,
    /// so what is brought up to date line by line never drifts. How many; one that fails doesn't
    /// stop the others (it is told, and its taste kept as it was).
    /// </summary>
    public int RecomputeTastes()
    {
        if (!Directory.Exists(_root))
        {
            FlushTastes();
            return 0;
        }

        var count = 0;
        foreach (var userId in UserFolders())
        {
            try
            {
                if (!_deleted.ContainsKey(userId) && Learns(userId))
                {
                    RecomputeTaste(userId);
                    count++;
                }
            }
            catch (Exception ex)
            {
                _logger?.LogWarning(ex, "kOS TV music: the taste of {User} could not be worked out again", userId.ToString("N"));
            }
        }

        // Those not worked out again (Learn off since): what was added, written.
        FlushTastes();
        return count;
    }

    // ---------------------------------------------------------------- «no me gusta»

    /// <summary>What <paramref name="userId"/> doesn't want to hear, a copy (the latest first).</summary>
    public KostvDislikes DislikesOf(Guid userId)
    {
        lock (LockOf(userId))
        {
            var copy = DislikesLocked(userId).Copy();
            copy.Songs = copy.Songs.OrderByDescending(s => s.At).ToList();
            copy.Artists = copy.Artists.OrderByDescending(a => a.At).ToList();
            return copy;
        }
    }

    private KostvDislikes DislikesLocked(Guid userId) => _dislikes.GetOrAdd(userId, id =>
        AtomicFile.ReadWithRecovery(
            Path.Combine(FolderOf(id), DislikesFile),
            text => JsonSerializer.Deserialize<KostvDislikes>(text, LineOptions))?.Normalized() ?? new KostvDislikes());

    /// <summary>
    /// Adds <paramref name="songs"/> and <paramref name="artists"/> to what <paramref name="userId"/>
    /// doesn't want to hear (one said again moves to the top). Also with Learn off: it is their
    /// choice, not something learned. False when not stored.
    /// </summary>
    public bool AddDislikes(Guid userId, IEnumerable<KostvDislikedSong> songs, IEnumerable<KostvDislikedArtist> artists)
    {
        lock (LockOf(userId))
        {
            if (_deleted.ContainsKey(userId))
            {
                return false;
            }

            var dislikes = DislikesLocked(userId);
            foreach (var song in songs)
            {
                dislikes.Songs.RemoveAll(s => s.Key == song.Key);
                dislikes.Songs.Add(song);
            }

            foreach (var artist in artists)
            {
                dislikes.Artists.RemoveAll(a => a.Id == artist.Id);
                dislikes.Artists.Add(artist);
            }

            dislikes.Songs = dislikes.Songs.OrderBy(s => s.At).TakeLast(MaxDislikes).ToList();
            dislikes.Artists = dislikes.Artists.OrderBy(a => a.At).TakeLast(MaxDislikes).ToList();
            return SaveDislikesLocked(userId, dislikes);
        }
    }

    /// <summary>Takes <paramref name="itemId"/> (a song or an artist) off <paramref name="userId"/>'s list. Whether it was on it.</summary>
    public bool RemoveDislike(Guid userId, Guid itemId) => RemoveDislike(userId, itemId.ToString("N"));

    /// <summary>
    /// Takes <paramref name="key"/> off <paramref name="userId"/>'s list: a song or an artist at
    /// home (its id, without dashes), or a song not at home (<c>stremfin:&lt;DeezerId&gt;</c>).
    /// Whether it was on it.
    /// </summary>
    public bool RemoveDislike(Guid userId, string key)
    {
        lock (LockOf(userId))
        {
            var dislikes = DislikesLocked(userId);
            var removed = dislikes.Songs.RemoveAll(s => s.Key == key) + dislikes.Artists.RemoveAll(a => a.Id == key);
            if (removed > 0)
            {
                SaveDislikesLocked(userId, dislikes);
            }

            return removed > 0;
        }
    }

    /// <summary>Empties <paramref name="userId"/>'s list of what they don't want to hear.</summary>
    public void ClearDislikes(Guid userId)
    {
        lock (LockOf(userId))
        {
            _dislikes[userId] = new KostvDislikes();
            AtomicFile.DeleteWithSidecars(Path.Combine(FolderOf(userId), DislikesFile));
        }
    }

    private bool SaveDislikesLocked(Guid userId, KostvDislikes dislikes)
    {
        try
        {
            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            AtomicFile.WriteAllText(Path.Combine(folder, DislikesFile), JsonSerializer.Serialize(dislikes, LineOptions));
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: «no me gusta» could not be stored");
            return false;
        }
    }

    // ---------------------------------------------------------------- the engines compared

    /// <summary>The first songs of a day's mixes by each engine, to compare with what is heard.</summary>
    public sealed class KostvShadow
    {
        [JsonPropertyName("day")]
        public string Day { get; set; } = string.Empty;

        /// <summary>The engine whose mixes were shown that day.</summary>
        [JsonPropertyName("engine")]
        public string? Engine { get; set; }

        [JsonPropertyName("old")]
        public List<Guid> Old { get; set; } = [];

        [JsonPropertyName("new")]
        public List<Guid> New { get; set; } = [];
    }

    /// <summary>One line of <c>compare.jsonl</c>: of a day, how many of each engine's first 25 were heard whole.</summary>
    public sealed class KostvComparison
    {
        [JsonPropertyName("day")]
        public string Day { get; set; } = string.Empty;

        [JsonPropertyName("engine")]
        public string? Engine { get; set; }

        [JsonPropertyName("hitsOld")]
        public int HitsOld { get; set; }

        [JsonPropertyName("hitsNew")]
        public int HitsNew { get; set; }
    }

    /// <summary>
    /// Keeps <paramref name="shadow"/> as <paramref name="userId"/>'s first songs of each engine
    /// for its day; the ones of a day before are compared first with what was heard whole that
    /// day (<paramref name="hits"/>), and the comparison added to <c>compare.jsonl</c>. Nothing
    /// while Learn is off, nor when worked out (<paramref name="workedOutAt"/>) before the person
    /// deleted their listens.
    /// </summary>
    public void NoteShadow(Guid userId, KostvShadow shadow, Func<KostvShadow, IReadOnlyList<KostvMusicEvent>, (int Old, int New)> hits, DateTimeOffset? workedOutAt = null)
    {
        lock (LockOf(userId))
        {
            if (_deleted.ContainsKey(userId) || !Learns(userId))
            {
                return;
            }

            // Worked out before the person deleted their listens: not written after.
            if (workedOutAt is { } at && _listensDeletedAt.TryGetValue(userId, out var deletedAt) && at < deletedAt)
            {
                return;
            }

            var folder = FolderOf(userId);
            var path = Path.Combine(folder, ShadowFile);
            var before = AtomicFile.ReadWithRecovery(path, text => JsonSerializer.Deserialize<KostvShadow>(text, LineOptions));
            try
            {
                Directory.CreateDirectory(folder);
                if (before != null && string.CompareOrdinal(before.Day, shadow.Day) < 0 &&
                    DateOnly.TryParseExact(before.Day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day))
                {
                    var events = Read(userId, KostvMusicEngine.DayStart(day, Zone));
                    var (old, fresh) = hits(before, events);
                    var line = JsonSerializer.Serialize(new KostvComparison { Day = before.Day, Engine = before.Engine, HitsOld = old, HitsNew = fresh }, LineOptions) + "\n";
                    File.AppendAllText(Path.Combine(folder, CompareFile), line, Utf8NoBom);
                }

                if (before == null || string.CompareOrdinal(before.Day, shadow.Day) <= 0)
                {
                    AtomicFile.WriteAllText(path, JsonSerializer.Serialize(shadow, LineOptions));
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _logger?.LogWarning(ex, "kOS TV music: the engines could not be compared");
            }
        }
    }

    /// <summary>The comparisons of <paramref name="userId"/>'s engines, oldest first.</summary>
    public IReadOnlyList<KostvComparison> Comparisons(Guid userId)
    {
        lock (LockOf(userId))
        {
            return ReadCompareLocked(userId);
        }
    }

    private List<KostvComparison> ReadCompareLocked(Guid userId)
    {
        var path = Path.Combine(FolderOf(userId), CompareFile);
        if (!File.Exists(path))
        {
            return [];
        }

        try
        {
            return File.ReadAllLines(path, Utf8NoBom)
                .Select(line =>
                {
                    try
                    {
                        return string.IsNullOrWhiteSpace(line) ? null : JsonSerializer.Deserialize<KostvComparison>(line, LineOptions);
                    }
                    catch (JsonException)
                    {
                        return null;
                    }
                })
                .OfType<KostvComparison>()
                .ToList();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: {Path} could not be read", path);
            return [];
        }
    }

    // The comparisons of days before the oldest month kept go, as the listens do.
    private void TrimCompareLocked(Guid userId, int oldestMonth)
    {
        var path = Path.Combine(FolderOf(userId), CompareFile);
        if (!File.Exists(path))
        {
            return;
        }

        var lines = ReadCompareLocked(userId);
        var kept = lines.Where(c => DateOnly.TryParseExact(c.Day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day) && day.Year * 12 + day.Month - 1 >= oldestMonth).ToList();
        if (kept.Count == lines.Count)
        {
            return;
        }

        try
        {
            AtomicFile.WriteAllText(path, string.Concat(kept.Select(c => JsonSerializer.Serialize(c, LineOptions) + "\n")));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: {Path} could not be trimmed", path);
        }
    }

    internal static string MonthName(int year, int month) =>
        string.Create(CultureInfo.InvariantCulture, $"{year:0000}-{month:00}.jsonl");

    private static bool TryDelete(string path)
    {
        try
        {
            File.Delete(path);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    // ---------------------------------------------------------------- the week's list

    private sealed class Discovery
    {
        [JsonPropertyName("week")]
        public string Week { get; set; } = string.Empty;

        [JsonPropertyName("songs")]
        public JsonElement Songs { get; set; }
    }

    /// <summary>
    /// The list the app stored for <paramref name="userId"/> for <paramref name="week"/>, as it
    /// sent it, or null when there is none. A list of another week is dropped.
    /// </summary>
    public JsonElement? DiscoveryOf(Guid userId, string week)
    {
        lock (LockOf(userId))
        {
            var path = Path.Combine(FolderOf(userId), DiscoveryFile);
            var stored = AtomicFile.ReadWithRecovery(path, text => JsonSerializer.Deserialize<Discovery>(text, LineOptions));
            if (stored == null)
            {
                return null;
            }

            if (!string.Equals(stored.Week, week, StringComparison.Ordinal) || stored.Songs.ValueKind != JsonValueKind.Array)
            {
                AtomicFile.DeleteWithSidecars(path);
                return null;
            }

            return stored.Songs.Clone();
        }
    }

    /// <summary>Why the app's list of the week wasn't stored.</summary>
    public enum DiscoveryRefusal
    {
        None,
        NotThisWeek,
        NotAList,
        TooMany,
        TooLarge
    }

    /// <summary>
    /// Stores <paramref name="songs"/> (a JSON array of up to <see cref="MaxDiscoverySongs"/>
    /// songs, at most <see cref="MaxDiscoveryBytes"/>) as <paramref name="userId"/>'s list of
    /// <paramref name="week"/>, which has to be <paramref name="currentWeek"/>.
    /// </summary>
    public DiscoveryRefusal SetDiscovery(Guid userId, string? week, JsonElement songs, string currentWeek)
    {
        if (!string.Equals(week, currentWeek, StringComparison.Ordinal))
        {
            return DiscoveryRefusal.NotThisWeek;
        }

        if (songs.ValueKind != JsonValueKind.Array)
        {
            return DiscoveryRefusal.NotAList;
        }

        if (songs.GetArrayLength() > MaxDiscoverySongs)
        {
            return DiscoveryRefusal.TooMany;
        }

        var json = JsonSerializer.Serialize(new Discovery { Week = currentWeek, Songs = songs }, LineOptions);
        if (Utf8NoBom.GetByteCount(json) > MaxDiscoveryBytes + 64)
        {
            return DiscoveryRefusal.TooLarge;
        }

        lock (LockOf(userId))
        {
            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            AtomicFile.WriteAllText(Path.Combine(folder, DiscoveryFile), json);
        }

        return DiscoveryRefusal.None;
    }
}

/// <summary>
/// kOS TV: where what is about to play comes from, as the app says it (a mix, the search, an
/// album...), kept <see cref="KeptFor"/> per person and song so the listen is noted with it.
/// Only in memory.
/// </summary>
public sealed class KostvMusicContext
{
    public static readonly TimeSpan KeptFor = TimeSpan.FromHours(6);

    /// <summary>The most songs one call may name.</summary>
    public const int MaxItems = 500;

    private static readonly HashSet<string> Plain = new(StringComparer.Ordinal)
    {
        "discovery", "search", "album", "artist", "favorites", "playlist", "charts", "radio", "other"
    };

    private static readonly Regex MixId = new("^mix:[a-z0-9][a-z0-9_-]{0,31}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    /// <summary>The most songs kept per person, the latest said.</summary>
    public const int MaxPerPerson = 2000;

    /// <summary>The most songs kept for everyone, the latest said.</summary>
    public const int MaxTotal = 20000;

    private static readonly TimeSpan SweepEvery = TimeSpan.FromMinutes(30);

    /// <summary>What was said of a song: where it comes from, the genre of its mix, and when.</summary>
    private sealed record Said(string Source, string? MixGenre, DateTimeOffset At);

    // Per person and song, all under one lock.
    private readonly object _sync = new();
    private readonly Dictionary<Guid, Dictionary<Guid, Said>> _sources = new();
    private int _count;
    private DateTimeOffset _lastSweep = DateTimeOffset.MinValue;

    /// <summary>
    /// The source as noted: one of the known ones, <c>mix:&lt;id&gt;</c> or
    /// <c>moment:&lt;slot&gt;</c>; anything else non-empty is "other", and nothing is null.
    /// </summary>
    public static string? Normalize(string? source)
    {
        var value = source?.Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(value))
        {
            return null;
        }

        if (Plain.Contains(value) || MixId.IsMatch(value))
        {
            return value;
        }

        if (value.StartsWith("moment:", StringComparison.Ordinal) && KostvMusicEngine.Slots.Contains(value["moment:".Length..]))
        {
            return value;
        }

        return "other";
    }

    /// <summary>
    /// The songs <paramref name="itemIds"/> of <paramref name="userId"/> come from
    /// <paramref name="source"/> (a daily mix of <paramref name="mixGenre"/>, when it is one).
    /// At most <see cref="MaxPerPerson"/> songs are kept per person and <see cref="MaxTotal"/> for
    /// everyone, the oldest said going first.
    /// </summary>
    public void Remember(Guid userId, string source, IEnumerable<Guid> itemIds, DateTimeOffset now, string? mixGenre = null)
    {
        var ids = itemIds.Where(id => id != Guid.Empty).Distinct().Take(MaxItems).ToList();
        lock (_sync)
        {
            if (!_sources.TryGetValue(userId, out var said))
            {
                _sources[userId] = said = new Dictionary<Guid, Said>();
            }

            foreach (var id in ids)
            {
                if (!said.ContainsKey(id))
                {
                    _count++;
                }

                said[id] = new Said(source, mixGenre, now);
            }

            if (said.Count > MaxPerPerson)
            {
                DropOldest(said.Select(kv => (userId, kv.Key, kv.Value.At)), said.Count - MaxPerPerson);
            }

            if (now - _lastSweep > SweepEvery)
            {
                _lastSweep = now;
                DropWhere(at => now - at > KeptFor);
            }

            if (_count > MaxTotal)
            {
                DropOldest(_sources.SelectMany(user => user.Value.Select(kv => (user.Key, kv.Key, kv.Value.At))), _count - MaxTotal);
            }
        }
    }

    private void DropOldest(IEnumerable<(Guid User, Guid Item, DateTimeOffset At)> entries, int count)
    {
        foreach (var (user, item, _) in entries.OrderBy(e => e.At).Take(count).ToList())
        {
            Drop(user, item);
        }
    }

    private void DropWhere(Func<DateTimeOffset, bool> old)
    {
        foreach (var (user, item) in _sources.SelectMany(u => u.Value.Where(kv => old(kv.Value.At)).Select(kv => (u.Key, kv.Key))).ToList())
        {
            Drop(user, item);
        }
    }

    private void Drop(Guid user, Guid item)
    {
        if (_sources.TryGetValue(user, out var said) && said.Remove(item))
        {
            _count--;
            if (said.Count == 0)
            {
                _sources.Remove(user);
            }
        }
    }

    private Said? Of(Guid userId, Guid itemId, DateTimeOffset now)
    {
        lock (_sync)
        {
            return _sources.TryGetValue(userId, out var said) && said.TryGetValue(itemId, out var value) && now - value.At <= KeptFor ? value : null;
        }
    }

    /// <summary>Where <paramref name="itemId"/> of <paramref name="userId"/> came from, if said within <see cref="KeptFor"/>.</summary>
    public string? SourceOf(Guid userId, Guid itemId, DateTimeOffset now) => Of(userId, itemId, now)?.Source;

    /// <summary>The genre of the daily mix <paramref name="itemId"/> of <paramref name="userId"/> came from, when it did.</summary>
    public string? MixGenreOf(Guid userId, Guid itemId, DateTimeOffset now) => Of(userId, itemId, now)?.MixGenre;

    /// <summary>How many songs are kept, for everyone or for <paramref name="userId"/>.</summary>
    internal int Count(Guid? userId = null)
    {
        lock (_sync)
        {
            return userId is { } id ? (_sources.TryGetValue(id, out var said) ? said.Count : 0) : _count;
        }
    }

    /// <summary>Forgets what <paramref name="userId"/> said.</summary>
    public void Forget(Guid userId)
    {
        lock (_sync)
        {
            if (_sources.Remove(userId, out var said))
            {
                _count -= said.Count;
            }
        }
    }
}
