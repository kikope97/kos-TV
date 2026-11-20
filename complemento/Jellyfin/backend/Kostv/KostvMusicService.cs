using System.Collections.Concurrent;
using System.Reflection;
using System.Text.Json;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: each person's music: their daily mixes, the artists for «Descubrimiento semanal» and
/// the songs for the time of day, read from the library and from what they listened to, and
/// handed to <see cref="KostvMusicEngine"/>. Kept per person for the day (and time of day), so
/// every device shows the same.
/// </summary>
public sealed class KostvMusicService
{
    // What is read of the library for a person. Generous for a home, and bounded.
    private const int HeardLimit = 5000;
    private const int FavoritesLimit = 2000;
    private const int GenreLimit = 1500;
    private const int ArtistsLimit = 3000;
    private const int PoolGenres = 6;
    private const int PoolArtists = 30;
    private const int SimilarOf = 12;
    private const int SimilarEach = 6;
    private const int IdsChunk = 500;

    // An empty answer is worked out again after this, so a person who just started listening
    // doesn't wait for the next day.
    private static readonly TimeSpan EmptyKeptFor = TimeSpan.FromHours(1);
    private static readonly TimeSpan NotReadyKeptFor = TimeSpan.FromMinutes(30);

    private static readonly PropertyInfo? OrderByProperty = typeof(InternalItemsQuery).GetProperty(nameof(InternalItemsQuery.OrderBy));

    private static readonly MethodInfo? GetUserData = typeof(IUserDataManager)
        .GetMethods()
        .FirstOrDefault(m =>
        {
            if (m.Name != "GetUserData")
            {
                return false;
            }

            var parameters = m.GetParameters();
            return parameters.Length == 2 &&
                parameters[1].ParameterType == typeof(BaseItem) &&
                typeof(UserItemData).IsAssignableFrom(m.ReturnType);
        });

    private readonly ILibraryManager _library;
    private readonly IUserDataManager _userData;
    private readonly KostvMusicStore _store;
    private readonly ILogger<KostvMusicService> _logger;

    private readonly ConcurrentDictionary<Guid, SemaphoreSlim> _gates = new();
    private readonly ConcurrentDictionary<Guid, Kept<IReadOnlyList<KostvMix>>> _mixes = new();
    private readonly ConcurrentDictionary<Guid, Kept<IReadOnlyList<string>>> _seeds = new();
    private readonly ConcurrentDictionary<Guid, Kept<KostvMoment>> _moments = new();

    /// <summary>Something worked out for a person, the day (and time of day) it is for.</summary>
    private sealed record Kept<T>(string Key, T Value, DateTimeOffset At, bool Empty);

    /// <summary>The mix of the time of day: which, whether there is enough for it, and its songs.</summary>
    public sealed record KostvMoment(string Slot, bool Ready, IReadOnlyList<Guid> Items);

    /// <summary>What was read of a person to work out their music.</summary>
    private sealed record Taste(
        IReadOnlyList<KostvMusicEvent> Events,
        List<KostvMusicTrack> Tracks,
        KostvMusicProfile Profile);

    public KostvMusicService(
        ILibraryManager library,
        IUserDataManager userData,
        KostvMusicStore store,
        ILogger<KostvMusicService> logger)
    {
        _library = library;
        _userData = userData;
        _store = store;
        _logger = logger;
    }

    public KostvMusicStore Store => _store;

    /// <summary>The music day it is at home (see <see cref="KostvMusicEngine.MusicDay"/>).</summary>
    public string Day => KostvMusicEngine.DayKey(KostvMusicEngine.MusicDay(_store.Now, _store.Zone));

    /// <summary>The ISO week it is at home.</summary>
    public string Week => KostvMusicEngine.WeekOf(_store.Now, _store.Zone);

    /// <summary>The time of day it is at home.</summary>
    public string Slot => KostvMusicEngine.SlotOf(TimeZoneInfo.ConvertTime(_store.Now, _store.Zone).Hour);

