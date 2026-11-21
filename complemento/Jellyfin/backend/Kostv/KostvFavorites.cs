using MediaBrowser.Model.Entities;
using System.Text.Json.Serialization;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>One person's favourites as kOS TV keeps them: since when each one is.</summary>
public sealed class KostvFavoriteData
{
    /// <summary>When each favourite was marked, by item (without dashes).</summary>
    [JsonPropertyName("since")]
    public Dictionary<string, DateTimeOffset> Since { get; set; } = new(StringComparer.Ordinal);

    /// <summary>When the person last saw the news of their favourite series.</summary>
    [JsonPropertyName("newsSeenAt")]
    public DateTimeOffset? NewsSeenAt { get; set; }

    /// <summary>
    /// Kos TV: favourites that already were before their moment was kept, by item. Never dated,
    /// so rating one (the server saves a rating the way it saves the heart) doesn't make it the
    /// newest favourite.
    /// </summary>
    [JsonPropertyName("undated")]
    public HashSet<string> Undated { get; set; } = new(StringComparer.Ordinal);

    /// <summary>Kos TV: whether <see cref="Undated"/> was filled from the server's favourites.</summary>
    [JsonPropertyName("seeded")]
    public bool Seeded { get; set; }

    /// <summary>
    /// Kos TV: since when each item of <see cref="Since"/> or <see cref="Undated"/> hasn't been on
    /// the server, so it is let go of only once it has been gone a while (see
    /// <see cref="KostvFavoriteDates.GoneGrace"/>).
    /// </summary>
    [JsonPropertyName("goneSince")]
    public Dictionary<string, DateTimeOffset> GoneSince { get; set; } = new(StringComparer.Ordinal);
}

/// <summary>
/// kOS TV: when each person marked each of their favourites, which the server itself doesn't
/// keep, and when they last saw the news of their favourite series. On disk.
/// </summary>
public sealed class KostvFavoriteDates : FileBackedCacheService<KostvFavoriteData>
{
    private readonly object _lock = new();

    /// <summary>The entries change under <see cref="_lock"/>, so they are written out under it.</summary>
    protected override T WithEntriesLocked<T>(Func<T> read)
    {
        lock (_lock)
        {
            return read();
        }
    }

    public KostvFavoriteDates(ILogger<KostvFavoriteDates> logger)
        : base(logger, "kostv-favorites.json", "kOS TV favourites")
    {
    }

    private static string KeyOf(Guid userId) => userId.ToString("N");

    /// <summary>
    /// Notes that <paramref name="itemId"/> is a favourite of <paramref name="userId"/> from
    /// <paramref name="at"/>, or with <paramref name="favorite"/> false that it no longer is.
    /// False when nothing changed: already noted, or never was.
    /// </summary>
    public bool Mark(Guid userId, Guid itemId, bool favorite, DateTimeOffset at)
    {
        var id = itemId.ToString("N");
        lock (_lock)
        {
            var data = EnsureLoaded().GetOrAdd(KeyOf(userId), _ => new KostvFavoriteData());
            if (favorite)
            {
                // Kos TV: a favourite from before is still one, not a new one.
                return !data.Undated.Contains(id) && data.Since.TryAdd(id, at);
            }

            var undated = data.Undated.Remove(id);
            return data.Since.Remove(id) || undated;
        }
    }

