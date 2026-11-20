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
/// kOS TV: one thing a person did with a song, one line of their month's file: a listen (how
/// long, how it ended, where, from what) or a heart put on or taken off.
/// </summary>
public sealed class KostvMusicEvent
{
    public const string ListenType = "listen";
    public const string HeartType = "heart";

    /// <summary><see cref="ListenType"/> or <see cref="HeartType"/>.</summary>
    [JsonPropertyName("type")]
    public string Type { get; set; } = ListenType;

    /// <summary>When it started (a listen) or happened (a heart), in UTC.</summary>
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

    [JsonIgnore]
    public bool IsListen => Type == ListenType;

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
/// kOS TV: each person's music, on disk: what they listened to (one JSON line per listen or
/// heart, a file per month, kept <see cref="KeepMonths"/> months), whether they want it kept
/// (Learn), and the app's list of the week for «Descubrimiento semanal». Under
/// <c>kostv-musica/&lt;user&gt;/</c> in the plugin's data folder. A line is appended under the
/// person's lock, so songs ending at once on two devices don't mix their lines.
/// </summary>
public sealed class KostvMusicStore
{
    /// <summary>The folder under the plugin's data folder.</summary>
    public const string FolderName = "kostv-musica";

    /// <summary>Months kept back from the current one: a listen is kept at least a year.</summary>
    public const int KeepMonths = 12;

    /// <summary>The most songs the app may store as the week's list.</summary>
    public const int MaxDiscoverySongs = 30;

    /// <summary>The largest week's list the app may store, in bytes.</summary>
    public const int MaxDiscoveryBytes = 64 * 1024;

    private const string SettingsFile = "settings.json";
    private const string DiscoveryFile = "discovery.json";
    private const string DayFile = "today.json";

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
    private readonly ConcurrentDictionary<Guid, bool> _learn = new();
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
    }

    /// <summary>Whether what <paramref name="userId"/> listens to is kept. On unless they turned it off.</summary>
    public bool Learns(Guid userId) => _learn.GetOrAdd(userId, id =>
    {
        var settings = AtomicFile.ReadWithRecovery(
            Path.Combine(FolderOf(id), SettingsFile),
            text => JsonSerializer.Deserialize<Settings>(text, LineOptions));
        return settings?.Learn ?? true;
    });

    /// <summary>Turns keeping what <paramref name="userId"/> listens to on or off.</summary>
    public void SetLearn(Guid userId, bool learn)
    {
        lock (LockOf(userId))
        {
            var folder = FolderOf(userId);
            Directory.CreateDirectory(folder);
            AtomicFile.WriteAllText(Path.Combine(folder, SettingsFile), JsonSerializer.Serialize(new Settings { Learn = learn }, LineOptions));
            _learn[userId] = learn;
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
            return entry == null || string.IsNullOrEmpty(entry.Item) ? null : entry;
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

    /// <summary>Forgets everything <paramref name="userId"/> listened to; Learn and the week's list stay.</summary>
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
            _learn.TryRemove(userId, out _);
            _summaries.TryRemove(userId, out _);
            _trimmedOn.TryRemove(userId, out _);
            _hearts.TryRemove(userId, out _);
            _listensDeletedAt.TryRemove(userId, out _);
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
        }

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
            if (e.Type == KostvMusicEvent.HeartType && e.Favorite is { } on && Guid.TryParse(e.Item, out var item))
            {
                hearts[item] = on;
            }
        }

        return hearts;
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