    /// <summary>Forgets what was worked out for <paramref name="userId"/>, so it is worked out again.</summary>
    public void Forget(Guid userId)
    {
        _mixes.TryRemove(userId, out _);
        _seeds.TryRemove(userId, out _);
        _moments.TryRemove(userId, out _);
    }

    private bool Stands<T>(Kept<T>? kept, string key, TimeSpan emptyFor) =>
        kept != null && kept.Key == key && (!kept.Empty || _store.Now - kept.At < emptyFor);

    /// <summary>The daily mixes of <paramref name="userId"/>, the same all day.</summary>
    public async Task<IReadOnlyList<KostvMix>> MixesAsync(Guid userId, object user)
    {
        var day = Day;
        if (_mixes.TryGetValue(userId, out var kept) && Stands(kept, day, EmptyKeptFor))
        {
            return kept.Value;
        }

        var gate = _gates.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_mixes.TryGetValue(userId, out kept) && Stands(kept, day, EmptyKeptFor))
            {
                return kept.Value;
            }

            var taste = TasteOf(userId, user);
            var genres = taste.Profile.Genres.Take(PoolGenres).Select(g => g.Name).ToList();
            var (pool, similar) = Pool(user, taste, genres, taste.Profile.Artists.Select(a => a.Name));
            var mixes = KostvMusicEngine.Mixes(userId, day, taste.Tracks.Concat(pool), taste.Profile, similar);
            _mixes[userId] = new Kept<IReadOnlyList<KostvMix>>(day, mixes, _store.Now, mixes.Count == 0);
            _seeds[userId] = Seeds(day, taste);
            return mixes;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>The artists <paramref name="userId"/> likes most, to ask for songs like theirs.</summary>
    public async Task<IReadOnlyList<string>> SeedsAsync(Guid userId, object user)
    {
        var day = Day;
        if (_seeds.TryGetValue(userId, out var kept) && Stands(kept, day, EmptyKeptFor))
        {
            return kept.Value;
        }

        var gate = _gates.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_seeds.TryGetValue(userId, out kept) && Stands(kept, day, EmptyKeptFor))
            {
                return kept.Value;
            }

