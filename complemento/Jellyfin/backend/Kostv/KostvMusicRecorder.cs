using System.Collections.Concurrent;
using System.Security.Claims;
using Jellyfin.Data.Enums;
using Jellyfin.Data.Events.Users;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Events;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Session;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: how a listen ended.</summary>
public static class KostvListenOutcome
{
    public const string Completed = "completed";
    public const string Skipped = "skipped";
    public const string Stopped = "stopped";

    /// <summary>A song heard this much or more of counts as heard whole.</summary>
    public const double CompletedShare = 0.9;

    /// <summary>Less than this many seconds heard is a skip...</summary>
    public const double SkippedSeconds = 30;

    /// <summary>...and so is less than this much of the song.</summary>
    public const double SkippedShare = 0.5;

    /// <summary>
    /// Completed when <paramref name="played"/> seconds are at least 90 % of
    /// <paramref name="duration"/> or the song played to its end
    /// (<paramref name="reachedEnd"/>); skipped when less than 30 s or less than half was heard;
    /// otherwise stopped. Without a duration, only the 30 s tell.
    /// </summary>
    public static string Classify(double played, double? duration, bool reachedEnd)
    {
        played = Math.Max(0, played);
        if (reachedEnd)
        {
            return Completed;
        }

        if (duration is > 0 and var length)
        {
            var share = played / length;
            if (share >= CompletedShare)
            {
                return Completed;
            }

            return played < SkippedSeconds || share < SkippedShare ? Skipped : Stopped;
        }

        return played < SkippedSeconds ? Skipped : Stopped;
    }
}

/// <summary>kOS TV: what kind of device a listen was on, from the names the app gives the server.</summary>
public static class KostvDeviceKind
{
    public const string Tv = "tv";
    public const string Mobile = "mobile";
    public const string Web = "web";
    public const string Other = "other";

    private static readonly string[] TvWords =
    [
        "android tv", "androidtv", "apple tv", "appletv", "tvos", "google tv", "fire tv", "firetv", "fire stick",
        "firestick", "aftmm", "aftka", "shield", "bravia", "chromecast", "roku", "webos", "lg tv", "tizen",
        "samsung tv", "smart tv", "smarttv", "kodi", "xbox", "playstation", "mi box", "mibox", " tv box"
    ];

    private static readonly string[] WebWords =
    [
        "jellyfin web", "web", "chrome", "firefox", "safari", "edge", "opera", "browser", "navegador"
    ];

    private static readonly string[] MobileWords =
    [
        "android", "ios", "iphone", "ipad", "ipod", "mobile", "móvil", "movil", "phone", "finamp", "symfonium",
        "streamyfin", "findroid", "swiftfin", "manet", "gelli", "jellify", "substreamer", "pixel", "galaxy",
        "xiaomi", "redmi", "oneplus", "motorola", "moto "
    ];

    /// <summary>
    /// tv, mobile, web or other for a session of <paramref name="client"/> on
    /// <paramref name="device"/>. kOS TV says which in its client name («kOS TV para Android
    /// TV», «kOS TV para la web», «kOS TV para Android»...); for other apps, by the usual
    /// names of TV, browser and phone apps.
    /// </summary>
    public static string Of(string? client, string? device)
    {
        var clientName = (client ?? string.Empty).Trim().ToLowerInvariant();
        var deviceName = (device ?? string.Empty).Trim().ToLowerInvariant();

        // kOS TV's own name has «TV» in it, so it is taken out before looking for TV words.
        if (clientName.StartsWith("kos tv", StringComparison.Ordinal))
        {
            var rest = clientName["kos tv".Length..].Trim();
            if (rest.Length > 0)
            {
                var said = Of(rest, string.Empty);
                return said != Other ? said : Of(string.Empty, deviceName);
            }

            clientName = string.Empty;
        }

        foreach (var name in new[] { clientName, deviceName })
        {
            if (name.Length == 0)
            {
                continue;
            }

            var padded = " " + name + " ";
            if (TvWords.Any(w => padded.Contains(w, StringComparison.Ordinal)) || padded.Contains(" tv ", StringComparison.Ordinal))
            {
                return Tv;
            }

            if (WebWords.Any(w => padded.Contains(w, StringComparison.Ordinal)))
            {
                return Web;
            }

            if (MobileWords.Any(w => padded.Contains(w, StringComparison.Ordinal)))
            {
                return Mobile;
            }
        }

        return Other;
    }
}

/// <summary>
/// kOS TV: the songs whose playback an app said failed (Jellyfin's stop report carries it, but
/// not the event the server raises from it), per person and song, for a short while: noted by
/// <see cref="KostvPlaybackFailureFilter"/> as the report arrives, taken by the recorder at the stop.
/// </summary>
public sealed class KostvPlaybackFailures
{
    /// <summary>A failure said longer ago than this isn't the stop's.</summary>
    internal static readonly TimeSpan KeptFor = TimeSpan.FromMinutes(2);

    private const int MaxKept = 1000;

