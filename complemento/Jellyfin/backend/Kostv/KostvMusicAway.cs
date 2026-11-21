using System.Collections;
using System.Collections.Concurrent;
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Playlists;
using MediaBrowser.Model.Entities;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>kOS TV: a heart of a person on a song not at home, as the taste weighs it: by its artist.</summary>
public sealed record KostvAwayHeart(string DeezerId, string? Artist);

/// <summary>
/// kOS TV: a song not at home («Toda la música»), as the app gives it: in a playlist (a «hueco»
/// of it, with the element before it, <see cref="After"/>) or with a heart of the person's own.
/// </summary>
public sealed class KostvAwaySong
{
    [JsonPropertyName("deezerId")]
    public string DeezerId { get; set; } = string.Empty;

    [JsonPropertyName("title")]
    public string? Title { get; set; }

    [JsonPropertyName("artist")]
    public string? Artist { get; set; }

    [JsonPropertyName("album")]
    public string? Album { get; set; }

    [JsonPropertyName("albumDeezerId")]
    public string? AlbumDeezerId { get; set; }

    [JsonPropertyName("artistDeezerId")]
    public string? ArtistDeezerId { get; set; }

    [JsonPropertyName("cover")]
    public string? Cover { get; set; }

    /// <summary>How long it is, in seconds, when the app said.</summary>
    [JsonPropertyName("duration")]
    public int? Duration { get; set; }

    [JsonPropertyName("explicit")]
    public bool Explicit { get; set; }

    /// <summary>
    /// In a playlist: the element before it in the whole list, an id of the server without dashes
    /// or <c>stremfin:&lt;DeezerId&gt;</c>; null, the first.
    /// </summary>
    [JsonPropertyName("after")]
    public string? After { get; set; }

    [JsonPropertyName("added")]
    public DateTimeOffset Added { get; set; }

    /// <summary>Its key in a playlist's order: <c>stremfin:&lt;DeezerId&gt;</c>.</summary>
    [JsonIgnore]
    public string Key => KostvMusicEvent.StreamedItem(DeezerId);

    public KostvAwaySong Copy() => (KostvAwaySong)MemberwiseClone();
}

/// <summary>
/// kOS TV: the order of a playlist with songs not at home in it: the server's elements in their
/// order, each «hueco» after the element it says (<see cref="KostvAwaySong.After"/>), and those
/// whose element is no longer there at the end, as the app places them.
/// </summary>
public static class KostvAwayOrder
{
    /// <summary>
    /// The whole list: <paramref name="jellyfin"/> (the ids of the server's elements, without
    /// dashes, in their order) with <paramref name="entries"/> placed in it, as keys.
    /// </summary>
    public static List<string> Merged(IReadOnlyList<string> jellyfin, IReadOnlyList<KostvAwaySong> entries)
    {
        var byAfter = new Dictionary<string, List<KostvAwaySong>>(StringComparer.Ordinal);
        foreach (var entry in entries)
        {
            var anchor = entry.After ?? string.Empty;
            if (!byAfter.TryGetValue(anchor, out var list))
            {
                byAfter[anchor] = list = [];
            }

            list.Add(entry);
        }

        var order = new List<string>(jellyfin.Count + entries.Count);
        var placed = new HashSet<string>(StringComparer.Ordinal);

        // Without recursion: a chain of 500 songs not at home, each after the one before.
        void Place(string anchor)
        {
            var stack = new Stack<(List<KostvAwaySong> List, int Next)>();
            if (byAfter.TryGetValue(anchor, out var first))
            {
                stack.Push((first, 0));
            }

            while (stack.Count > 0)
            {
                var (list, next) = stack.Pop();
                if (next >= list.Count)
                {
                    continue;
                }

                stack.Push((list, next + 1));
                var entry = list[next];
                if (placed.Add(entry.Key))
                {
                    order.Add(entry.Key);
                    if (byAfter.TryGetValue(entry.Key, out var after))
                    {
                        stack.Push((after, 0));
                    }
                }
            }
        }

        Place(string.Empty);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var id in jellyfin)
        {
            order.Add(id);
            // The same song twice: what follows it goes after the first.
            if (seen.Add(id))
            {
                Place(id);
            }
        }

        foreach (var entry in entries)
        {
            if (placed.Add(entry.Key))
            {
                order.Add(entry.Key);
                Place(entry.Key);
            }
        }

