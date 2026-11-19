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

    /// <summary>
    /// Kos TV: since when the server hasn't had it, nor anything with its TMDB title (a file
    /// being replaced by a better one, a disk away during a scan). Null while it is there.
    /// </summary>
    [JsonPropertyName("missingSince")]
    public DateTimeOffset? MissingSince { get; set; }
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

    /// <summary>Kos TV: the most marks kept per person of what went on by itself.</summary>
    public const int MaxArrived = 2000;

    /// <summary>
    /// Kos TV: how long a title with a TMDB title can be missing from the server before it
    /// leaves the list. A replaced file comes back with a new id within minutes, and is found
    /// again by its TMDB title; this only lets go of what really went.
    /// </summary>
    public static readonly TimeSpan MissingGrace = TimeSpan.FromDays(7);

    private readonly object _lock = new();

    /// <summary>The entries change under <see cref="_lock"/>, so they are written out under it.</summary>
    protected override T WithEntriesLocked<T>(Func<T> read)
    {
        lock (_lock)
        {
            return read();
        }
    }

    public KostvMyList(ILogger<KostvMyList> logger)
        : base(logger, "kostv-my-list.json", "kOS TV my list")
    {
    }

    private static string KeyOf(Guid userId) => userId.ToString("N");

    /// <summary>
    /// Kos TV: <paramref name="oldId"/> on the person's list is now <paramref name="newId"/> (the
    /// server gave the title a new id); it keeps its place and when it was added. False when it
    /// isn't on the list, or the new id already is.
    /// </summary>
    public bool Repoint(Guid userId, string oldId, string newId)
    {
        lock (_lock)
        {
            if (!EnsureLoaded().TryGetValue(KeyOf(userId), out var data) ||
                data.Items.Any(e => e.ItemId == newId))
            {
                return false;
            }

            var entry = data.Items.FirstOrDefault(e => e.ItemId == oldId);
            if (entry == null)
            {
                return false;
            }

            entry.ItemId = newId;
            entry.MissingSince = null;
            return true;
        }
    }

    /// <summary>The list of <paramref name="userId"/>, the newest first.</summary>
    public IReadOnlyList<KostvMyListEntry> For(Guid userId)
    {
        lock (_lock)
        {
            return EnsureLoaded().TryGetValue(KeyOf(userId), out var data)
                ? data.Items.AsEnumerable().Reverse().Select(e => new KostvMyListEntry { ItemId = e.ItemId, Key = e.Key, AddedAt = e.AddedAt, MissingSince = e.MissingSince }).ToList()
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
                // Kos TV: the latest ones only, so it doesn't grow with everything ever asked for.
                if (data.Arrived.Count > MaxArrived)
                {
                    data.Arrived.RemoveRange(0, data.Arrived.Count - MaxArrived);
                }
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

    /// <summary>
    /// Kos TV: what reading the list found. <paramref name="missing"/> the server doesn't have now:
    /// marked as missing from <paramref name="now"/>, and taken off once missing for
    /// <see cref="MissingGrace"/>. <paramref name="present"/> it has: no longer missing. Whether
    /// anything changed, so the caller writes it out.
    /// </summary>
    public bool Sweep(Guid userId, IReadOnlyCollection<string> missing, IReadOnlyCollection<string> present, DateTimeOffset now)
    {
        lock (_lock)
        {
            if (!EnsureLoaded().TryGetValue(KeyOf(userId), out var data))
            {
                return false;
            }

            var changed = false;
            foreach (var entry in data.Items)
            {
                if (missing.Contains(entry.ItemId))
                {
                    if (entry.MissingSince == null)
                    {
                        entry.MissingSince = now;
                        changed = true;
                    }
                }
                else if (entry.MissingSince != null && present.Contains(entry.ItemId))
                {
                    entry.MissingSince = null;
                    changed = true;
                }
            }

            var gone = data.Items.RemoveAll(e =>
                e.MissingSince is { } since && missing.Contains(e.ItemId) && now - since >= MissingGrace);
            return changed || gone > 0;
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