    private readonly ConcurrentDictionary<(Guid User, Guid Item), DateTimeOffset> _failed = new();

    /// <summary>The playback of <paramref name="itemId"/> by <paramref name="userId"/> failed.</summary>
    public void Note(Guid userId, Guid itemId, DateTimeOffset now)
    {
        if (userId == Guid.Empty || itemId == Guid.Empty)
        {
            return;
        }

        if (_failed.Count >= MaxKept)
        {
            foreach (var (key, at) in _failed)
            {
                if (now - at > KeptFor)
                {
                    _failed.TryRemove(key, out _);
                }
            }

            if (_failed.Count >= MaxKept)
            {
                _failed.Clear();
            }
        }

        _failed[(userId, itemId)] = now;
    }

    /// <summary>Whether the playback of <paramref name="itemId"/> by <paramref name="userId"/> was said to fail lately; forgotten once asked.</summary>
    public bool Take(Guid userId, Guid itemId, DateTimeOffset now) =>
        _failed.TryRemove((userId, itemId), out var at) && now - at <= KeptFor;
}

/// <summary>
/// kOS TV: notes, from the stop report an app sends the server, that a playback failed
/// (<see cref="PlaybackStopInfo.Failed"/>), before the server handles it. Only looks at the
/// report already read; never changes or stops a request.
/// </summary>
public sealed class KostvPlaybackFailureFilter : IActionFilter
{
    private readonly KostvPlaybackFailures _failures;

    public KostvPlaybackFailureFilter(KostvPlaybackFailures failures)
    {
        _failures = failures;
    }

    public void OnActionExecuting(ActionExecutingContext context)
    {
        try
        {
            Note(context.ActionArguments.Values, context.HttpContext.User, _failures, DateTimeOffset.UtcNow);
        }
        catch
        {
            // Never in the way of the server's own work.
        }
    }

    public void OnActionExecuted(ActionExecutedContext context)
    {
    }

    /// <summary>Notes the failed stop report among <paramref name="arguments"/>, if any, for the person of <paramref name="user"/>.</summary>
    internal static bool Note(IEnumerable<object?> arguments, ClaimsPrincipal? user, KostvPlaybackFailures failures, DateTimeOffset now)
    {
        foreach (var argument in arguments)
        {
            if (argument is PlaybackStopInfo { Failed: true } info && info.ItemId != Guid.Empty)
            {
                var claim = user?.FindFirst("Jellyfin-UserId")?.Value ?? user?.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (Guid.TryParse(claim, out var userId))
                {
                    failures.Note(userId, info.ItemId, now);
                    return true;
                }
            }
        }

        return false;
    }
}

/// <summary>
/// kOS TV: notes each song people listen to, from any app (the server says when a song starts,
/// goes on and stops, and when a session ends), and each heart put on or taken off a song, an
/// album or an artist, in <see cref="KostvMusicStore"/>. Of each listen also its session and the
/// song before, how it really ended, shuffle and repeat, replays and how often it was taken back.
/// Only music, only for whoever hasn't turned Learn off. Drops what is past its two years daily,
/// and a person's music when their user is deleted (see <see cref="KostvMusicOnUserDeleted"/>;
/// the daily round also drops the folders of users deleted while the plugin was off).
/// </summary>
public sealed class KostvMusicRecorder : IHostedService
{
    /// <summary>A song still open this long after it was last heard of is let go of, unnoted.</summary>
    internal static readonly TimeSpan OpenFor = TimeSpan.FromHours(6);

    /// <summary>A song this close to its end when it stopped played to the end.</summary>
    internal static readonly TimeSpan EndSlack = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Stopped without saying where, but the server says it played to the end: it did when it
    /// has been playing about as long as it lasts, this much short at most (the time it took to
    /// start, or a pause the app didn't tell).
    /// </summary>
    internal static readonly TimeSpan EndHintSlack = TimeSpan.FromSeconds(15);

    /// <summary>A song stopped this recently is not taken up again by a late report of its progress.</summary>
    internal static readonly TimeSpan ClosedFor = TimeSpan.FromMinutes(2);

    /// <summary>
    /// A song taken up from a report of its progress this recently is the same listen when its
    /// start arrives late, not one more.
    /// </summary>
    internal static readonly TimeSpan AdoptedFor = TimeSpan.FromSeconds(10);

    /// <summary>An artist not found is looked for again after this (it may not have been scanned yet).</summary>
    internal static readonly TimeSpan ArtistMissingFor = TimeSpan.FromHours(1);

    /// <summary>Another song starting on the same session this soon after a stop makes it ended by «next».</summary>
    internal static readonly TimeSpan NextWithin = TimeSpan.FromSeconds(5);

    /// <summary>
    /// How long a listen stopped short is held, waiting for the next song's start, before it is
    /// written as stopped (a little more than <see cref="NextWithin"/>).
    /// </summary>
    internal static readonly TimeSpan HoldFor = TimeSpan.FromSeconds(6);

    /// <summary>Taken back more than this within a song, while it played, counts as going back.</summary>
    internal const double SeekBackSeconds = 5;