    /// <summary>Kos TV: whether <paramref name="userId"/>'s favourites from before are noted.</summary>
    public bool IsSeeded(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data) && data.Seeded;
        }
    }

    /// <summary>
    /// Kos TV: notes <paramref name="favorites"/>, the server's favourites of
    /// <paramref name="userId"/> now, as favourites from before, except those already dated.
    /// Once per person; false when already done.
    /// </summary>
    public bool Seed(Guid userId, IEnumerable<string> favorites)
    {
        lock (_lock)
        {
            var data = EnsureLoaded().GetOrAdd(KeyOf(userId), _ => new KostvFavoriteData());
            if (data.Seeded)
            {
                return false;
            }

            foreach (var id in favorites)
            {
                if (!data.Since.ContainsKey(id))
                {
                    data.Undated.Add(id);
                }
            }

            data.Seeded = true;
            return true;
        }
    }

    /// <summary>Since when each of <paramref name="userId"/>'s favourites is, as far as known.</summary>
    public IReadOnlyDictionary<string, DateTimeOffset> Since(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data)
                ? new Dictionary<string, DateTimeOffset>(data.Since, StringComparer.Ordinal)
                : new Dictionary<string, DateTimeOffset>(StringComparer.Ordinal);
        }
    }

    /// <summary>
    /// Kos TV: how long an item noted here can be gone from the server before it is forgotten.
    /// A disk away during a scan, or a file being replaced, comes back well within it.
    /// </summary>
    public static readonly TimeSpan GoneGrace = TimeSpan.FromDays(30);

    /// <summary>Kos TV: every item noted for <paramref name="userId"/>, dated or from before.</summary>
    public IReadOnlyList<string> Noted(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data)
                ? data.Since.Keys.Concat(data.Undated).Distinct(StringComparer.Ordinal).ToList()
                : [];
        }
    }

    /// <summary>
    /// Kos TV: what a look at the server found of what is noted for <paramref name="userId"/>:
    /// <paramref name="gone"/> isn't there now (marked gone from <paramref name="now"/>, and
    /// forgotten once gone for <see cref="GoneGrace"/>); the rest of what is noted is there.
    /// Whether anything changed, so the caller writes it out.
    /// </summary>
    public bool Sweep(Guid userId, IReadOnlyCollection<string> gone, DateTimeOffset now)
    {
        lock (_lock)
        {
            if (!EnsureLoaded().TryGetValue(KeyOf(userId), out var data))
            {
                return false;
            }

            var changed = false;
            foreach (var id in data.GoneSince.Keys.Where(id => !gone.Contains(id)).ToList())
            {
                // Back, or no longer noted.
                data.GoneSince.Remove(id);
                changed = true;
            }

            foreach (var id in gone)
            {
                if (!data.Since.ContainsKey(id) && !data.Undated.Contains(id))
                {
                    continue;
                }

                if (!data.GoneSince.TryGetValue(id, out var since))
                {
                    data.GoneSince[id] = now;
                    changed = true;
                }
                else if (now - since >= GoneGrace)
                {
                    data.Since.Remove(id);
                    data.Undated.Remove(id);
                    data.GoneSince.Remove(id);
                    changed = true;
                }
            }

            return changed;
        }
    }

    /// <summary>When <paramref name="userId"/> last saw the news of their favourite series.</summary>
    public DateTimeOffset? NewsSeenAt(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data) ? data.NewsSeenAt : null;
        }
    }

    /// <summary><paramref name="userId"/> has just seen the news of their favourite series.</summary>
    public void NewsSeen(Guid userId, DateTimeOffset at)
    {
        lock (_lock)
        {
            EnsureLoaded().GetOrAdd(KeyOf(userId), _ => new KostvFavoriteData()).NewsSeenAt = at;
        }
    }
}

/// <summary>
/// kOS TV: notes the moment someone marks or unmarks a favourite, from any app or the server's
/// own web, so their favourites can be shown newest first.
/// </summary>
public sealed class KostvFavoritesWatcher : IHostedService
{
    // Kos TV: the library is read for the favourites from before once the server is up.
    private static readonly TimeSpan SeedAfter = TimeSpan.FromMinutes(2);
    // Kos TV: every SeedAfter for up to an hour while a library doesn't answer, and again at the
    // next start.
    private const int SeedTries = 30;

    private readonly IUserDataManager _userDataManager;
    private readonly KostvFavoriteDates _dates;
    private readonly ILibraryManager _libraryManager;
    private readonly IServiceProvider _services;
    private readonly ILogger<KostvFavoritesWatcher> _logger;
    private readonly CancellationTokenSource _stopping = new();

