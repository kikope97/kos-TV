using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>A film or series someone put on their list.</summary>
public sealed class KostvMyListEntry
{
    /// <summary>The home server's item, without dashes.</summary>
    [JsonPropertyName("itemId")]
    public string ItemId { get; set; } = string.Empty;

    /// <summary>The TMDB title ("movie:123", "tv:45"), when it has one.</summary>
    [JsonPropertyName("key")]
    public string? Key { get; set; }

    [JsonPropertyName("addedAt")]
    public DateTimeOffset AddedAt { get; set; }
}

/// <summary>One person's list, the newest last, and what was put on it for them.</summary>
public sealed class KostvMyListData
{
    [JsonPropertyName("items")]
    public List<KostvMyListEntry> Items { get; set; } = [];

    /// <summary>
    /// The titles once put on the list by themselves, when something the person asked for
    /// arrived: never put back by themselves, so taking one off sticks.
    /// </summary>
    [JsonPropertyName("arrived")]
    public List<string> Arrived { get; set; } = [];
}

/// <summary>
/// kOS TV: each person's list of what they want to watch («Mi lista»), on disk. The same on
/// every device of theirs.
/// </summary>
public sealed class KostvMyList : FileBackedCacheService<KostvMyListData>
{
    /// <summary>The most kept per person.</summary>
    public const int MaxPerPerson = 1000;

    private readonly object _lock = new();

    public KostvMyList(ILogger<KostvMyList> logger)
        : base(logger, "kostv-my-list.json", "kOS TV my list")
    {
    }

    private static string KeyOf(Guid userId) => userId.ToString("N");

    /// <summary>The list of <paramref name="userId"/>, the newest first.</summary>
    public IReadOnlyList<KostvMyListEntry> For(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data)
                ? data.Items.AsEnumerable().Reverse().Select(e => new KostvMyListEntry { ItemId = e.ItemId, Key = e.Key, AddedAt = e.AddedAt }).ToList()
                : [];
        }
    }

    /// <summary>
    /// Puts <paramref name="itemId"/> on the list; false when it already was, or, with
    /// <paramref name="arrived"/>, when it once went on by itself already.
    /// </summary>
    public bool Add(Guid userId, string itemId, string? key, bool arrived = false)
    {
        lock (_lock)
        {
            var data = EnsureLoaded().GetOrAdd(KeyOf(userId), _ => new KostvMyListData());
            if (arrived)
            {
                var mark = key ?? itemId;
                if (data.Arrived.Contains(mark))
                {
                    return false;
                }

                data.Arrived.Add(mark);
            }

            if (data.Items.Any(e => e.ItemId == itemId))
            {
                return arrived;
            }

            data.Items.Add(new KostvMyListEntry { ItemId = itemId, Key = key, AddedAt = DateTimeOffset.UtcNow });
            if (data.Items.Count > MaxPerPerson)
            {
                data.Items.RemoveRange(0, data.Items.Count - MaxPerPerson);
            }

            return true;
        }
    }

    /// <summary>Takes <paramref name="itemIds"/> off the list; how many were on it.</summary>
    public int Remove(Guid userId, IReadOnlyCollection<string> itemIds)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data)
                ? data.Items.RemoveAll(e => itemIds.Contains(e.ItemId))
                : 0;
        }
    }
}