    private static readonly TimeSpan FirstTrimAfter = TimeSpan.FromMinutes(10);

    /// <summary>The daily round goes this long after the music day starts at home, so it is past it.</summary>
    internal static readonly TimeSpan RoundAfterDayStart = TimeSpan.FromMinutes(1);

    private readonly ISessionManager _sessions;
    private readonly IUserDataManager _userData;
    private readonly ILibraryManager _library;
    private readonly KostvMusicStore _store;
    private readonly KostvMusicContext _context;
    private readonly ILogger<KostvMusicRecorder> _logger;
    private readonly IServiceProvider? _services;
    private readonly KostvPlaybackFailures? _failures;
    private readonly CancellationTokenSource _stopping = new();

    // The listen stopped short on each session, held for the next song's start (see HoldFor).
    private readonly ConcurrentDictionary<string, Held> _held = new(StringComparer.Ordinal);

    // The song playing on each session, by session (or device) and song.
    private readonly ConcurrentDictionary<string, Open> _open = new(StringComparer.Ordinal);

    // The songs stopped lately, by session and song, and when: a late report of their progress
    // doesn't open them again.
    private readonly ConcurrentDictionary<string, DateTimeOffset> _closed = new(StringComparer.Ordinal);

    // Artist names to their ids, and when an id was looked for (one not found is looked for again).
    private readonly ConcurrentDictionary<string, (string? Id, DateTimeOffset At)> _artistIds = new(StringComparer.OrdinalIgnoreCase);

    // The listens and hearts on their way to the store.
    private readonly ConcurrentDictionary<Task, byte> _pending = new();

    /// <summary>A song that started on a session and hasn't stopped yet.</summary>
    internal sealed class Open
    {
        public required Guid UserId { get; init; }

        public required BaseItem Item { get; init; }

        public required DateTimeOffset StartedAt { get; init; }

        public required string Device { get; init; }

        /// <summary>Where it was when it started, in seconds (a song taken up again mid way).</summary>
        public double StartPosition { get; init; }

        /// <summary>Where it was at the last report of its progress that said so, in seconds.</summary>
        public double? Position { get; set; }

        /// <summary>When it was last heard of.</summary>
        public DateTimeOffset SeenAt { get; set; }

        /// <summary>When this was opened.</summary>
        public DateTimeOffset OpenedAt { get; init; }

        /// <summary>Whether it was paused at the last report.</summary>
        public bool Paused { get; set; }

        /// <summary>The seconds it has been playing (not paused) up to <see cref="SeenAt"/>.</summary>
        public double PlayingSeconds { get; set; }

        /// <summary>Taken up from a report of its progress, before (or without) its start.</summary>
        public bool Adopted { get; set; }

        /// <summary>Whether shuffle was on at the last report that said; null while none did.</summary>
        public bool? Shuffle { get; set; }

        /// <summary>The repeat mode at the last report that said; null while none did.</summary>
        public string? Repeat { get; set; }

        /// <summary>How many times it was taken back more than <see cref="SeekBackSeconds"/> while it played.</summary>
        public int SeekBack { get; set; }
    }

    /// <summary>A listen stopped short, waiting to know whether another song followed.</summary>
    private sealed class Held
    {
        public required Open Open { get; init; }

        public required KostvMusicEvent Entry { get; init; }

        public required DateTimeOffset StoppedAt { get; init; }
    }

    public KostvMusicRecorder(
        ISessionManager sessions,
        IUserDataManager userData,
        ILibraryManager library,
        KostvMusicStore store,
        KostvMusicContext context,
        ILogger<KostvMusicRecorder> logger,
        IServiceProvider? services = null,
        KostvPlaybackFailures? failures = null,
        KostvMusicService? music = null)
    {
        _sessions = sessions;
        _userData = userData;
        _library = library;
        _store = store;
        _context = context;
        _logger = logger;
        _services = services;
        _failures = failures;
        // Kos TV: no longer needed (a heart counts from the next music day); still taken, as
        // the server and the tests give it.
        _ = music;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _sessions.PlaybackStart += OnStart;
        _sessions.PlaybackProgress += OnProgress;
        _sessions.PlaybackStopped += OnStopped;
        _sessions.SessionEnded += OnSessionEnded;
        _userData.UserDataSaved += OnUserDataSaved;
        _ = TrimDailyAsync(_stopping.Token);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _stopping.Cancel();
        _sessions.PlaybackStart -= OnStart;
        _sessions.PlaybackProgress -= OnProgress;
        _sessions.PlaybackStopped -= OnStopped;
        _sessions.SessionEnded -= OnSessionEnded;
        _userData.UserDataSaved -= OnUserDataSaved;
        // Nothing more can follow what is held: stopped.
        ReleaseAllHeld();
        try
        {
            // What is on its way, and then the tastes not written yet.
            Task.WaitAll(_pending.Keys.ToArray(), TimeSpan.FromSeconds(5));
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: a listen on its way failed as the server stopped");
        }

        try
        {
            _store.FlushTastes();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: the tastes could not be written as the server stopped");
        }

        return Task.CompletedTask;
    }