        return order;
    }

    /// <summary>Why songs could not be added to a playlist.</summary>
    public enum InsertRefusal
    {
        None,

        /// <summary>The list would have more than <see cref="KostvAwayStore.MaxPerPlaylist"/>.</summary>
        TooMany,

        /// <summary>After is one of the songs added.</summary>
        AfterItself
    }

    /// <summary>
    /// Adds <paramref name="songs"/> (those not in it yet; each once) to <paramref name="entries"/>,
    /// one after the other: after <paramref name="after"/> when <paramref name="afterSaid"/> (null,
    /// the first), and at the end of the whole list when not. What was after that element follows
    /// them, so they go right after it.
    /// </summary>
    public static InsertRefusal Insert(
        List<KostvAwaySong> entries,
        IReadOnlyList<string> jellyfin,
        IReadOnlyList<KostvAwaySong> songs,
        bool afterSaid,
        string? after,
        DateTimeOffset now)
    {
        var have = entries.Select(e => e.DeezerId).ToHashSet(StringComparer.Ordinal);
        var added = songs.Where(s => !have.Contains(s.DeezerId)).DistinctBy(s => s.DeezerId).Select(s => s.Copy()).ToList();
        if (added.Count == 0)
        {
            return InsertRefusal.None;
        }

        if (afterSaid && after != null && added.Any(s => s.Key == after))
        {
            return InsertRefusal.AfterItself;
        }

        if (entries.Count + added.Count > KostvAwayStore.MaxPerPlaylist)
        {
            return InsertRefusal.TooMany;
        }

        var anchor = afterSaid ? after : Merged(jellyfin, entries).LastOrDefault();
        var last = added[^1].Key;
        foreach (var entry in entries.Where(e => e.After == anchor))
        {
            entry.After = last;
        }

        var previous = anchor;
        foreach (var song in added)
        {
            song.After = previous;
            song.Added = now;
            previous = song.Key;
        }

        entries.AddRange(added);
        return InsertRefusal.None;
    }

    /// <summary>
    /// Takes <paramref name="deezerId"/> out of <paramref name="entries"/>: what was after it goes
    /// after <paramref name="replacement"/> (by default, what it was after), so it keeps its place.
    /// Whether it was there.
    /// </summary>
    public static bool Remove(List<KostvAwaySong> entries, string deezerId, string? replacement = null, bool replace = false)
    {
        var index = entries.FindIndex(e => e.DeezerId == deezerId);
        if (index < 0)
        {
            return false;
        }

        var gone = entries[index];
        entries.RemoveAt(index);
        var instead = replace ? replacement : gone.After;
        foreach (var entry in entries.Where(e => e.After == gone.Key))
        {
            entry.After = instead;
        }

        return true;
    }

    /// <summary>
    /// The <see cref="KostvAwaySong.After"/> of <paramref name="entries"/> from the whole list as it
    /// is now (<paramref name="ids"/>): each after the element before it there (null, the first).
    /// Those not in it stay as they were, after the rest.
    /// </summary>
    public static void Reorder(List<KostvAwaySong> entries, IReadOnlyList<string> ids)
    {
        var at = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < ids.Count; i++)
        {
            at.TryAdd(ids[i], i);
        }

        foreach (var entry in entries)
        {
            if (at.TryGetValue(entry.Key, out var index))
            {
                entry.After = index == 0 ? null : ids[index - 1];
            }
        }

        var ordered = entries
            .Select((e, i) => (Entry: e, Place: at.TryGetValue(e.Key, out var index) ? index : ids.Count + i))
            .OrderBy(x => x.Place)
            .Select(x => x.Entry)
            .ToList();
        entries.Clear();
        entries.AddRange(ordered);
    }

    /// <summary>
    /// Where the song <paramref name="deezerId"/> goes among the server's elements of the list once
    /// it is at home: how many of them are before it in the whole list.
    /// </summary>
    public static int TargetIndex(IReadOnlyList<string> jellyfin, IReadOnlyList<KostvAwaySong> entries, string deezerId)
    {
        var key = KostvMusicEvent.StreamedItem(deezerId);
        var count = 0;
        foreach (var id in Merged(jellyfin, entries))
        {
            if (id == key)
            {
                return count;
            }

            if (KostvMusicEvent.DeezerIdOf(id) == null)
            {
                count++;
            }
        }

        return count;
    }

    /// <summary>
    /// An element of a playlist as the app names it: an id of the server (any form, given back
    /// without dashes) or <c>stremfin:&lt;DeezerId&gt;</c>; null when it is neither.
    /// </summary>
    public static string? NormalizeId(string? id)
    {
        id = id?.Trim();
        if (string.IsNullOrEmpty(id))
        {
            return null;
        }

        if (KostvMusicEvent.DeezerIdOf(id) is { } deezerId)
        {
            return KostvMusicEvent.StreamedItem(deezerId);
        }

        return Guid.TryParse(id, out var guid) && guid != Guid.Empty ? guid.ToString("N") : null;
    }
}

/// <summary>
/// kOS TV: the songs not at home kept by the plugin, as the server keeps only its own in its
/// playlists and hearts: the «huecos» of each playlist (one file per playlist, under
/// <c>kostv-musica/listas-fuera/</c>, the same for whoever sees it) and each person's hearts
/// (<c>kostv-musica/&lt;user&gt;/fuera-favoritas.json</c>, gone with the person). Written whole
/// through <see cref="AtomicFile"/> (with its <c>.bak</c>), under a lock per playlist (one that can
/// be awaited, as a song arriving waits for the server's playlists) and per person.
/// </summary>
public sealed class KostvAwayStore
{
    /// <summary>The folder of the playlists' songs not at home, under the music's.</summary>
    public const string PlaylistsFolder = "listas-fuera";

    /// <summary>A person's hearts on songs not at home, in their music folder.</summary>
    public const string FavoritesFile = "fuera-favoritas.json";

    /// <summary>The most songs not at home a playlist keeps.</summary>
    public const int MaxPerPlaylist = 500;

    /// <summary>The most hearts on songs not at home a person keeps.</summary>
    public const int MaxFavorites = 2000;

    private readonly string _root;
    private readonly Func<DateTimeOffset> _now;
    private readonly ILogger? _logger;
    private readonly ConcurrentDictionary<Guid, SemaphoreSlim> _playlistLocks = new();
    private readonly ConcurrentDictionary<Guid, object> _userLocks = new();
    private int _version;

    private sealed class PlaylistFile
    {
        [JsonPropertyName("entries")]
        public List<KostvAwaySong>? Entries { get; set; }
    }

    private sealed class FavoritesList
    {
        [JsonPropertyName("songs")]
        public List<KostvAwaySong>? Songs { get; set; }
    }

    /// <param name="root">The folder of everyone's music (<see cref="KostvMusicStore.FolderName"/>).</param>
    /// <param name="now">The clock, so tests can move it.</param>
    /// <param name="logger">Where what can't be stored is told.</param>
    public KostvAwayStore(string root, Func<DateTimeOffset>? now = null, ILogger? logger = null)
    {
        _root = root;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _logger = logger;
    }

    public DateTimeOffset Now => _now();

    /// <summary>Goes up with each change, so what was read of all of them is read again.</summary>
    public int Version => Volatile.Read(ref _version);

