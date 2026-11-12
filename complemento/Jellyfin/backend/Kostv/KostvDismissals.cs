using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>A title someone said they aren't interested in.</summary>
public sealed class KostvDismissedTitle
{
    /// <summary>The TMDB title, "movie:123" or "tv:45".</summary>
    [JsonPropertyName("key")]
    public string Key { get; set; } = string.Empty;

    [JsonPropertyName("at")]
    public DateTimeOffset At { get; set; }
}

/// <summary>Everything one person turned down, the newest last.</summary>
public sealed class KostvDismissedList
{
    [JsonPropertyName("titles")]
    public List<KostvDismissedTitle> Titles { get; set; } = [];
}

/// <summary>
/// kOS TV: what each person said they aren't interested in, from the home page, on disk. Kept
/// by TMDB title so it holds when the file is replaced or the item re-added.
/// </summary>
public sealed class KostvDismissals : FileBackedCacheService<KostvDismissedList>
{
    /// <summary>The most kept per person; the oldest go first.</summary>
    public const int MaxPerPerson = 500;

    private readonly object _lock = new();

    public KostvDismissals(ILogger<KostvDismissals> logger)
        : base(logger, "kostv-home-dismissed.json", "kOS TV not interested")
    {
    }

    private static string KeyOf(Guid userId) => userId.ToString("N");

    /// <summary>The titles <paramref name="userId"/> turned down, the newest last.</summary>
    public IReadOnlyList<string> For(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var list)
                ? list.Titles.Select(t => t.Key).ToList()
                : [];
        }
    }

    /// <summary>Notes <paramref name="key"/> as turned down; false when it already was.</summary>
    public bool Add(Guid userId, string key)
    {
        lock (_lock)
        {
            var list = EnsureLoaded().GetOrAdd(KeyOf(userId), _ => new KostvDismissedList());
            if (list.Titles.Any(t => t.Key == key))
            {
                return false;
            }

            list.Titles.Add(new KostvDismissedTitle { Key = key, At = DateTimeOffset.UtcNow });
            if (list.Titles.Count > MaxPerPerson)
            {
                list.Titles.RemoveRange(0, list.Titles.Count - MaxPerPerson);
            }

            return true;
        }
    }

    /// <summary>Takes <paramref name="key"/> back; false when it wasn't there.</summary>
    public bool Remove(Guid userId, string key)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var list) &&
                list.Titles.RemoveAll(t => t.Key == key) > 0;
        }
    }
}
