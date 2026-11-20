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
/// a person's music when their user is deleted (see <see cref="KostvMusicOnUserDeleted"/>).
/// </summary>
public sealed class KostvMusicRecorder : IHostedService
{
    /// <summary>A song still open this long after it was last heard of is let go of, unnoted.</summary>
    internal static readonly TimeSpan OpenFor = TimeSpan.FromHours(6);

    /// <summary>A song this close to its end when it stopped played to the end.</summary>
    internal static readonly TimeSpan EndSlack = TimeSpan.FromSeconds(3);

    private static readonly TimeSpan TrimEvery = TimeSpan.FromDays(1);
    private static readonly TimeSpan FirstTrimAfter = TimeSpan.FromMinutes(10);

    private readonly ISessionManager _sessions;
    private readonly IUserDataManager _userData;
    private readonly ILibraryManager _library;
    private readonly KostvMusicStore _store;
    private readonly KostvMusicContext _context;
    private readonly ILogger<KostvMusicRecorder> _logger;
    private readonly CancellationTokenSource _stopping = new();

    // The song playing on each session, by session (or device) and song.
    private readonly ConcurrentDictionary<string, Open> _open = new(StringComparer.Ordinal);

    // The last heart noted per person and song, so saving a rating with it doesn't note it again.
    private readonly ConcurrentDictionary<(Guid User, Guid Item), bool> _hearts = new();

    // Artist names to their ids, read once.
    private readonly ConcurrentDictionary<string, string?> _artistIds = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>A song that started on a session and hasn't stopped yet.</summary>
    internal sealed class Open
    {
        public required Guid UserId { get; init; }

        public required BaseItem Item { get; init; }

        public required DateTimeOffset StartedAt { get; init; }

        public required string Device { get; init; }

        public double? Position { get; set; }

        public DateTimeOffset SeenAt { get; set; }
    }

    public KostvMusicRecorder(
        ISessionManager sessions,
        IUserDataManager userData,
        ILibraryManager library,
        KostvMusicStore store,
        KostvMusicContext context,
        ILogger<KostvMusicRecorder> logger)
    {
        _sessions = sessions;
        _userData = userData;
        _library = library;
        _store = store;
        _context = context;
        _logger = logger;
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

    private static double? Seconds(long? ticks) => ticks is > 0 ? TimeSpan.FromTicks(ticks.Value).TotalSeconds : ticks == 0 ? 0 : null;

    private void OnStart(object? sender, PlaybackProgressEventArgs e)
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

            var key = SessionKey(e);
            var now = _store.Now;

            // The session moved on to another song without saying the last one stopped.
            foreach (var (openKey, open) in _open.Where(kv => kv.Key.StartsWith(key + "|", StringComparison.Ordinal)).ToList())
            {
                if (_open.TryRemove(openKey, out _))
                {
                    Finish(open, open.Position, now);
                }
            }

            SweepStale(now);
            if (!_store.Learns(userId))
            {
                return;
            }

            _open[key + "|" + item.Id.ToString("N")] = new Open
            {
                UserId = userId,
                Item = item,
                StartedAt = now,
                Device = KostvDeviceKind.Of(e.ClientName ?? e.Session?.Client, e.DeviceName ?? e.Session?.DeviceName),
                Position = Seconds(e.PlaybackPositionTicks),
                SeenAt = now
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a song that started failed");
        }
    }