    private string PlaylistPath(Guid playlistId) => Path.Combine(_root, PlaylistsFolder, playlistId.ToString("N") + ".json");

    private string FavoritesPath(Guid userId) => Path.Combine(_root, userId.ToString("N"), FavoritesFile);

    /// <summary>The lock of <paramref name="playlistId"/>'s songs not at home, to hold while reading and writing them.</summary>
    public SemaphoreSlim PlaylistLock(Guid playlistId) => _playlistLocks.GetOrAdd(playlistId, _ => new SemaphoreSlim(1, 1));

    private static T? Parse<T>(string text)
        where T : class
    {
        try
        {
            return JsonSerializer.Deserialize<T>(text, KostvMusicStore.LineOptions);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>What is kept of a song, without what isn't one (cut short or written by hand).</summary>
    private static List<KostvAwaySong> Valid(IEnumerable<KostvAwaySong?>? songs) =>
        (songs ?? []).OfType<KostvAwaySong>().Where(s => KostvMusicEvent.IsDeezerId(s.DeezerId) && !string.IsNullOrEmpty(s.Title)).DistinctBy(s => s.DeezerId).ToList();

    // ---------------------------------------------------------------- playlists

    /// <summary>The songs not at home of <paramref name="playlistId"/>, in the order kept (a copy).</summary>
    public List<KostvAwaySong> Entries(Guid playlistId) =>
        Valid(AtomicFile.ReadWithRecovery(PlaylistPath(playlistId), Parse<PlaylistFile>)?.Entries);

    /// <summary>
    /// Stores <paramref name="entries"/> as <paramref name="playlistId"/>'s songs not at home (none,
    /// the file goes). Under its lock. False when not stored.
    /// </summary>
    public bool SaveEntries(Guid playlistId, List<KostvAwaySong> entries)
    {
        try
        {
            var path = PlaylistPath(playlistId);
            if (entries.Count == 0)
            {
                AtomicFile.DeleteWithSidecars(path);
            }
            else
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                AtomicFile.WriteAllText(path, JsonSerializer.Serialize(new PlaylistFile { Entries = entries }, KostvMusicStore.LineOptions));
            }

            Interlocked.Increment(ref _version);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: the songs not at home of a playlist could not be stored");
            return false;
        }
    }

    /// <summary>Forgets the songs not at home of <paramref name="playlistId"/> (the playlist was deleted).</summary>
    public async Task DeletePlaylistAsync(Guid playlistId)
    {
        var gate = PlaylistLock(playlistId);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (File.Exists(PlaylistPath(playlistId)) || File.Exists(AtomicFile.BackupPath(PlaylistPath(playlistId))))
            {
                SaveEntries(playlistId, []);
            }
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>The playlists with songs not at home kept.</summary>
    public IReadOnlyList<Guid> Playlists()
    {
        var folder = Path.Combine(_root, PlaylistsFolder);
        try
        {
            return Directory.Exists(folder)
                ? Directory.EnumerateFiles(folder, "*.json")
                    .Select(f => Guid.TryParseExact(Path.GetFileNameWithoutExtension(f), "N", out var id) ? id : Guid.Empty)
                    .Where(id => id != Guid.Empty)
                    .ToList()
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: the playlists with songs not at home could not be read");
            return [];
        }
    }

    // ---------------------------------------------------------------- hearts

    private object UserLock(Guid userId) => _userLocks.GetOrAdd(userId, _ => new object());

    private List<KostvAwaySong> FavoritesLocked(Guid userId) =>
        Valid(AtomicFile.ReadWithRecovery(FavoritesPath(userId), Parse<FavoritesList>)?.Songs);

    private bool SaveFavoritesLocked(Guid userId, List<KostvAwaySong> songs)
    {
        try
        {
            var path = FavoritesPath(userId);
            if (songs.Count == 0)
            {
                AtomicFile.DeleteWithSidecars(path);
            }
            else
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                AtomicFile.WriteAllText(path, JsonSerializer.Serialize(new FavoritesList { Songs = songs }, KostvMusicStore.LineOptions));
            }

            Interlocked.Increment(ref _version);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: the hearts on songs not at home could not be stored");
            return false;
        }
    }

    /// <summary><paramref name="userId"/>'s hearts on songs not at home, the latest first.</summary>
    public List<KostvAwaySong> Favorites(Guid userId)
    {
        lock (UserLock(userId))
        {
            return FavoritesLocked(userId).OrderByDescending(s => s.Added).ToList();
        }
    }

    /// <summary>What came of putting a heart on a song not at home.</summary>
    public enum FavoriteResult
    {
        Stored,
        TooMany,
        NotStored
    }

    /// <summary>
    /// A heart of <paramref name="userId"/> on <paramref name="song"/>: one said again keeps when it
    /// was first put on, with what the app says of it now. Past <see cref="MaxFavorites"/>, not kept.
    /// </summary>
    public FavoriteResult AddFavorite(Guid userId, KostvAwaySong song)
    {
        lock (UserLock(userId))
        {
            var songs = FavoritesLocked(userId);
            var had = songs.FindIndex(s => s.DeezerId == song.DeezerId);
            var kept = song.Copy();
            kept.After = null;
            if (had >= 0)
            {
                kept.Added = songs[had].Added;
                songs[had] = kept;
            }
            else
            {
                if (songs.Count >= MaxFavorites)
                {
                    return FavoriteResult.TooMany;
                }

                kept.Added = _now();
                songs.Add(kept);
            }

            return SaveFavoritesLocked(userId, songs) ? FavoriteResult.Stored : FavoriteResult.NotStored;
        }
    }

    /// <summary>Takes the heart of <paramref name="userId"/> off <paramref name="deezerId"/>. False when it was on and could not be stored without it.</summary>
    public bool RemoveFavorite(Guid userId, string deezerId)
    {
        lock (UserLock(userId))
        {
            var songs = FavoritesLocked(userId);
            return songs.RemoveAll(s => s.DeezerId == deezerId) == 0 || SaveFavoritesLocked(userId, songs);
        }
    }

    /// <summary>The people with hearts on songs not at home.</summary>
    public IReadOnlyList<Guid> UsersWithFavorites()
    {
        try
        {
            return Directory.Exists(_root)
                ? Directory.EnumerateDirectories(_root)
                    .Where(d => File.Exists(Path.Combine(d, FavoritesFile)) || File.Exists(AtomicFile.BackupPath(Path.Combine(d, FavoritesFile))))
                    .Select(d => Guid.TryParseExact(Path.GetFileName(d), "N", out var id) ? id : Guid.Empty)
                    .Where(id => id != Guid.Empty)
                    .ToList()
                : [];
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            _logger?.LogWarning(ex, "kOS TV music: the hearts on songs not at home could not be read");
            return [];
        }
    }

    // ---------------------------------------------------------------- all of them

    /// <summary>A song not at home kept somewhere, and where: in which playlists and with whose hearts.</summary>
    public sealed record Pending(KostvAwaySong Song, IReadOnlyList<Guid> Playlists, IReadOnlyList<Guid> Users);

    /// <summary>Every song not at home kept, by its Deezer id, read now.</summary>
    public Dictionary<string, Pending> All()
    {
        var songs = new Dictionary<string, (KostvAwaySong Song, List<Guid> Playlists, List<Guid> Users)>(StringComparer.Ordinal);
        (KostvAwaySong Song, List<Guid> Playlists, List<Guid> Users) Of(KostvAwaySong song)
        {
            if (!songs.TryGetValue(song.DeezerId, out var known))
            {
                songs[song.DeezerId] = known = (song, [], []);
            }

            return known;
        }

        foreach (var playlistId in Playlists())
        {
            foreach (var entry in Entries(playlistId))
            {
                Of(entry).Playlists.Add(playlistId);
            }
        }

        foreach (var userId in UsersWithFavorites())
        {
            foreach (var song in Favorites(userId))
            {
                Of(song).Users.Add(userId);
            }
        }

        return songs.ToDictionary(s => s.Key, s => new Pending(s.Value.Song, s.Value.Playlists, s.Value.Users), StringComparer.Ordinal);
    }
}

/// <summary>Who may do what with a playlist of the server.</summary>
public enum KostvPlaylistAccess
{
    /// <summary>Not theirs to see.</summary>
    None,

