using System.Collections.Concurrent;
using Jellyfin.Data.Enums;
using Jellyfin.Data.Events.Users;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Events;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Entities;
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
/// kOS TV: notes each song people listen to, from any app (the server says when a song starts
/// and stops), and each heart put on or taken off a song, in <see cref="KostvMusicStore"/>.
/// Only music, only for whoever hasn't turned Learn off. Drops what is past its year daily, and
/// a person's music when their user is deleted (see <see cref="KostvMusicOnUserDeleted"/>; the
/// daily round also drops the folders of users deleted while the plugin was off).
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

    private static readonly TimeSpan TrimEvery = TimeSpan.FromDays(1);
    private static readonly TimeSpan FirstTrimAfter = TimeSpan.FromMinutes(10);

    private readonly ISessionManager _sessions;
    private readonly IUserDataManager _userData;
    private readonly ILibraryManager _library;
    private readonly KostvMusicStore _store;
    private readonly KostvMusicContext _context;
    private readonly ILogger<KostvMusicRecorder> _logger;
    private readonly IServiceProvider? _services;
    private readonly CancellationTokenSource _stopping = new();

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
    }

    public KostvMusicRecorder(
        ISessionManager sessions,
        IUserDataManager userData,
        ILibraryManager library,
        KostvMusicStore store,
        KostvMusicContext context,
        ILogger<KostvMusicRecorder> logger,
        IServiceProvider? services = null)
    {
        _sessions = sessions;
        _userData = userData;
        _library = library;
        _store = store;
        _context = context;
        _logger = logger;
        _services = services;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _sessions.PlaybackStart += OnStart;
        _sessions.PlaybackProgress += OnProgress;
        _sessions.PlaybackStopped += OnStopped;
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
        _userData.UserDataSaved -= OnUserDataSaved;
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
                        _logger.LogInformation("kOS TV music: {Count} months of listens past their year dropped", removed);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "kOS TV music: dropping old listens failed");
                }

                await Task.Delay(TrimEvery, token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
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
            Open? adopted = null;

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
                    Close(openKey, open, null, false, now);
                }
            }

            SweepStale(now);
            if (adopted != null)
            {
                lock (adopted)
                {
                    adopted.Adopted = false;
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
                Paused = e.IsPaused
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

            var key = ItemKey(SessionKey(e), item);
            var now = _store.Now;
            if (_open.TryGetValue(key, out var open))
            {
                Touch(open, now, e.IsPaused, Seconds(e.PlaybackPositionTicks));
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
                Adopted = true
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

            var key = ItemKey(SessionKey(e), item);
            var now = _store.Now;
            if (_open.TryRemove(key, out var open))
            {
                Close(key, open, Seconds(e.PlaybackPositionTicks), e.PlayedToCompletion, now);
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

    /// <summary>What a report of its progress says of <paramref name="open"/>.</summary>
    private static void Touch(Open open, DateTimeOffset now, bool paused, double? position)
    {
        lock (open)
        {
            if (!open.Paused)
            {
                open.PlayingSeconds += Math.Max(0, (now - open.SeenAt).TotalSeconds);
            }

            open.SeenAt = now;
            open.Paused = paused;
            if (position.HasValue)
            {
                open.Position = position;
            }
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

    private void Close(string key, Open open, double? position, bool playedToCompletion, DateTimeOffset now)
    {
        _closed[key] = now;
        Finish(open, position, playedToCompletion, now);
    }

    /// <summary>Notes the listen of <paramref name="open"/>, which stopped at <paramref name="position"/> seconds, if said.</summary>
    private void Finish(Open open, double? position, bool playedToCompletion, DateTimeOffset now)
    {
        var entry = ListenOf(
            open,
            position,
            now,
            _context.SourceOf(open.UserId, open.Item.Id, now),
            playedToCompletion,
            _context.MixGenreOf(open.UserId, open.Item.Id, now));
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

    /// <summary>When what is on its way to the store has got there (for tests).</summary>
    internal Task Settled() => Task.WhenAll(_pending.Keys.ToList());

    /// <summary>
    /// The listen of <paramref name="open"/>, without what the library says of the song. How far
    /// it got: where it stopped (<paramref name="position"/>) when the app said; else where the
    /// last report of its progress put it, plus the time since unless paused; else how long it
    /// has been playing. Without the position, the server saying it played to the end
    /// (<paramref name="playedToCompletion"/>) counts when that time is about as long as the song.
    /// </summary>
    internal KostvMusicEvent ListenOf(
        Open open,
        double? position,
        DateTimeOffset now,
        string? source,
        bool playedToCompletion = false,
        string? mixGenre = null)
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

        return new KostvMusicEvent
        {
            Type = KostvMusicEvent.ListenType,
            Item = open.Item.Id.ToString("N"),
            Played = (int)Math.Round(played),
            Duration = duration.HasValue ? (int)Math.Round(duration.Value) : null,
            Outcome = KostvListenOutcome.Classify(played, duration, reachedEnd),
            Device = open.Device,
            Source = source,
            MixGenre = source != null && source.StartsWith("mix:", StringComparison.Ordinal) ? mixGenre : null
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
            if (e.Item is not Audio item || e.UserData == null)
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
            if (!changed || !_store.Learns(e.UserId))
            {
                return;
            }

            var entry = new KostvMusicEvent
            {
                Type = KostvMusicEvent.HeartType,
                Item = item.Id.ToString("N"),
                Favorite = favorite
            }.Stamp(_store.Now, _store.Zone);
            var userId = e.UserId;
            Later(() =>
            {
                Describe(entry, item);
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
