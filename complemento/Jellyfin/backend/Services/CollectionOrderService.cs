using System.Text.Json;

namespace Moonfin.Server.Services;

/// <summary>
/// Stores a per-user custom ordering of the items in a collection, as a JSON array of item-id
/// strings under <c>collections/{userId}/{collectionId}.json</c>. Item ids stay opaque because
/// Jellyfin uses GUIDs and Emby uses numeric ids, so the same store works against either server.
/// </summary>
public class CollectionOrderService
{
    private readonly string _rootPath;
    private static readonly SemaphoreSlim _lock = new(1, 1);

    private const int MaxItems = 5000;

    /// <summary>Kos TV: an order of a collection that is gone is kept this long untouched before it goes.</summary>
    public static readonly TimeSpan OrphanAfter = TimeSpan.FromDays(30);

    public CollectionOrderService()
    {
        var dataPath = MoonfinPlugin.Instance?.DataFolderPath
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Jellyfin", "plugins", "Moonfin");
        _rootPath = Path.Combine(dataPath, "collections");
    }

    /// <summary>Kos TV: the store under <paramref name="rootPath"/>, for the tests.</summary>
    internal CollectionOrderService(string rootPath)
    {
        _rootPath = rootPath;
    }

    /// <summary>
    /// Kos TV: whether <paramref name="collectionId"/> can name a stored order (it keeps some
    /// letters or digits), so a bad one is answered as such instead of failing.
    /// </summary>
    public bool IsValidId(Guid userId, string? collectionId) => ResolvePath(userId, collectionId ?? string.Empty) != null;

    /// <summary>Returns the stored order for the user+collection, or an empty list when none is set.</summary>
    public async Task<List<string>> GetAsync(Guid userId, string collectionId, CancellationToken cancellationToken)
    {
        var path = ResolvePath(userId, collectionId);
        if (path == null)
        {
            return new List<string>();
        }

        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // Kos TV: the file, or its .bak when the file was cut short, instead of an empty order.
            return AtomicFile.ReadWithRecovery(path, text => JsonSerializer.Deserialize<List<string>>(text))
                ?? new List<string>();
        }
        catch
        {
            return new List<string>();
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Saves the order. An empty list deletes the stored file.</summary>
    public async Task SaveAsync(Guid userId, string collectionId, List<string> itemIds, CancellationToken cancellationToken)
    {
        var path = ResolvePath(userId, collectionId);
        if (path == null)
        {
            throw new ArgumentException("Invalid collection id.", nameof(collectionId));
        }

        var normalized = Normalize(itemIds);

        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (normalized.Count == 0)
            {
                AtomicFile.DeleteWithSidecars(path);
                return;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            // Kos TV: through a temp file and a rename (keeping a .bak), so a crash or a full disk
            // midway never leaves the order someone dragged by hand half written.
            await AtomicFile.WriteAllTextAsync(path, JsonSerializer.Serialize(normalized), cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>
    /// Kos TV: forgets the person's orders of collections that no longer exist
    /// (<paramref name="exists"/> says no) and haven't been touched in <see cref="OrphanAfter"/>,
    /// so their folder doesn't keep growing. Only orders named by an item id are judged; how many
    /// went.
    /// </summary>
    public async Task<int> PruneAsync(Guid userId, Func<Guid, bool> exists, CancellationToken cancellationToken)
    {
        var folder = Path.Combine(_rootPath, userId.ToString("N"));
        if (!Directory.Exists(folder))
        {
            return 0;
        }

        var removed = 0;
        await _lock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var before = DateTime.UtcNow - OrphanAfter;
            foreach (var file in Directory.EnumerateFiles(folder, "*.json"))
            {
                if (Guid.TryParseExact(Path.GetFileNameWithoutExtension(file), "N", out var id) &&
                    File.GetLastWriteTimeUtc(file) < before &&
                    !exists(id))
                {
                    AtomicFile.DeleteWithSidecars(file);
                    removed++;
                }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Tidying only: what is left is tried again next time.
        }
        finally
        {
            _lock.Release();
        }

        return removed;
    }

    // Drops blanks and duplicates, keeps the first occurrence so the drag order survives, and caps the count.
    private static List<string> Normalize(List<string>? itemIds)
    {
        var result = new List<string>();
        if (itemIds == null) return result;

        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var id in itemIds)
        {
            if (string.IsNullOrWhiteSpace(id)) continue;
            var trimmed = id.Trim();
            if (!seen.Add(trimmed)) continue;
            result.Add(trimmed);
            if (result.Count >= MaxItems) break;
        }
        return result;
    }

    private string? ResolvePath(Guid userId, string collectionId)
    {
        var safeCollection = SanitizeFileName(collectionId);
        if (safeCollection.Length == 0)
        {
            return null;
        }

        var path = Path.GetFullPath(Path.Combine(_rootPath, userId.ToString("N"), $"{safeCollection}.json"));

        // Make sure the resolved path stays inside the collections root.
        var rootFull = Path.GetFullPath(_rootPath);
        var rootWithSep = rootFull.EndsWith(Path.DirectorySeparatorChar) ? rootFull : rootFull + Path.DirectorySeparatorChar;
        return path.StartsWith(rootWithSep, StringComparison.Ordinal) ? path : null;
    }

    // Collection ids are GUIDs on Jellyfin and numeric on Emby. Keeping only alphanumerics stops
    // the id escaping the folder while leaving both forms intact.
    private static string SanitizeFileName(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var chars = value.Where(char.IsLetterOrDigit).ToArray();
        var sanitized = new string(chars);
        return sanitized.Length > 128 ? sanitized[..128] : sanitized;
    }
}