    /// <summary>To see (open to all, or shared with them).</summary>
    Read,

    /// <summary>To change too (theirs, or shared with them to edit).</summary>
    Edit
}

/// <summary>
/// kOS TV: the server's playlist manager, to add a song and move it, bound by name: what each
/// takes changed between server versions (10.11 added where to add and who moves it).
/// </summary>
public sealed class KostvPlaylistEditor
{
    private readonly object? _manager;
    private readonly MethodInfo? _add;
    private readonly MethodInfo? _move;

    /// <param name="manager">The playlist manager.</param>
    /// <param name="managerType">Its type as bound (for tests, another server version's).</param>
    public KostvPlaylistEditor(object? manager, Type? managerType = null)
    {
        _manager = manager;
        var type = managerType ?? typeof(IPlaylistManager);
        _add = type.GetMethods().FirstOrDefault(m => m.Name == "AddItemToPlaylistAsync" && typeof(Task).IsAssignableFrom(m.ReturnType) && AddArgs(m, Guid.Empty, [], Guid.Empty) != null);
        _move = type.GetMethods().FirstOrDefault(m => m.Name == "MoveItemAsync" && typeof(Task).IsAssignableFrom(m.ReturnType) && MoveArgs(m, Guid.Empty, string.Empty, 0, Guid.Empty) != null);
    }

    /// <summary>Whether songs can be added and moved on this server.</summary>
    public bool CanEdit => _manager != null && _add != null && _move != null;

    private static object?[]? AddArgs(MethodInfo method, Guid playlistId, Guid[] ids, Guid userId)
    {
        var parameters = method.GetParameters();
        var args = new object?[parameters.Length];
        var guids = 0;
        var said = (Playlist: false, Ids: false);
        for (var i = 0; i < parameters.Length; i++)
        {
            var type = parameters[i].ParameterType;
            if (type == typeof(Guid))
            {
                // The playlist first, and then who adds.
                args[i] = guids++ == 0 ? playlistId : userId;
                said.Playlist = true;
            }
            else if (type == typeof(string) && !said.Playlist)
            {
                args[i] = playlistId.ToString("N");
                said.Playlist = true;
                guids++;
            }
            else if (type != typeof(string) && type.IsAssignableFrom(typeof(Guid[])))
            {
                args[i] = ids;
                said.Ids = true;
            }
            else if (type == typeof(int?))
            {
                // Where: at the end (then moved, as on servers that can't say where).
                args[i] = null;
            }
            else if (type == typeof(CancellationToken))
            {
                args[i] = CancellationToken.None;
            }
            else if (parameters[i].HasDefaultValue)
            {
                args[i] = parameters[i].DefaultValue;
            }
            else
            {
                return null;
            }
        }

        return said.Playlist && said.Ids && guids <= 2 ? args : null;
    }

    private static object?[]? MoveArgs(MethodInfo method, Guid playlistId, string entryId, int index, Guid userId)
    {
        var parameters = method.GetParameters();
        var args = new object?[parameters.Length];
        var strings = 0;
        var said = (Index: false, Strings: 0);
        for (var i = 0; i < parameters.Length; i++)
        {
            var type = parameters[i].ParameterType;
            if (type == typeof(string))
            {
                args[i] = strings++ == 0 ? playlistId.ToString("N") : entryId;
            }
            else if (type == typeof(int))
            {
                args[i] = index;
                said.Index = true;
            }
            else if (type == typeof(Guid))
            {
                args[i] = userId;
            }
            else if (type == typeof(CancellationToken))
            {
                args[i] = CancellationToken.None;
            }
            else if (parameters[i].HasDefaultValue)
            {
                args[i] = parameters[i].DefaultValue;
            }
            else
            {
                return null;
            }
        }

