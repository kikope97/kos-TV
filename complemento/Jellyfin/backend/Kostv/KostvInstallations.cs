using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Kostv;

/// <summary>One device with the app, as it last asked for an update.</summary>
public sealed class KostvInstallation
{
    [JsonPropertyName("deviceId")]
    public string DeviceId { get; set; } = string.Empty;

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = string.Empty;

    [JsonPropertyName("userId")]
    public string UserId { get; set; } = string.Empty;

    [JsonPropertyName("userName")]
    public string UserName { get; set; } = string.Empty;

    [JsonPropertyName("deviceName")]
    public string DeviceName { get; set; } = string.Empty;

    [JsonPropertyName("versionCode")]
    public long VersionCode { get; set; }

    [JsonPropertyName("lastSeen")]
    public DateTimeOffset LastSeen { get; set; }

    /// <summary>A short, stable id for the panel («Quitar»), made from the device and the kind.</summary>
    [JsonIgnore]
    public string Id => KostvInstallations.IdOf(DeviceId, Kind);
}

/// <summary>
/// kOS TV: the devices that have the app, recorded each time one asks for an update, so the
/// admin sees who still has to update. One entry per device and kind (tele/móvil); one not seen
/// for <see cref="KeepFor"/> is forgotten (a phone that was replaced doesn't stay for ever).
/// Recording never fails nor makes the app's answer wait: it changes memory and writes the small
/// file afterwards, only when something that matters changed or now and then.
/// </summary>
public sealed class KostvInstallations
{
    public const string FileName = "installations.json";

    /// <summary>More than any family has; keeps a misbehaving client from filling the file.</summary>
    public const int MaxEntries = 500;

    private const int MaxText = 120;

    public static readonly TimeSpan KeepFor = TimeSpan.FromDays(14);

    /// <summary>A check that only moves the date is written at most this often.</summary>
    public static readonly TimeSpan SeenWriteEvery = TimeSpan.FromHours(1);

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    private readonly string _root;
    private readonly Func<DateTimeOffset> _now;
    private readonly ILogger? _logger;
    private readonly bool _background;
    private readonly object _lock = new();
    private readonly object _writeLock = new();
    private Dictionary<string, KostvInstallation>? _entries;
    private DateTimeOffset _savedAt = DateTimeOffset.MinValue;
    private bool _dirty;
    private bool _flushQueued;

    /// <param name="root">The folder of the file (the updates' folder).</param>
    /// <param name="now">The clock (for tests).</param>
    /// <param name="logger">Where a file that can't be read or written is told.</param>
    /// <param name="background">False writes on the caller's thread (for tests).</param>
    public KostvInstallations(string root, Func<DateTimeOffset>? now = null, ILogger? logger = null, bool background = true)
    {
        _root = root;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _logger = logger;
        _background = background;
    }

    private string FilePath => Path.Combine(_root, FileName);

    private static string Key(string deviceId, string kind) => deviceId + "\n" + kind;

