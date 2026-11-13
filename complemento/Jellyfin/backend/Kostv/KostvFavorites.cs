using System.Text.Json.Serialization;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
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
}

/// <summary>
/// kOS TV: when each person marked each of their favourites, which the server itself doesn't
/// keep, and when they last saw the news of their favourite series. On disk.
/// </summary>
public sealed class KostvFavoriteDates : FileBackedCacheService<KostvFavoriteData>
{
    private readonly object _lock = new();

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
                return data.Since.TryAdd(id, at);
            }

            return data.Since.Remove(id);
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
    private readonly IUserDataManager _userDataManager;
    private readonly KostvFavoriteDates _dates;
    private readonly ILogger<KostvFavoritesWatcher> _logger;

    public KostvFavoritesWatcher(
        IUserDataManager userDataManager,
        KostvFavoriteDates dates,
        ILogger<KostvFavoritesWatcher> logger)
    {
        _userDataManager = userDataManager;
        _dates = dates;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _userDataManager.UserDataSaved += OnUserDataSaved;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _userDataManager.UserDataSaved -= OnUserDataSaved;
        return _dates.FlushAsync();
    }

    private void OnUserDataSaved(object? sender, UserDataSaveEventArgs e)
    {
        try
        {
            if (e.Item == null || e.UserData == null)
            {
                return;
            }

            // Saved for every bit of progress too: only a change of heart is written.
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