        return strings == 2 && said.Index ? args : null;
    }

    private static async Task Run(object? task)
    {
        if (task is Task running)
        {
            await running.ConfigureAwait(false);
        }
    }

    /// <summary>Adds <paramref name="itemId"/> at the end of <paramref name="playlistId"/>, as <paramref name="userId"/>.</summary>
    public Task AddAsync(Guid playlistId, Guid itemId, Guid userId)
    {
        if (!CanEdit)
        {
            throw new NotSupportedException("The server's playlists can't be changed from here.");
        }

        return Run(_add!.Invoke(_manager, AddArgs(_add, playlistId, [itemId], userId)));
    }

    /// <summary>Moves the element <paramref name="entryId"/> of <paramref name="playlistId"/> to <paramref name="index"/>, as <paramref name="userId"/>.</summary>
    public Task MoveAsync(Guid playlistId, string entryId, int index, Guid userId)
    {
        if (!CanEdit)
        {
            throw new NotSupportedException("The server's playlists can't be changed from here.");
        }

        return Run(_move!.Invoke(_manager, MoveArgs(_move, playlistId, entryId, index, userId)));
    }
}

/// <summary>
/// kOS TV: playlists and hearts with songs not at home (see <see cref="KostvAwayStore"/>): who
/// may see and change a playlist, as the server says, and what is done when one of those songs
/// comes home: put in the server's playlist where it was (after the element before it), its
/// «hueco» gone, and its heart made the server's for each person who had it. Only for what the
/// person may see: a song out of their libraries (of the playlist's owner, for a playlist) stays
/// as it was, not at home.
/// </summary>
public sealed class KostvMusicAway
{
    /// <summary>How close the length of a song at home must be to the one the app said, in seconds.</summary>
    public const double DurationMargin = 3;

    /// <summary>The most songs not at home looked for in the library on one daily round.</summary>
    public const int MaxLookedForPerRound = 3000;

    private readonly ILibraryManager _library;
    private readonly IUserDataManager _userData;
    private readonly KostvAwayStore _store;
    private readonly KostvPlaylistEditor _editor;
    private readonly ILogger<KostvMusicAway> _logger;

    // Only one arrival at a time: a library scan says many songs at once.
    private readonly SemaphoreSlim _arrivals = new(1, 1);

    // The songs not at home kept, by title and artist, as of the store's version.
    private readonly object _indexSync = new();
    private (int Version, Dictionary<string, List<KostvAwaySong>> ByName)? _index;

    // The arrivals on their way (see Detect).
    private readonly ConcurrentDictionary<string, Task> _pending = new(StringComparer.Ordinal);

    public KostvMusicAway(
        ILibraryManager library,
        IUserDataManager userData,
        IPlaylistManager playlists,
        KostvAwayStore store,
        IServiceProvider services,
        ILogger<KostvMusicAway> logger)
        : this(library, userData, new KostvPlaylistEditor(playlists), store, logger)
    {
        UserOf = id => UserReflection.ResolveUser(services, id);
        SetFavorite = (user, item) => SetServerFavorite(userData, user, item, logger);
    }

    internal KostvMusicAway(
        ILibraryManager library,
        IUserDataManager userData,
        KostvPlaylistEditor editor,
        KostvAwayStore store,
        ILogger<KostvMusicAway> logger)
    {
        _library = library;
        _userData = userData;
        _editor = editor;
        _store = store;
        _logger = logger;
    }

    public KostvAwayStore Store => _store;

    /// <summary>The server's user with this id, or null (for tests, to set).</summary>
    public Func<Guid, object?> UserOf { get; set; } = _ => null;

    /// <summary>Whether the person (the server's user) may see an item of the library on its own (for tests, to set).</summary>
    public Func<BaseItem, object, bool> Sees { get; set; } = UserReflection.IsVisibleStandaloneTo;

    /// <summary>Puts the heart of the server on a song for a person (for tests, to set). False when it could not.</summary>
    public Func<object, BaseItem, bool> SetFavorite { get; set; } = (_, _) => false;

    /// <summary>The library's item <paramref name="id"/>, or null.</summary>
    public BaseItem? ItemOf(Guid id)
    {
        try
        {
            return id == Guid.Empty ? null : _library.GetItemById(id);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: an item could not be read");
            return null;
        }
    }

    // ---------------------------------------------------------------- playlists

    /// <summary>The server's playlist <paramref name="playlistId"/>, or null.</summary>
    public Playlist? PlaylistOf(Guid playlistId)
    {
        try
        {
            return playlistId == Guid.Empty ? null : _library.GetItemById(playlistId) as Playlist;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: a playlist could not be read");
            return null;
        }
    }

    /// <summary>
    /// What <paramref name="userId"/> may do with <paramref name="playlist"/>, as the server's own
    /// playlist routes say: see it when it is open to all, theirs or shared with them; change it
    /// when it is theirs or shared with them to edit.
    /// </summary>
    public static KostvPlaylistAccess AccessOf(Playlist? playlist, Guid userId)
    {
        if (playlist == null || userId == Guid.Empty)
        {
            return KostvPlaylistAccess.None;
        }

        if (playlist.OwnerUserId == userId)
        {
            return KostvPlaylistAccess.Edit;
        }

        var access = playlist.OpenAccess ? KostvPlaylistAccess.Read : KostvPlaylistAccess.None;
        foreach (var (user, canEdit) in SharesOf(playlist))
        {
            if (user == userId)
            {
                if (canEdit)
                {
                    return KostvPlaylistAccess.Edit;
                }

                access = KostvPlaylistAccess.Read;
            }
        }

        return access;
    }