    public static string IdOf(string deviceId, string kind) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Key(deviceId, kind))), 0, 8).ToLowerInvariant();

    private static string Clip(string? value)
    {
        var text = (value ?? string.Empty).Trim();
        return text.Length > MaxText ? text[..MaxText] : text;
    }

    // ------------------------------------------------------------------ store

    private Dictionary<string, KostvInstallation> EntriesLocked()
    {
        if (_entries != null)
        {
            return _entries;
        }

        _entries = new Dictionary<string, KostvInstallation>(StringComparer.Ordinal);
        try
        {
            if (File.Exists(FilePath))
            {
                var list = JsonSerializer.Deserialize<List<KostvInstallation>>(File.ReadAllText(FilePath)) ?? [];
                foreach (var entry in list.Where(e => !string.IsNullOrEmpty(e.DeviceId) && KostvUpdates.IsKind(e.Kind)))
                {
                    _entries[Key(entry.DeviceId, entry.Kind)] = entry;
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            // Only a list of who was seen: it fills again as the apps ask.
            _logger?.LogWarning(ex, "kOS TV installations: could not read {Path}; starting empty", FilePath);
        }

        _savedAt = _now();
        return _entries;
    }

    /// <summary>Drops what wasn't seen for <see cref="KeepFor"/>; true if something went.</summary>
    private bool PruneLocked(Dictionary<string, KostvInstallation> entries)
    {
        var limit = _now() - KeepFor;
        var old = entries.Where(e => e.Value.LastSeen < limit).Select(e => e.Key).ToList();
        foreach (var key in old)
        {
            entries.Remove(key);
        }

        return old.Count > 0;
    }

    /// <summary>Writes the file now if something is waiting. Never throws.</summary>
    public void Flush()
    {
        lock (_writeLock)
        {
            string text;
            lock (_lock)
            {
                _flushQueued = false;
                if (!_dirty || _entries == null)
                {
                    return;
                }

                text = JsonSerializer.Serialize(_entries.Values.OrderByDescending(e => e.LastSeen).ToList(), Json);
                _dirty = false;
                _savedAt = _now();
            }

            try
            {
                Directory.CreateDirectory(_root);
                var temp = FilePath + ".tmp";
                File.WriteAllText(temp, text);
                File.Move(temp, FilePath, overwrite: true);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                _logger?.LogWarning(ex, "kOS TV installations: could not write {Path}", FilePath);
                lock (_lock)
                {
                    _dirty = true;
                }
            }
        }
    }

    /// <summary>Called with the lock held: marks a change and has it written.</summary>
    private bool QueueLocked(bool now)
    {
        _dirty = true;
        if (!now && _now() - _savedAt < SeenWriteEvery)
        {
            return false;
        }

        if (_flushQueued)
        {
            return false;
        }

        _flushQueued = true;
        return true;
    }

    private void Write(bool queued)
    {
        if (!queued)
        {
            return;
        }

        if (_background)
        {
            _ = Task.Run(Flush);
        }
        else
        {
            Flush();
        }
    }

    // ------------------------------------------------------------------ recording

    /// <summary>
    /// Notes that <paramref name="deviceId"/> (its <paramref name="kind"/> of app) asked with
    /// <paramref name="versionCode"/>, signed in as that user. Another profile on the same device
    /// takes the entry over. Never throws.
    /// </summary>
    public void Record(string? userId, string? userName, string? deviceId, string? deviceName, string kind, long versionCode)
    {
        try
        {
            var device = Clip(deviceId);
            if (device.Length == 0 || !KostvUpdates.IsKind(kind))
            {
                return;
            }

            bool queued;
            lock (_lock)
            {
                var entries = EntriesLocked();
                var pruned = PruneLocked(entries);
                var key = Key(device, kind);
                var user = Clip(userId);
                var name = Clip(userName);
                var label = Clip(deviceName);
                var important = pruned;
                if (!entries.TryGetValue(key, out var entry))
                {
                    if (entries.Count >= MaxEntries)
                    {
                        // Full: make room by forgetting the one seen longest ago.
                        entries.Remove(entries.MinBy(e => e.Value.LastSeen).Key);
                    }

                    entry = new KostvInstallation { DeviceId = device, Kind = kind };
                    entries[key] = entry;
                    important = true;
                }

                if (entry.UserId != user || entry.UserName != name || entry.VersionCode != versionCode
                    || (label.Length > 0 && entry.DeviceName != label))
                {
                    important = true;
                }

                entry.UserId = user;
                entry.UserName = name;
                if (label.Length > 0)
                {
                    entry.DeviceName = label;
                }

                entry.VersionCode = versionCode;
                entry.LastSeen = _now();
                queued = QueueLocked(important);
            }

            Write(queued);
        }
        catch (Exception ex)
        {
            _logger?.LogWarning(ex, "kOS TV installations: could not record a device");
        }
    }

    // ------------------------------------------------------------------ the panel

    /// <summary>The devices seen in the last <see cref="KeepFor"/>, the most recent first.</summary>
    public List<KostvInstallation> List()
    {
        bool queued = false;
        List<KostvInstallation> copy;
        lock (_lock)
        {
            var entries = EntriesLocked();
            if (PruneLocked(entries))
            {
                queued = QueueLocked(now: true);
            }

            copy = entries.Values
                .OrderBy(e => e.UserName, StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(e => e.Kind, StringComparer.Ordinal)
                .ThenByDescending(e => e.LastSeen)
                .Select(e => new KostvInstallation
                {
                    DeviceId = e.DeviceId,
                    Kind = e.Kind,
                    UserId = e.UserId,
                    UserName = e.UserName,
                    DeviceName = e.DeviceName,
                    VersionCode = e.VersionCode,
                    LastSeen = e.LastSeen
                })
                .ToList();
        }

        Write(queued);
        return copy;
    }

    /// <summary>Forgets one device by its <see cref="KostvInstallation.Id"/>; false if unknown.</summary>
    public bool Remove(string id)
    {
        bool queued;
        lock (_lock)
        {
            var entries = EntriesLocked();
            var key = entries.FirstOrDefault(e => e.Value.Id == id).Key;
            if (key == null)
            {
                return false;
            }

            entries.Remove(key);
            queued = QueueLocked(now: true);
        }

        Write(queued);
        return true;
    }

    // ------------------------------------------------------------------ versions

    /// <summary>
    /// The version a code stands for: <c>(MAJOR*1000000 + MINOR*1000 + PATCH)*100</c>, plus N
    /// for the test build N («1.21.0 (prueba 3)»); 1000000 is 1.0.0, from the old scheme.
    /// </summary>
    public static string VersionName(long code)
    {
        if (code <= 0)
        {
            return "desconocida";
        }

        if (code == 1_000_000)
        {
            return "1.0.0";
        }

        var test = code % 100;
        var number = code / 100;
        var name = string.Create(
            CultureInfo.InvariantCulture,
            $"{number / 1_000_000}.{number / 1000 % 1000}.{number % 1000}");
        return test == 0 ? name : string.Create(CultureInfo.InvariantCulture, $"{name} (prueba {test})");
    }

    /// <summary>
    /// Up to date when it has the newest version on offer for its kind, or a newer one (a test
    /// build of it); with nothing on offer there is nothing to update to.
    /// </summary>
    public static bool IsUpToDate(long versionCode, long? latestCode) =>
        latestCode is not { } latest || versionCode >= latest;
}