    public KostvFavoritesWatcher(
        IUserDataManager userDataManager,
        KostvFavoriteDates dates,
        ILibraryManager libraryManager,
        IServiceProvider services,
        ILogger<KostvFavoritesWatcher> logger)
    {
        _userDataManager = userDataManager;
        _dates = dates;
        _libraryManager = libraryManager;
        _services = services;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _userDataManager.UserDataSaved += OnUserDataSaved;
        _ = SeedLaterAsync(_stopping.Token);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _stopping.Cancel();
        _userDataManager.UserDataSaved -= OnUserDataSaved;
        return _dates.FlushAsync();
    }

    /// <summary>
    /// Kos TV: notes each person's favourites from before as such, once, so rating one later
    /// doesn't date it as just marked. Tried again a few times while the library isn't ready.
    /// </summary>
    private async Task SeedLaterAsync(CancellationToken token)
    {
        for (var attempt = 0; attempt < SeedTries; attempt++)
        {
            try
            {
                await Task.Delay(SeedAfter, token).ConfigureAwait(false);
                var (any, waiting) = SeedAll();
                if (any)
                {
                    await _dates.FlushAsync().ConfigureAwait(false);
                }

                // Kos TV: someone's library didn't answer yet: tried again in a while.
                if (waiting)
                {
                    continue;
                }

                return;
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "kOS TV: noting the favourites from before failed");
            }
        }
    }

    // Whether anyone's were noted, and whether someone's library didn't answer yet.
    private (bool Any, bool Waiting) SeedAll()
    {
        var any = false;
        var waiting = false;
        foreach (var user in UserReflection.AllUsers(_services) ?? Array.Empty<object>())
        {
            if (user.GetType().GetProperty("Id")?.GetValue(user) is not Guid id || _dates.IsSeeded(id))
            {
                continue;
            }

            var query = new InternalItemsQuery { IsFavorite = true, Recursive = true, EnableTotalRecordCount = false };
            // Without the person's limits applied nothing is read, rather than everything.
            if (!UserReflection.ApplyUser(query, user))
            {
                continue;
            }

            // Kos TV: bound by name, so it works on every server version (see LibraryQueries).
            var favorites = LibraryQueries.ItemList(_libraryManager, query).Select(i => i.Id.ToString("N")).ToList();
            // Kos TV: no favourites and nothing at all to see is a library not loaded yet, not a
            // person without favourites: not noted as done, so it is tried again.
            if (favorites.Count == 0 && !SeesAnything(user))
            {
                waiting = true;
                continue;
            }

            any |= _dates.Seed(id, favorites);
        }

        return (any, waiting);
    }

    // Kos TV: whether the library gives the person anything at all.
    private bool SeesAnything(object user)
    {
        var query = new InternalItemsQuery { Recursive = true, Limit = 1, EnableTotalRecordCount = false };
        return UserReflection.ApplyUser(query, user) && LibraryQueries.ItemList(_libraryManager, query).Count > 0;
    }

    private void OnUserDataSaved(object? sender, UserDataSaveEventArgs e)
    {
        try
        {
            if (e.Item == null || e.UserData == null)
            {
                return;
            }

            // Saved for every bit of progress too: only a change of heart is written. A
            // favourite is dated only when it is marked (the heart, or an app saving the
            // person's data); one first met while saving progress was marked before this was
            // kept, so its moment stays unknown instead of being today.
            var marking = e.SaveReason is UserDataSaveReason.UpdateUserRating or UserDataSaveReason.UpdateUserData;
            if (e.UserData.IsFavorite && !marking)
            {
                return;
            }

            if (_dates.Mark(e.UserId, e.Item.Id, e.UserData.IsFavorite, DateTimeOffset.UtcNow))
            {
                _ = _dates.FlushAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV: noting a favourite failed");
        }
    }
}