    // Read by name: the type of who it is shared with isn't the same on every server version.
    private static IEnumerable<(Guid User, bool CanEdit)> SharesOf(Playlist playlist)
    {
        IEnumerable? shares;
        try
        {
            shares = typeof(Playlist).GetProperty("Shares")?.GetValue(playlist) as IEnumerable;
        }
        catch
        {
            shares = null;
        }

        foreach (var share in shares ?? Array.Empty<object>())
        {
            var type = share?.GetType();
            var user = type?.GetProperty("UserId")?.GetValue(share);
            var id = user switch
            {
                Guid guid => guid,
                string text when Guid.TryParse(text, out var parsed) => parsed,
                _ => Guid.Empty
            };
            if (id != Guid.Empty)
            {
                yield return (id, type?.GetProperty("CanEdit")?.GetValue(share) is true);
            }
        }
    }

    /// <summary>The ids of the elements of <paramref name="playlist"/> (without dashes), in their order.</summary>
    public static List<string> JellyfinIdsOf(Playlist playlist) =>
        (playlist.LinkedChildren ?? []).Select(IdOf).OfType<Guid>().Select(id => id.ToString("N")).ToList();

    private static Guid? IdOf(LinkedChild child) =>
        child.ItemId is { } id && id != Guid.Empty ? id : Guid.TryParse(child.LibraryItemId, out var parsed) && parsed != Guid.Empty ? parsed : null;

    // Kos TV: LinkedChild.Id (the playlist entry's own id, which 10.10 moves by) is gone from
    // 10.11, where an entry is moved by its item's id; bound by name so it works on both.
    private static readonly PropertyInfo? LinkedChildIdProperty = typeof(LinkedChild).GetProperty("Id");

    /// <summary>The id the server's playlist moves <paramref name="child"/> (the item <paramref name="itemId"/>) by.</summary>
    internal static string EntryIdOf(LinkedChild child, Guid itemId) =>
        LinkedChildIdProperty?.GetValue(child) as string is { Length: > 0 } entryId ? entryId : itemId.ToString("N");

    // ---------------------------------------------------------------- a song comes home

    /// <summary>
    /// The song not at home <paramref name="deezerId"/> is <paramref name="item"/> now: in each
    /// playlist it was in, put in its place and its «hueco» gone; and each person's heart on it
    /// made the server's. What can't be done yet (the song out of the person's libraries, the
    /// server's playlist refused it) stays as it was. How many playlists and hearts changed.
    /// </summary>
    public async Task<int> ArriveAsync(string deezerId, BaseItem item)
    {
        if (!KostvMusicEvent.IsDeezerId(deezerId) || item is not Audio)
        {
            return 0;
        }

        var changed = 0;
        var where = _store.All().GetValueOrDefault(deezerId);
        foreach (var playlistId in where?.Playlists ?? [])
        {
            try
            {
                if (await ArriveInPlaylistAsync(playlistId, deezerId, item).ConfigureAwait(false))
                {
                    changed++;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "kOS TV music: a song come home could not be put in a playlist");
            }
        }

        foreach (var userId in where?.Users ?? [])
        {
            try
            {
                if (ArriveInFavorites(userId, deezerId, item))
                {
                    changed++;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "kOS TV music: the heart on a song come home could not be moved");
            }
        }

        return changed;
    }

    private async Task<bool> ArriveInPlaylistAsync(Guid playlistId, string deezerId, BaseItem item)
    {
        var gate = _store.PlaylistLock(playlistId);
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var entries = _store.Entries(playlistId);
            if (!entries.Any(e => e.DeezerId == deezerId))
            {
                return false;
            }

            var playlist = PlaylistOf(playlistId);
            if (playlist == null)
            {
                // Deleted: what was kept of it goes too.
                _store.SaveEntries(playlistId, []);
                return false;
            }

            // As its owner adds it: only a song its owner may see.
            var ownerId = playlist.OwnerUserId;
            if (UserOf(ownerId) is not { } owner || !Sees(item, owner))
            {
                return false;
            }

            var key = item.Id.ToString("N");
            var jellyfin = JellyfinIdsOf(playlist);
            if (!jellyfin.Contains(key))
            {
                var index = KostvAwayOrder.TargetIndex(jellyfin, entries, deezerId);
                await _editor.AddAsync(playlistId, item.Id, ownerId).ConfigureAwait(false);
                var after = PlaylistOf(playlistId) ?? playlist;
                var children = after.LinkedChildren ?? [];
                var at = Array.FindLastIndex(children, c => IdOf(c) == item.Id);
                if (at < 0)
                {
                    // The server didn't take it: it stays not at home.
                    return false;
                }

                if (at != index)
                {
                    try
                    {
                        await _editor.MoveAsync(playlistId, EntryIdOf(children[at], item.Id), index, ownerId).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        // In the list all the same, only at the end.
                        _logger.LogWarning(ex, "kOS TV music: a song come home could not be moved to its place in a playlist");
                    }
                }

                // What was after it now goes after the song at home.
                KostvAwayOrder.Remove(entries, deezerId, key, replace: true);
            }
            else
            {
                // Already in it (put there some other way): only the «hueco» goes, the rest in its place.
                KostvAwayOrder.Remove(entries, deezerId);
            }

            _store.SaveEntries(playlistId, entries);
            return true;
        }
        finally
        {
            gate.Release();
        }
    }

    private bool ArriveInFavorites(Guid userId, string deezerId, BaseItem item)
    {
        // Not a heart of the server on what the person may not see: it stays theirs, not at home.
        if (UserOf(userId) is not { } user || !Sees(item, user))
        {
            return false;
        }

        if (!SetFavorite(user, item))
        {
            return false;
        }

        // Should this fail, the heart is put on again next time, which changes nothing.
        return _store.RemoveFavorite(userId, deezerId);
    }