            var seeds = Seeds(day, TasteOf(userId, user));
            _seeds[userId] = seeds;
            return seeds.Value;
        }
        finally
        {
            gate.Release();
        }
    }

    private Kept<IReadOnlyList<string>> Seeds(string day, Taste taste)
    {
        var seeds = KostvMusicEngine.Seeds(taste.Profile);
        return new Kept<IReadOnlyList<string>>(day, seeds, _store.Now, seeds.Count == 0);
    }

    /// <summary>
    /// The mix for the time of day it is, for <paramref name="userId"/>: not ready until they
    /// have listened enough at this time of day, and never while Learn is off.
    /// </summary>
    public async Task<KostvMoment> MomentAsync(Guid userId, object user)
    {
        var day = Day;
        var slot = Slot;
        var key = day + "|" + slot;
        if (_moments.TryGetValue(userId, out var kept) && Stands(kept, key, NotReadyKeptFor))
        {
            return kept.Value;
        }

        var gate = _gates.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_moments.TryGetValue(userId, out kept) && Stands(kept, key, NotReadyKeptFor))
            {
                return kept.Value;
            }

            var moment = new KostvMoment(slot, false, []);
            var now = _store.Now;
            var events = _store.Learns(userId) ? _store.Read(userId, now - KostvMusicEngine.MomentWindow) : [];
            if (KostvMusicEngine.MomentReady(events, slot, now))
            {
                var taste = TasteOf(userId, user);
                var slotItems = events
                    .Where(e => e.IsListen && KostvMusicEngine.SlotOf(e.Hour) == slot && e.Outcome != KostvListenOutcome.Skipped)
                    .ToList();
                var genres = slotItems.SelectMany(e => e.Genres ?? []).GroupBy(KostvMusicEngine.Key).OrderByDescending(g => g.Count()).Take(3).Select(g => g.First()).ToList();
                var artists = slotItems.SelectMany(e => e.Artists ?? []).GroupBy(KostvMusicEngine.Key).OrderByDescending(g => g.Count()).Take(PoolArtists).Select(g => g.First()).ToList();
                var (pool, similar) = Pool(user, taste, genres, artists);
                var items = KostvMusicEngine.Moment(userId, day, slot, events, taste.Tracks.Concat(pool), taste.Profile, now, similar);
                moment = new KostvMoment(slot, items.Count > 0, items);
            }

            _moments[userId] = new Kept<KostvMoment>(key, moment, _store.Now, !moment.Ready);
            return moment;
        }
        finally
        {
            gate.Release();
        }
    }

    // ---------------------------------------------------------------- reading the library

    /// <summary>
    /// What <paramref name="userId"/> has played (the server's count and last time, their hearts
    /// and, with Learn on, their listens), and what they like of it.
    /// </summary>
    private Taste TasteOf(Guid userId, object user)
    {
        var now = _store.Now;
        var events = _store.Learns(userId) ? _store.Read(userId) : [];
        var listens = KostvMusicEngine.Listens(events, now);

        var items = new Dictionary<Guid, BaseItem>();
        foreach (var item in Query(user, q => q.IsPlayed = true, HeardLimit, newestBy: ItemSortBy.DatePlayed)
            .Concat(Query(user, q => q.IsFavorite = true, FavoritesLimit))
            .Concat(listens.Keys.Chunk(IdsChunk).SelectMany(ids => Query(user, q => q.ItemIds = ids, IdsChunk))))
        {
            items.TryAdd(item.Id, item);
        }

        var tracks = items.Values.Select(item => TrackOf(item, UserDataOf(user, item))).ToList();
        return new Taste(events, tracks, KostvMusicEngine.Profile(tracks, listens, now));
    }

    /// <summary>
    /// Songs to pick the new ones from: of <paramref name="genres"/>, not yet played; all of
    /// the person's main <paramref name="artists"/>; and those of the artists the server finds
    /// like them, with which those are (by artist).
    /// </summary>
    private (List<KostvMusicTrack> Pool, Dictionary<string, IReadOnlyList<string>> Similar) Pool(
        object user,
        Taste taste,
        IEnumerable<string> genres,
        IEnumerable<string> artists)
    {
        var known = taste.Tracks.Select(t => t.Id).ToHashSet();
        var pool = new Dictionary<Guid, KostvMusicTrack>();
        void Add(IEnumerable<BaseItem> items)
        {
            foreach (var item in items)
            {
                if (!known.Contains(item.Id) && !pool.ContainsKey(item.Id))
                {
                    pool[item.Id] = TrackOf(item, null);
                }
            }
        }

        foreach (var genre in genres.Where(g => !string.IsNullOrWhiteSpace(g)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            Add(Query(user, q =>
            {
                q.Genres = [genre];
                q.IsPlayed = false;
            }, GenreLimit));
        }

        var main = ArtistsByName(artists.Take(PoolArtists));
        if (main.Count > 0)
        {
            var ids = main.Values.Select(a => a.Id).ToArray();
            Add(Query(user, q => q.ArtistIds = ids, ArtistsLimit));
        }

        var similar = new Dictionary<string, IReadOnlyList<string>>(StringComparer.OrdinalIgnoreCase);
        var alikeIds = new HashSet<Guid>();
        foreach (var (name, artist) in main.Take(SimilarOf))
        {
            var alike = SimilarArtists(artist);
            if (alike.Count > 0)
            {
                similar[name] = alike.Select(a => a.Name).ToList();
                alikeIds.UnionWith(alike.Select(a => a.Id));
            }
        }

        alikeIds.ExceptWith(main.Values.Select(a => a.Id));
        if (alikeIds.Count > 0)
        {
            var ids = alikeIds.ToArray();
            Add(Query(user, q => q.ArtistIds = ids, ArtistsLimit));
        }

        return (pool.Values.ToList(), similar);
    }

    /// <summary>The artists of the server with these names, by name. Asked by name, as artists aren't in a library.</summary>
    public Dictionary<string, BaseItem> ArtistsByName(IEnumerable<string> names)
    {
        var found = new Dictionary<string, BaseItem>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in names.Where(n => !string.IsNullOrWhiteSpace(n)).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                // Not GetArtist, which makes the artist when it isn't there.
                var artist = _library.GetItemList(new InternalItemsQuery
                {
                    IncludeItemTypes = [BaseItemKind.MusicArtist],
                    Name = name,
                    Recursive = true,
                    Limit = 1,
                    EnableTotalRecordCount = false
                }).FirstOrDefault();
                if (artist != null)
                {
                    found[name] = artist;
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "kOS TV music: an artist could not be read");
            }
        }

        return found;
    }

    /// <summary>The artists the server finds most like <paramref name="artist"/> (its own similar items).</summary>
    private List<BaseItem> SimilarArtists(BaseItem artist)
    {
        try
        {
            return _library.GetItemList(new InternalItemsQuery
            {
                IncludeItemTypes = [BaseItemKind.MusicArtist],
                SimilarTo = artist,
                ExcludeItemIds = [artist.Id],
                Recursive = true,
                Limit = SimilarEach,
                EnableTotalRecordCount = false
            }).Where(a => !string.IsNullOrWhiteSpace(a.Name)).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV music: the artists like one could not be read");
            return [];
        }
    }

    private static KostvMusicTrack TrackOf(BaseItem item, UserItemData? data)
    {
        var audio = item as Audio;
        var artists = (audio?.Artists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        if (artists.Count == 0)
        {
            artists = (audio?.AlbumArtists ?? []).Where(a => !string.IsNullOrWhiteSpace(a)).ToList();
        }

        return new KostvMusicTrack(
            item.Id,
            artists,
            (item.Genres ?? []).Where(g => !string.IsNullOrWhiteSpace(g)).ToList(),
            data?.PlayCount ?? 0,
            data?.LastPlayedDate,
            data?.IsFavorite ?? false);
    }

    /// <summary>Songs within the person's limits (libraries and parental rating).</summary>
    private IReadOnlyList<BaseItem> Query(object user, Action<InternalItemsQuery> filter, int limit, ItemSortBy? newestBy = null)
    {
        var query = new InternalItemsQuery
        {
            IncludeItemTypes = [BaseItemKind.Audio],
            IsVirtualItem = false,
            Recursive = true,
            Limit = limit,
            EnableTotalRecordCount = false
        };
        filter(query);
        if (newestBy.HasValue)
        {
            Order(query, newestBy.Value);
        }

        // Without the person's limits applied nothing is read, rather than everything.
        if (!UserReflection.ApplyUser(query, user))
        {
            return [];
        }

        try
        {
            return _library.GetItemList(query);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV music: a library query failed");
            return [];
        }
    }

    // The tuple type of OrderBy changed between server versions, so it is built by reflection.
    private static void Order(InternalItemsQuery query, ItemSortBy sortBy)
    {
        if (OrderByProperty == null)
        {
            return;
        }

        try
        {
            var elementType = OrderByProperty.PropertyType.GetGenericArguments()[0];
            var sortOrderType = elementType.GetGenericArguments()[1];
            var array = Array.CreateInstance(elementType, 1);
            array.SetValue(Activator.CreateInstance(elementType, sortBy, Enum.Parse(sortOrderType, "Descending")), 0);
            OrderByProperty.SetValue(query, array);
        }
        catch
        {
            // Unordered is still right, only not the latest first.
        }
    }

    private UserItemData? UserDataOf(object user, BaseItem item)
    {
        try
        {
            return GetUserData?.Invoke(_userData, [user, item]) as UserItemData;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>The week's list the app stored for <paramref name="userId"/>, or null.</summary>
    public JsonElement? DiscoverySongs(Guid userId) => _store.DiscoveryOf(userId, Week);
}
