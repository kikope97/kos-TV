using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Services;

/// <summary>
/// Shared scaffold for the file-backed JSON caches: data-path resolution, serializer
/// options, flush-to-disk, and the lazy double-checked load. Subclasses add their own
/// typed accessors over the dictionary returned by <see cref="EnsureLoaded"/>.
/// </summary>
/// <typeparam name="TEntry">The cache entry type persisted as the dictionary value.</typeparam>
public abstract class FileBackedCacheService<TEntry>
    where TEntry : class
{
    private readonly string _cacheFilePath;
    private readonly string _displayName;
    private readonly ILogger _logger;
    private readonly SemaphoreSlim _fileLock = new(1, 1);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private ConcurrentDictionary<string, TEntry>? _cache;
    private long _snapshotSeq;
    private long _writtenSeq;

    /// <summary>
    /// Kos TV: runs <paramref name="read"/> under the lock the entries change under, for a
    /// subclass whose entries are changed in place under a lock of its own. By default the
    /// dictionary's own safety is enough.
    /// </summary>
    protected virtual T WithEntriesLocked<T>(Func<T> read) => read();

    protected FileBackedCacheService(ILogger logger, string cacheFileName, string displayName)
    {
        _logger = logger;
        _displayName = displayName;
        var dataPath = MoonfinPlugin.Instance?.DataFolderPath
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Jellyfin", "plugins", "Moonfin");

        if (!Directory.Exists(dataPath))
        {
            Directory.CreateDirectory(dataPath);
        }

        _cacheFilePath = Path.Combine(dataPath, cacheFileName);
    }

    public async Task FlushAsync()
    {
        var cache = _cache;
        if (cache == null) return;

        // Kos TV: the copy is taken under the subclass's own lock (the one its entries change
        // under), then written through a temp file and a rename (keeping a .bak), so a crash
        // or a full disk midway never leaves the stored data half written. Some of these
        // caches hold what people chose (their list, what they dismissed, when they marked a
        // favourite), not just what can be fetched again.
        string json;
        int count;
        long seq;
        try
        {
            (json, count, seq) = WithEntriesLocked(() =>
                (JsonSerializer.Serialize(new Dictionary<string, TEntry>(cache, StringComparer.OrdinalIgnoreCase), JsonOptions),
                 cache.Count,
                 Interlocked.Increment(ref _snapshotSeq)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to flush {CacheName} cache to disk", _displayName);
            return;
        }

        await _fileLock.WaitAsync().ConfigureAwait(false);
        try
        {
            // A newer copy already went to disk: this older one would undo it.
            if (seq < _writtenSeq) return;
            _writtenSeq = seq;
            await AtomicFile.WriteAllTextAsync(_cacheFilePath, json).ConfigureAwait(false);
            _logger.LogDebug("{CacheName} cache flushed to disk ({Count} entries)", _displayName, count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to flush {CacheName} cache to disk", _displayName);
        }
        finally
        {
            _fileLock.Release();
        }
    }

    /// <summary>
    /// Empties the cache and writes the cleared state to disk so it survives a restart.
    /// Returns how many entries were dropped.
    /// </summary>
    public async Task<int> ClearAsync()
    {
        var cache = EnsureLoaded();
        var removed = cache.Count;
        cache.Clear();
        await FlushAsync().ConfigureAwait(false);
        _logger.LogInformation("{CacheName} cache cleared ({Count} entries removed)", _displayName, removed);
        return removed;
    }

    protected ConcurrentDictionary<string, TEntry> EnsureLoaded()
    {
        if (_cache != null) return _cache;

        _fileLock.Wait();
        try
        {
            if (_cache != null) return _cache;

            // Kos TV: the file, or its .bak when the file is missing or broken.
            var loaded = AtomicFile.ReadWithRecovery(
                _cacheFilePath,
                text => JsonSerializer.Deserialize<Dictionary<string, TEntry>>(text, JsonOptions));
            if (loaded != null)
            {
                _cache = new ConcurrentDictionary<string, TEntry>(loaded, StringComparer.OrdinalIgnoreCase);
                _logger.LogInformation("{CacheName} cache loaded from disk ({Count} entries)", _displayName, _cache.Count);
            }
            else
            {
                if (File.Exists(_cacheFilePath))
                {
                    // Neither copy could be read: the broken one is put aside rather than written
                    // over by the next flush, so what it held can still be looked at.
                    SetAside(_cacheFilePath);
                    _logger.LogWarning("Failed to load {CacheName} cache from disk, starting fresh (the unreadable file was kept beside it)", _displayName);
                }

                _cache = new ConcurrentDictionary<string, TEntry>(StringComparer.OrdinalIgnoreCase);
            }
        }
        finally
        {
            _fileLock.Release();
        }

        return _cache;
    }

    private void SetAside(string path)
    {
        try
        {
            File.Move(path, $"{path}.broken-{DateTime.UtcNow:yyyyMMddHHmmss}", overwrite: true);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not put the unreadable {CacheName} cache aside", _displayName);
        }
    }
}