    // ---------------------------------------------------------------- telling the songs come home

    /// <summary>A name as compared: without accents, marks or case, words apart by one space.</summary>
    public static string Normalize(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return string.Empty;
        }

        var builder = new StringBuilder(text.Length);
        var space = false;
        foreach (var c in text.Normalize(NormalizationForm.FormKD))
        {
            var category = CharUnicodeInfo.GetUnicodeCategory(c);
            if (category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark)
            {
                continue;
            }

            if (char.IsLetterOrDigit(c))
            {
                if (space && builder.Length > 0)
                {
                    builder.Append(' ');
                }

                builder.Append(char.ToLowerInvariant(c));
                space = false;
            }
            else
            {
                space = true;
            }
        }

        return builder.ToString();
    }

    private static string NameKey(string? title, string? artist) => Normalize(title) + "|" + Normalize(artist);

    /// <summary>The artists of a song at home: its own, and the album's.</summary>
    private static IEnumerable<string> ArtistsOf(Audio audio) =>
        (audio.Artists ?? []).Concat(audio.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a));

    /// <summary>
    /// Whether <paramref name="item"/> is <paramref name="song"/> come home: the same title, one of
    /// its artists and the album (when the app said it), and its length within
    /// <see cref="DurationMargin"/> seconds when both are known.
    /// </summary>
    public static bool Matches(KostvAwaySong song, BaseItem item)
    {
        if (item is not Audio audio || item.IsVirtualItem)
        {
            return false;
        }

        var title = Normalize(song.Title);
        var artist = Normalize(song.Artist);
        if (title.Length == 0 || artist.Length == 0 || Normalize(item.Name) != title)
        {
            return false;
        }

        if (!ArtistsOf(audio).Any(a => Normalize(a) == artist))
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(song.Album) && Normalize(audio.Album) != Normalize(song.Album))
        {
            return false;
        }

        if (song.Duration is > 0 && item.RunTimeTicks is > 0)
        {
            var seconds = TimeSpan.FromTicks(item.RunTimeTicks.Value).TotalSeconds;
            if (Math.Abs(seconds - song.Duration.Value) > DurationMargin)
            {
                return false;
            }
        }

        return true;
    }

    private Dictionary<string, List<KostvAwaySong>> Index()
    {
        var version = _store.Version;
        lock (_indexSync)
        {
            if (_index is { } known && known.Version == version)
            {
                return known.ByName;
            }
        }

        var byName = new Dictionary<string, List<KostvAwaySong>>(StringComparer.Ordinal);
        foreach (var pending in _store.All().Values)
        {
            var key = NameKey(pending.Song.Title, pending.Song.Artist);
            if (!byName.TryGetValue(key, out var list))
            {
                byName[key] = list = [];
            }

            list.Add(pending.Song);
        }

        lock (_indexSync)
        {
            _index = (version, byName);
        }

        return byName;
    }

    /// <summary>The song not at home kept that <paramref name="item"/> is, if any.</summary>
    public KostvAwaySong? Kept(BaseItem item)
    {
        if (item is not Audio audio || item.IsVirtualItem)
        {
            return null;
        }

        var index = Index();
        if (index.Count == 0)
        {
            return null;
        }

        foreach (var artist in ArtistsOf(audio).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (index.TryGetValue(NameKey(item.Name, artist), out var songs) && songs.FirstOrDefault(s => Matches(s, item)) is { } song)
            {
                return song;
            }
        }

        return null;
    }

    /// <summary>
    /// A song entered (or changed in) the library: if it is one kept not at home, it is made to
    /// come home, apart (the library's events aren't held up). The task, or null.
    /// </summary>
    public Task? Detect(BaseItem item)
    {
        try
        {
            if (Kept(item) is not { } song)
            {
                return null;
            }

            var key = song.DeezerId + "|" + item.Id.ToString("N");
            if (_pending.TryGetValue(key, out var running))
            {
                return running;
            }

            // Started only once it is the one kept, so it is taken off the list when it ends.
            var start = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            var task = DetachedAsync(start.Task, key, song.DeezerId, item);
            if (_pending.TryAdd(key, task))
            {
                start.SetResult(true);
                return task;
            }

            start.SetResult(false);
            return _pending.GetValueOrDefault(key) ?? task;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: a song of the library could not be compared with those not at home");
            return null;
        }
    }

    private async Task DetachedAsync(Task<bool> start, string key, string deezerId, BaseItem item)
    {
        if (!await start.ConfigureAwait(false))
        {
            return;
        }

        try
        {
            await Task.Yield();
            await ArriveOnceAsync(deezerId, item).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: a song come home could not be moved from not at home");
        }
        finally
        {
            _pending.TryRemove(key, out _);
        }
    }

    /// <summary>The arrivals on their way, to wait for (tests, and the server stopping).</summary>
    public Task Settled() => Task.WhenAll(_pending.Values.ToArray());

    /// <summary><see cref="ArriveAsync"/>, one at a time.</summary>
    public async Task<int> ArriveOnceAsync(string deezerId, BaseItem item)
    {
        await _arrivals.WaitAsync().ConfigureAwait(false);
        try
        {
            return await ArriveAsync(deezerId, item).ConfigureAwait(false);
        }
        finally
        {
            _arrivals.Release();
        }
    }

    /// <summary>
    /// The daily round: forgets the songs not at home of playlists deleted, and looks in the library
    /// for those kept (up to <see cref="MaxLookedForPerRound"/>), making those found come home.
    /// How many came home.
    /// </summary>
    public async Task<int> RoundAsync(CancellationToken token = default)
    {
        foreach (var playlistId in _store.Playlists())
        {
            if (PlaylistOf(playlistId) == null)
            {
                await _store.DeletePlaylistAsync(playlistId).ConfigureAwait(false);
            }
        }

        var arrived = 0;
        foreach (var pending in _store.All().Values.Take(MaxLookedForPerRound))
        {
            token.ThrowIfCancellationRequested();
            if (Find(pending.Song) is { } item && await ArriveOnceAsync(pending.Song.DeezerId, item).ConfigureAwait(false) > 0)
            {
                arrived++;
            }
        }

        return arrived;
    }

    /// <summary>The song at home that <paramref name="song"/> is, looked for by its title, or null.</summary>
    public BaseItem? Find(KostvAwaySong song)
    {
        if (string.IsNullOrWhiteSpace(song.Title) || string.IsNullOrWhiteSpace(song.Artist))
        {
            return null;
        }

        // As the app said it, and then without its marks (a «(Remix)» the server's search may not take).
        foreach (var term in new[] { song.Title.Trim(), Normalize(song.Title) }.Where(t => t.Length > 0).Distinct(StringComparer.Ordinal))
        {
            try
            {
                // GetItemsResult, the same on every server version (GetItemList isn't).
                var found = _library.GetItemsResult(new InternalItemsQuery
                {
                    IncludeItemTypes = [BaseItemKind.Audio],
                    SearchTerm = term,
                    IsVirtualItem = false,
                    Recursive = true,
                    Limit = 100,
                    EnableTotalRecordCount = false
                });
                if (found?.Items?.FirstOrDefault(item => Matches(song, item)) is { } item)
                {
                    return item;
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "kOS TV music: a song not at home could not be looked for in the library");
                return null;
            }
        }

        return null;
    }

    // ---------------------------------------------------------------- the server's heart

    /// <summary>The server's heart put on <paramref name="item"/> for <paramref name="user"/>, bound by name (the User's type changed in 10.11).</summary>
    internal static bool SetServerFavorite(IUserDataManager userData, object user, BaseItem item, ILogger logger)
    {
        try
        {
            var get = typeof(IUserDataManager).GetMethods().FirstOrDefault(m =>
                m.Name == "GetUserData" && m.GetParameters() is { Length: 2 } p && p[1].ParameterType == typeof(BaseItem) && p[0].ParameterType.IsInstanceOfType(user));
            var save = typeof(IUserDataManager).GetMethods().FirstOrDefault(m =>
                m.Name == "SaveUserData" && m.GetParameters() is { Length: 5 } p &&
                p[0].ParameterType.IsInstanceOfType(user) && p[1].ParameterType == typeof(BaseItem) &&
                p[2].ParameterType == typeof(UserItemData) && p[3].ParameterType == typeof(UserDataSaveReason));
            if (get == null || save == null || get.Invoke(userData, [user, item]) is not UserItemData data)
            {
                return false;
            }

            if (!data.IsFavorite)
            {
                data.IsFavorite = true;
                save.Invoke(userData, [user, item, data, UserDataSaveReason.UpdateUserRating, CancellationToken.None]);
            }

            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "kOS TV music: the server's heart could not be put on a song come home");
            return false;
        }
    }
}