    private void OnProgress(object? sender, PlaybackProgressEventArgs e)
    {
        try
        {
            if (e.Item is not Audio item)
            {
                return;
            }

            var key = SessionKey(e) + "|" + item.Id.ToString("N");
            var now = _store.Now;
            if (_open.TryGetValue(key, out var open))
            {
                open.Position = Seconds(e.PlaybackPositionTicks) ?? open.Position;
                open.SeenAt = now;
                return;
            }

            // Already playing when the server started: noted from where it is now.
            var userId = UserOf(e);
            if (userId == Guid.Empty || !_store.Learns(userId))
            {
                return;
            }

            var position = Seconds(e.PlaybackPositionTicks) ?? 0;
            _open[key] = new Open
            {
                UserId = userId,
                Item = item,
                StartedAt = now - TimeSpan.FromSeconds(position),
                Device = KostvDeviceKind.Of(e.ClientName ?? e.Session?.Client, e.DeviceName ?? e.Session?.DeviceName),
                Position = position,
                SeenAt = now
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: following a song failed");
        }
    }

    private void OnStopped(object? sender, PlaybackStopEventArgs e)
    {
        try
        {
            if (e.Item is not Audio item)
            {
                return;
            }

            if (_open.TryRemove(SessionKey(e) + "|" + item.Id.ToString("N"), out var open))
            {
                Finish(open, Seconds(e.PlaybackPositionTicks) ?? open.Position, _store.Now);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: noting a song that stopped failed");
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
    }

    /// <summary>Notes the listen of <paramref name="open"/>, which stopped at <paramref name="position"/> seconds.</summary>
    private void Finish(Open open, double? position, DateTimeOffset now)
    {
        var entry = ListenOf(open, position, now, _context.SourceOf(open.UserId, open.Item.Id, now));
        // Off this thread: reading the artists asks the library.
        _ = Task.Run(() =>
        {
            try
            {
                Describe(entry, open.Item);
                _store.Append(open.UserId, entry);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "kOS TV music: noting a listen failed");
            }
        });
    }

    /// <summary>
    /// The listen of <paramref name="open"/> stopped at <paramref name="position"/> seconds (or,
    /// unsaid, as long as it has been playing), without what the library says of the song.
    /// </summary>
    internal KostvMusicEvent ListenOf(Open open, double? position, DateTimeOffset now, string? source)
    {
        double? duration = open.Item.RunTimeTicks is > 0 ? TimeSpan.FromTicks(open.Item.RunTimeTicks.Value).TotalSeconds : null;
        var played = position ?? Math.Max(0, (now - open.StartedAt).TotalSeconds);
        if (duration.HasValue)
        {
            played = Math.Min(played, duration.Value);
        }

        var reachedEnd = position.HasValue && duration.HasValue && position.Value >= duration.Value - EndSlack.TotalSeconds;
        return new KostvMusicEvent
        {
            Type = KostvMusicEvent.ListenType,
            Item = open.Item.Id.ToString("N"),
            Played = (int)Math.Round(played),
            Duration = duration.HasValue ? (int)Math.Round(duration.Value) : null,
            Outcome = KostvListenOutcome.Classify(played, duration, reachedEnd),
            Device = open.Device,
            Source = source
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

    private string? ArtistIdOf(string name) => _artistIds.GetOrAdd(name, n =>
    {
        try
        {
            // Asked by name, not GetArtist, which makes the artist when it isn't there.
            return _library.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.MusicArtist],
                Name = n,
                Recursive = true,
                Limit = 1,
                EnableTotalRecordCount = false
            }).FirstOrDefault()?.Id.ToString("N");
        }
        catch
        {
            return null;
        }
    });

    // ---------------------------------------------------------------- hearts

    private void OnUserDataSaved(object? sender, UserDataSaveEventArgs e)
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
            var key = (e.UserId, item.Id);
            if (_hearts.TryGetValue(key, out var had) ? had == favorite : !favorite && e.SaveReason == UserDataSaveReason.UpdateUserData)
            {
                // The same as last noted, or data saved for a song that never had a heart.
                _hearts[key] = favorite;
                return;
            }

            _hearts[key] = favorite;
            if (!_store.Learns(e.UserId))
            {
                return;
            }

            var entry = new KostvMusicEvent
            {
                Type = KostvMusicEvent.HeartType,
                Item = item.Id.ToString("N"),
                Favorite = favorite
            }.Stamp(_store.Now, _store.Zone);
            _ = Task.Run(() =>
            {
                try
                {
                    Describe(entry, item);
                    _store.Append(e.UserId, entry);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "kOS TV music: noting a heart failed");
                }
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
