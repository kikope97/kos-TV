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
    private const int SeedTries = 5;

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
                if (SeedAll())
                {
                    await _dates.FlushAsync().ConfigureAwait(false);
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

    // Whether anyone's were noted.
    private bool SeedAll()
    {
        var any = false;
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

            var favorites = _libraryManager.GetItemList(query).Select(i => i.Id.ToString("N"));
            any |= _dates.Seed(id, favorites);
        }

        return any;
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