/// <summary>
/// kOS TV: watches the library for the songs not at home kept that come home (as they enter it or
/// their details are read), forgets those of the playlists deleted, and once a day looks for them
/// all (see <see cref="KostvMusicAway.RoundAsync"/>).
/// </summary>
public sealed class KostvMusicAwayWatcher : IHostedService
{
    private static readonly TimeSpan FirstRoundAfter = TimeSpan.FromMinutes(15);

    // After the music's own daily round, so it doesn't read the disk at the same time.
    private static readonly TimeSpan AfterMusicRound = TimeSpan.FromMinutes(10);

    private readonly ILibraryManager _library;
    private readonly KostvMusicAway _away;
    private readonly KostvMusicStore _music;
    private readonly ILogger<KostvMusicAwayWatcher> _logger;
    private readonly CancellationTokenSource _stopping = new();

    public KostvMusicAwayWatcher(ILibraryManager library, KostvMusicAway away, KostvMusicStore music, ILogger<KostvMusicAwayWatcher> logger)
    {
        _library = library;
        _away = away;
        _music = music;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        _library.ItemAdded += OnItemChanged;
        _library.ItemUpdated += OnItemChanged;
        _library.ItemRemoved += OnItemRemoved;
        _ = RoundDailyAsync(_stopping.Token);
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        _stopping.Cancel();
        _library.ItemAdded -= OnItemChanged;
        _library.ItemUpdated -= OnItemChanged;
        _library.ItemRemoved -= OnItemRemoved;
        try
        {
            _away.Settled().Wait(TimeSpan.FromSeconds(5));
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: a song come home on its way failed as the server stopped");
        }

        return Task.CompletedTask;
    }

    internal void OnItemChanged(object? sender, ItemChangeEventArgs e)
    {
        if (e.Item is Audio item)
        {
            _away.Detect(item);
        }
    }

    internal void OnItemRemoved(object? sender, ItemChangeEventArgs e)
    {
        if (e.Item is Playlist playlist)
        {
            var id = playlist.Id;
            _ = Task.Run(async () =>
            {
                try
                {
                    await _away.Store.DeletePlaylistAsync(id).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "kOS TV music: the songs not at home of a deleted playlist could not be forgotten");
                }
            });
        }
    }

    private async Task RoundDailyAsync(CancellationToken token)
    {
        try
        {
            await Task.Delay(FirstRoundAfter, token).ConfigureAwait(false);
            while (!token.IsCancellationRequested)
            {
                try
                {
                    var arrived = await _away.RoundAsync(token).ConfigureAwait(false);
                    if (arrived > 0)
                    {
                        _logger.LogInformation("kOS TV music: {Count} songs not at home came home", arrived);
                    }
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "kOS TV music: the daily round of the songs not at home failed");
                }

                await Task.Delay(KostvMusicRecorder.NextRoundIn(_music.Now, _music.Zone) + AfterMusicRound, token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }
}