    private async Task TrimDailyAsync(CancellationToken token)
    {
        try
        {
            await Task.Delay(FirstTrimAfter, token).ConfigureAwait(false);
            while (!token.IsCancellationRequested)
            {
                try
                {
                    var gone = _store.RemoveMissingUsers(ServerUsers());
                    if (gone > 0)
                    {
                        _logger.LogInformation("kOS TV music: the music of {Count} users no longer on the server dropped", gone);
                    }

                    var removed = _store.TrimAll();
                    if (removed > 0)
                    {
                        _logger.LogInformation("kOS TV music: {Count} months of listens past their two years dropped", removed);
                    }

                    // Once a day, each taste worked out in full again (it is brought up to date
                    // as each listen is noted the rest of the day).
                    _store.RecomputeTastes();
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "kOS TV music: the daily round (old listens, users gone, tastes) failed");
                }

                // Then each day as the music day starts at home (5:00), not a day after the start.
                await Task.Delay(NextRoundIn(_store.Now, _store.Zone), token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    /// <summary>How long from <paramref name="now"/> until the next daily round: just after the next music day starts at home.</summary>
    internal static TimeSpan NextRoundIn(DateTimeOffset now, TimeZoneInfo zone)
    {
        var next = KostvMusicEngine.DayStart(KostvMusicEngine.MusicDay(now, zone).AddDays(1), zone) + RoundAfterDayStart;
        var wait = next - now;
        // Bounded, should the clock or the zone jump.
        return wait < TimeSpan.FromMinutes(1) ? TimeSpan.FromMinutes(1) : wait > TimeSpan.FromHours(26) ? TimeSpan.FromHours(26) : wait;
    }

    // ---------------------------------------------------------------- playback

    // Jellyfin says when a song starts and stops off the request (in no fixed order between them)
    // and its progress on it, so they can arrive out of order: a progress after the stop, a
    // progress before the start, the next song's start before the last one's stop.
    private static string SessionKey(PlaybackProgressEventArgs e) =>
        e.Session?.Id ?? e.DeviceId ?? e.Session?.DeviceId ?? string.Empty;

    // The User the event carries changed type in 10.11, so the person is read from the session,
    // or else by reflection.
    private static Guid UserOf(PlaybackProgressEventArgs e)
    {
        if (e.Session is { } session && session.UserId != Guid.Empty)
        {
            return session.UserId;
        }

        var users = e.GetType().GetProperty("Users")?.GetValue(e) as System.Collections.IEnumerable;
        var first = users?.Cast<object>().FirstOrDefault();
        return first?.GetType().GetProperty("Id")?.GetValue(first) is Guid id ? id : Guid.Empty;
    }

    // A position only when one is said: 0 is where a song starts, and what some apps send when
    // they don't know, so it tells nothing of how far it got.
    private static double? Seconds(long? ticks) => ticks is > 0 ? TimeSpan.FromTicks(ticks.Value).TotalSeconds : null;

    private static string ItemKey(string sessionKey, BaseItem item) => sessionKey + "|" + item.Id.ToString("N");

    /// <summary>
    /// Whether shuffle is on and the repeat mode (none, all or one), from a session's PlayState,
    /// read by name, as they aren't in every server version: RepeatMode, and PlaybackOrder or
    /// ShuffleMode, whichever there is. Null for what it doesn't have.
    /// </summary>
    internal static (bool? Shuffle, string? Repeat) PlayModeOf(object? playState)
    {
        if (playState == null)
        {
            return (null, null);
        }

        string? Read(string name)
        {
            try
            {
                return playState.GetType().GetProperty(name)?.GetValue(playState)?.ToString()?.Trim().ToLowerInvariant();
            }
            catch
            {
                return null;
            }
        }

        bool? shuffle = (Read("PlaybackOrder") ?? Read("ShuffleMode")) switch
        {
            "shuffle" => true,
            "default" or "sorted" => false,
            _ => null
        };
        var repeat = Read("RepeatMode") switch
        {
            "repeatnone" or "none" => "none",
            "repeatall" or "all" => "all",
            "repeatone" or "one" => "one",
            _ => null
        };
        return (shuffle, repeat);
    }

    // Whether the stop says the playback failed: on the event, if a server version has it there,
    // or as the app's report said (see KostvPlaybackFailureFilter).
    private bool FailedOf(PlaybackStopEventArgs e, Guid userId, Guid itemId, DateTimeOffset now)
    {
        var said = false;
        try
        {
            said = e.GetType().GetProperty("Failed")?.GetValue(e) is true;
        }
        catch
        {
        }

        var reported = _failures?.Take(userId, itemId, now) ?? false;
        return said || reported;
    }

    internal void OnStart(object? sender, PlaybackProgressEventArgs e)
    {
        try
        {
            if (e.Item is not Audio item)
            {
                return;
            }

            var userId = UserOf(e);
            if (userId == Guid.Empty)
            {
                return;
            }

            var session = SessionKey(e);
            var key = ItemKey(session, item);
            var now = _store.Now;
            var mode = PlayModeOf(e.Session?.PlayState);
            Open? adopted = null;

            // The last song of the session stopped a moment ago: this one followed it.
            ReleaseHeld(session, now);

            // The session moved on to another song without saying the last one stopped.
            foreach (var (openKey, open) in _open.Where(kv => kv.Key.StartsWith(session + "|", StringComparison.Ordinal)).ToList())
            {
                // Its progress was told before its start arrived: the same listen, not one more.
                if (openKey == key && open.Adopted && now - open.OpenedAt <= AdoptedFor)
                {
                    adopted = open;
                    continue;
                }

                if (_open.TryRemove(openKey, out _))
                {
                    Close(session, openKey, open, null, false, now, KostvListenEnd.Next);
                }
            }

            SweepStale(now);
            if (adopted != null)
            {
                lock (adopted)
                {
                    adopted.Adopted = false;
                    adopted.Shuffle = mode.Shuffle ?? adopted.Shuffle;
                    adopted.Repeat = mode.Repeat ?? adopted.Repeat;
                }

                return;
            }

            if (!_store.Learns(userId))
            {
                return;
            }

            _closed.TryRemove(key, out _);
            _open[key] = new Open
            {
                UserId = userId,
                Item = item,
                StartedAt = now,
                Device = KostvDeviceKind.Of(e.ClientName ?? e.Session?.Client, e.DeviceName ?? e.Session?.DeviceName),
                StartPosition = Seconds(e.PlaybackPositionTicks) ?? 0,
                SeenAt = now,
                OpenedAt = now,
                Paused = e.IsPaused,
                Shuffle = mode.Shuffle,
                Repeat = mode.Repeat
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a song that started failed");
        }
    }

    internal void OnProgress(object? sender, PlaybackProgressEventArgs e)
    {
        try
        {
            if (e.Item is not Audio item)
            {
                return;
            }

            var session = SessionKey(e);
            var key = ItemKey(session, item);
            var now = _store.Now;
            var mode = PlayModeOf(e.Session?.PlayState);
            if (_open.TryGetValue(key, out var open))
            {
                Touch(open, now, e.IsPaused, Seconds(e.PlaybackPositionTicks), mode);
                return;
            }

            // Stopped a moment ago: a report that arrived late, not the song again.
            if (_closed.TryGetValue(key, out var closedAt) && now - closedAt <= ClosedFor)
            {
                return;
            }

            // Already playing when the server started, or its start not here yet: taken up from
            // where it is, but only while the session is playing it.
            if (e.IsPaused || e.Session?.NowPlayingItem?.Id != item.Id)
            {
                return;
            }

            var userId = UserOf(e);
            if (userId == Guid.Empty || !_store.Learns(userId))
            {
                return;
            }

            // Playing a song the session didn't say it started: the last one, stopped a moment
            // ago, was followed by it.
            ReleaseHeld(session, now);
            var position = Seconds(e.PlaybackPositionTicks);
            _open.TryAdd(key, new Open
            {
                UserId = userId,
                Item = item,
                StartedAt = now - TimeSpan.FromSeconds(position ?? 0),
                Device = KostvDeviceKind.Of(e.ClientName ?? e.Session?.Client, e.DeviceName ?? e.Session?.DeviceName),
                StartPosition = position ?? 0,
                Position = position,
                SeenAt = now,
                OpenedAt = now,
                Adopted = true,
                Shuffle = mode.Shuffle,
                Repeat = mode.Repeat
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: following a song failed");
        }
    }

    internal void OnStopped(object? sender, PlaybackStopEventArgs e)
    {
        try
        {
            if (e.Item is not Audio item)
            {
                return;
            }

            var session = SessionKey(e);
            var key = ItemKey(session, item);
            var now = _store.Now;
            if (_open.TryRemove(key, out var open))
            {
                var endedBy = FailedOf(e, open.UserId, item.Id, now) ? KostvListenEnd.Error : null;
                Close(session, key, open, Seconds(e.PlaybackPositionTicks), e.PlayedToCompletion, now, endedBy);
            }
            else
            {
                _closed[key] = now;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a song that stopped failed");
        }
    }

    /// <summary>A session ended (the app closed, or the server let it go): what played on it ended with it.</summary>
    internal void OnSessionEnded(object? sender, SessionEventArgs e)
    {
        try
        {
            if (e.SessionInfo is not { } info)
            {
                return;
            }

            var now = _store.Now;
            foreach (var session in new[] { info.Id, info.DeviceId }.Where(s => !string.IsNullOrEmpty(s)).Distinct(StringComparer.Ordinal))
            {
                if (_held.TryRemove(session!, out var held))
                {
                    Release(held, KostvListenEnd.Closed);
                }

                foreach (var (openKey, open) in _open.Where(kv => kv.Key.StartsWith(session + "|", StringComparison.Ordinal)).ToList())
                {
                    if (_open.TryRemove(openKey, out _))
                    {
                        Close(session!, openKey, open, null, false, now, KostvListenEnd.Closed);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a session that ended failed");
        }
    }

    /// <summary>
    /// What a report of its progress says of <paramref name="open"/>: where it is, whether it is
    /// paused, shuffle and repeat, and whether it was taken back more than
    /// <see cref="SeekBackSeconds"/> from where it should be by now (only while it plays, and not
    /// when it starts over from its end, as with repeat one).
    /// </summary>
    private static void Touch(Open open, DateTimeOffset now, bool paused, double? position, (bool? Shuffle, string? Repeat) mode)
    {
        lock (open)
        {
            var running = open.Paused ? 0 : Math.Max(0, (now - open.SeenAt).TotalSeconds);
            if (position is { } at && !open.Paused && !paused)
            {
                var expected = (open.Position ?? open.StartPosition + open.PlayingSeconds) + running;
                double? duration = open.Item.RunTimeTicks is > 0 ? TimeSpan.FromTicks(open.Item.RunTimeTicks.Value).TotalSeconds : null;
                var startedOver = duration is { } length && expected >= length - EndHintSlack.TotalSeconds && at <= SeekBackSeconds;
                if (at < expected - SeekBackSeconds && !startedOver)
                {
                    open.SeekBack++;
                }
            }

            open.PlayingSeconds += running;
            open.SeenAt = now;
            open.Paused = paused;
            if (position.HasValue)
            {
                open.Position = position;
            }

            open.Shuffle = mode.Shuffle ?? open.Shuffle;
            open.Repeat = mode.Repeat ?? open.Repeat;
        }
    }

    private void SweepStale(DateTimeOffset now)
    {
        foreach (var (key, open) in _open)
        {
            if (now - open.SeenAt > OpenFor)
            {
                _open.TryRemove(key, out _);
            }
        }

        foreach (var (key, at) in _closed)
        {
            if (now - at > ClosedFor)
            {
                _closed.TryRemove(key, out _);
            }
        }
    }

    /// <summary>
    /// Notes the listen of <paramref name="open"/> on <paramref name="session"/>, which stopped at
    /// <paramref name="position"/> seconds, if said, and ended by <paramref name="endedBy"/> unless
    /// it played to its end. One stopped short, with nothing else said, is held until the next
    /// song's start tells it was «next», or for <see cref="HoldFor"/>, after which it was «stop».
    /// </summary>
    private void Close(string session, string key, Open open, double? position, bool playedToCompletion, DateTimeOffset now, string? endedBy)
    {
        _closed[key] = now;
        var entry = ListenOf(
            open,
            position,
            now,
            _context.SourceOf(open.UserId, open.Item.Id, now),
            playedToCompletion,
            _context.MixGenreOf(open.UserId, open.Item.Id, now),
            endedBy);
        if (entry.EndedBy != null)
        {
            Note(open, entry, now);
            return;
        }

        var held = new Held { Open = open, Entry = entry, StoppedAt = now };
        // Only one listen is held per session: one left there has nothing following it.
        if (_held.TryRemove(session, out var earlier))
        {
            Release(earlier, KostvListenEnd.Stop);
        }

        _held[session] = held;
        _ = ReleaseLaterAsync(session, held);
    }

    /// <summary>Writes the listen held for <paramref name="session"/>, if any: «next» when it stopped within <see cref="NextWithin"/>.</summary>
    private void ReleaseHeld(string session, DateTimeOffset now)
    {
        if (_held.TryRemove(session, out var held))
        {
            Release(held, now - held.StoppedAt <= NextWithin ? KostvListenEnd.Next : KostvListenEnd.Stop);
        }
    }

    private async Task ReleaseLaterAsync(string session, Held held)
    {
        try
        {
            await Task.Delay(HoldFor, _stopping.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // Let go of when the server stops.
            return;
        }

        // Unless a start or the session's end took it meanwhile.
        if (_held.TryRemove(new KeyValuePair<string, Held>(session, held)))
        {
            Release(held, KostvListenEnd.Stop);
        }
    }

    private void ReleaseAllHeld()
    {
        foreach (var pair in _held)
        {
            if (_held.TryRemove(pair))
            {
                Release(pair.Value, KostvListenEnd.Stop);
            }
        }
    }

    private void Release(Held held, string endedBy)
    {
        try
        {
            held.Entry.EndedBy = endedBy;
            Note(held.Open, held.Entry, held.StoppedAt);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a listen failed");
        }
    }

    /// <summary>
    /// Links <paramref name="entry"/>, which ended at <paramref name="endedAt"/>, to the person's
    /// listen before (see <see cref="KostvMusicStore.Link"/>) here, in the order they end, and
    /// writes it.
    /// </summary>
    private void Note(Open open, KostvMusicEvent entry, DateTimeOffset endedAt)
    {
        try
        {
            _store.Link(open.UserId, entry, endedAt);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: the listen before could not be read");
        }

        // Off this thread: reading the artists asks the library.
        Later(() =>
        {
            Describe(entry, open.Item);
            _store.Append(open.UserId, entry);
        });
    }

    private void Later(Action work)
    {
        var task = Task.Run(() =>
        {
            try
            {
                work();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "kOS TV music: noting a listen or a heart failed");
            }
        });
        _pending[task] = 0;
        task.ContinueWith(done => _pending.TryRemove(done, out _), TaskScheduler.Default);
    }

    /// <summary>
    /// When what is on its way to the store has got there (for tests). A listen held for the next
    /// song's start is let go of first, as stopped.
    /// </summary>
    internal Task Settled()
    {
        ReleaseAllHeld();
        return Task.WhenAll(_pending.Keys.ToList());
    }

    /// <summary>
    /// The listen of <paramref name="open"/>, without what the library says of the song nor the
    /// listen before. How far it got: where it stopped (<paramref name="position"/>) when the app
    /// said; else where the last report of its progress put it, plus the time since unless
    /// paused; else how long it has been playing. Without the position, the server saying it
    /// played to the end (<paramref name="playedToCompletion"/>) counts when that time is about as
    /// long as the song. How it ended: error when <paramref name="endedBy"/> says; else natural
    /// when it played to its end; else <paramref name="endedBy"/> (null while not known).
    /// </summary>
    internal KostvMusicEvent ListenOf(
        Open open,
        double? position,
        DateTimeOffset now,
        string? source,
        bool playedToCompletion = false,
        string? mixGenre = null,
        string? endedBy = null)
    {
        double? duration = open.Item.RunTimeTicks is > 0 ? TimeSpan.FromTicks(open.Item.RunTimeTicks.Value).TotalSeconds : null;
        double played;
        bool reachedEnd;
        if (position is { } stoppedAt)
        {
            played = stoppedAt;
            reachedEnd = duration.HasValue && stoppedAt >= duration.Value - EndSlack.TotalSeconds;
        }
        else
        {
            lock (open)
            {
                var running = open.Paused ? 0 : Math.Max(0, (now - open.SeenAt).TotalSeconds);
                played = open.Position is { } last ? last + running : open.StartPosition + open.PlayingSeconds + running;
            }

            reachedEnd = duration is { } length &&
                (played >= length - EndSlack.TotalSeconds || (playedToCompletion && played >= length - EndHintSlack.TotalSeconds));
        }

        played = Math.Max(0, played);
        if (duration.HasValue)
        {
            played = Math.Min(played, duration.Value);
        }

        bool? shuffle;
        string? repeat;
        int seekBack;
        lock (open)
        {
            shuffle = open.Shuffle;
            repeat = open.Repeat;
            seekBack = open.SeekBack;
        }

        return new KostvMusicEvent
        {
            Type = KostvMusicEvent.ListenType,
            Item = open.Item.Id.ToString("N"),
            Played = (int)Math.Round(played),
            Duration = duration.HasValue ? (int)Math.Round(duration.Value) : null,
            Outcome = KostvListenOutcome.Classify(played, duration, reachedEnd),
            Device = open.Device,
            Source = source,
            MixGenre = source != null && source.StartsWith("mix:", StringComparison.Ordinal) ? mixGenre : null,
            EndedBy = endedBy == KostvListenEnd.Error ? endedBy : reachedEnd ? KostvListenEnd.Natural : endedBy,
            Shuffle = shuffle,
            Repeat = repeat,
            SeekBack = seekBack > 0 ? seekBack : null
        }.Stamp(open.StartedAt, _store.Zone);
    }

    /// <summary>Fills in the album, artists and genres of <paramref name="item"/>.</summary>
    private void Describe(KostvMusicEvent entry, BaseItem item)
    {
        var audio = item as Audio;
        entry.Album = audio?.AlbumEntity?.Id.ToString("N") ?? (item.ParentId == Guid.Empty ? null : item.ParentId.ToString("N"));
        var artists = (audio?.Artists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (artists.Count == 0)
        {
            artists = (audio?.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        }

        entry.Artists = artists.Count > 0 ? artists : null;
        var ids = artists.Select(ArtistIdOf).OfType<string>().ToList();
        entry.ArtistIds = ids.Count > 0 ? ids : null;
        var genres = (item.Genres ?? []).Where(g => !string.IsNullOrWhiteSpace(g)).ToList();
        entry.Genres = genres.Count > 0 ? genres : null;
    }

    /// <summary>Fills in the artists and genres of the album or artist <paramref name="item"/> with a heart.</summary>
    private void DescribeFavorite(KostvMusicEvent entry, BaseItem item)
    {
        List<string> artists;
        if (item is MusicArtist)
        {
            artists = string.IsNullOrWhiteSpace(item.Name) ? [] : [item.Name.Trim()];
            entry.ArtistIds = [item.Id.ToString("N")];
        }
        else
        {
            var album = item as MusicAlbum;
            artists = (album?.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            if (artists.Count == 0)
            {
                artists = (album?.Artists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            }

            var ids = artists.Select(ArtistIdOf).OfType<string>().ToList();
            entry.ArtistIds = ids.Count > 0 ? ids : null;
        }

        entry.Artists = artists.Count > 0 ? artists : null;
        var genres = (item.Genres ?? []).Where(g => !string.IsNullOrWhiteSpace(g)).ToList();
        entry.Genres = genres.Count > 0 ? genres : null;
    }

    /// <summary>The id of the artist <paramref name="name"/>; one not found is looked for again after <see cref="ArtistMissingFor"/>.</summary>
    internal string? ArtistIdOf(string name)
    {
        var now = _store.Now;
        if (_artistIds.TryGetValue(name, out var known) && (known.Id != null || now - known.At < ArtistMissingFor))
        {
            return known.Id;
        }

        string? id = null;
        try
        {
            // Asked by name, not GetArtist, which makes the artist when it isn't there.
            id = _library.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.MusicArtist],
                Name = name,
                Recursive = true,
                Limit = 1,
                EnableTotalRecordCount = false
            }).FirstOrDefault()?.Id.ToString("N");
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: an artist could not be read");
        }

        _artistIds[name] = (id, now);
        return id;
    }

    /// <summary>The ids of the server's users, or none when any of them can't be read.</summary>
    private IReadOnlyCollection<Guid> ServerUsers()
    {
        try
        {
            if (_services == null || UserReflection.AllUsers(_services) is not { } users)
            {
                return [];
            }

            var ids = new List<Guid>();
            foreach (var user in users)
            {
                if (user?.GetType().GetProperty("Id")?.GetValue(user) is not Guid id || id == Guid.Empty)
                {
                    // Without everyone, a folder could be taken for a deleted user's.
                    return [];
                }

                ids.Add(id);
            }

            return ids;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: the server's users could not be read");
            return [];
        }
    }

    // ---------------------------------------------------------------- hearts

    internal void OnUserDataSaved(object? sender, UserDataSaveEventArgs e)
    {
        try
        {
            // A song's heart is a "heart"; an album's or an artist's, a "favorite" of that kind.
            string? kind;
            switch (e.Item)
            {
                case Audio:
                    kind = null;
                    break;
                case MusicAlbum:
                    kind = KostvMusicEvent.AlbumKind;
                    break;
                case MusicArtist:
                    kind = KostvMusicEvent.ArtistKind;
                    break;
                default:
                    return;
            }

            var item = e.Item;
            if (e.UserData == null)
            {
                return;
            }

            // Saved for every bit of progress too: only the heart and an app saving the
            // person's data mark it.
            if (e.SaveReason is not (UserDataSaveReason.UpdateUserRating or UserDataSaveReason.UpdateUserData))
            {
                return;
            }

            var favorite = e.UserData.IsFavorite;
            // The last heart noted, also from before a restart (read from the person's files).
            var had = _store.HeartOf(e.UserId, item.Id);
            if (had != favorite)
            {
                _store.SetHeart(e.UserId, item.Id, favorite);
            }

            // Never noted before: only a heart put on is told apart. A save without one is of
            // something else (a rating, the person's data), not a heart taken off; and data saved
            // with one on is a heart put on before, not now.
            var changed = had.HasValue ? had.Value != favorite : favorite && e.SaveReason == UserDataSaveReason.UpdateUserRating;
            if (!changed)
            {
                return;
            }

            // Kos TV: a heart counts from the next music day (the server's hearts are read then,
            // and with Learn on it is noted), not by making the whole day's music again now: that
            // read the library afresh on each heart and changed the daily mixes halfway through the day.
            if (!_store.Learns(e.UserId))
            {
                return;
            }

            var entry = new KostvMusicEvent
            {
                Type = kind == null ? KostvMusicEvent.HeartType : KostvMusicEvent.FavoriteType,
                Item = item.Id.ToString("N"),
                Kind = kind,
                Favorite = favorite
            }.Stamp(_store.Now, _store.Zone);
            var userId = e.UserId;
            Later(() =>
            {
                if (kind == null)
                {
                    Describe(entry, item);
                }
                else
                {
                    DescribeFavorite(entry, item);
                }

                _store.Append(userId, entry);
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a heart failed");
        }
    }
}

/// <summary>kOS TV: forgets a person's music when their user is deleted.</summary>
public sealed class KostvMusicOnUserDeleted : IEventConsumer<UserDeletedEventArgs>
{
    private readonly KostvMusicStore _store;
    private readonly KostvMusicContext _context;
    private readonly KostvMusicService _music;

    public KostvMusicOnUserDeleted(KostvMusicStore store, KostvMusicContext context, KostvMusicService music)
    {
        _store = store;
        _context = context;
        _music = music;
    }

    public Task OnEvent(UserDeletedEventArgs eventArgs)
    {
        // The User the event carries changed type in 10.11, so its id is read by reflection.
        var user = eventArgs.GetType().GetProperty("Argument")?.GetValue(eventArgs);
        if (user?.GetType().GetProperty("Id")?.GetValue(user) is Guid id)
        {
            _store.DeleteUser(id);
            _context.Forget(id);
            _music.Forget(id);
        }

        return Task.CompletedTask;
    }
}
