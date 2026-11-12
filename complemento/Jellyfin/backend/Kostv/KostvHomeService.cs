using System.Collections.Concurrent;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Entities;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>What TMDB said of a title or a person, kept so it's asked once a month.</summary>
public sealed class KostvTasteEntry
{
    [JsonPropertyName("recs")]
    public List<string> Recs { get; set; } = [];

    [JsonPropertyName("people")]
    public List<KostvTastePerson> People { get; set; } = [];

    /// <summary>For a person: what they made or acted in.</summary>
    [JsonPropertyName("credits")]
    public List<string> Credits { get; set; } = [];

    [JsonPropertyName("cachedAt")]
    public DateTimeOffset CachedAt { get; set; }
}

public sealed class KostvTastePerson
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("director")]
    public bool Director { get; set; }
}

/// <summary>kOS TV: TMDB's recommendations and credits, on disk.</summary>
public sealed class KostvTasteCache : FileBackedCacheService<KostvTasteEntry>
{
    private static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);

    public KostvTasteCache(ILogger<KostvTasteCache> logger)
        : base(logger, "kostv-home-tmdb.json", "kOS TV home")
    {
    }

    public KostvTasteEntry? Get(string key) =>
        EnsureLoaded().TryGetValue(key, out var entry) && DateTimeOffset.UtcNow - entry.CachedAt < MaxAge ? entry : null;

    public void Set(string key, KostvTasteEntry entry)
    {
        entry.CachedAt = DateTimeOffset.UtcNow;
        EnsureLoaded()[key] = entry;
    }
}

/// <summary>How far someone is with a title of their list.</summary>
public enum KostvListState
{
    ToStart,
    Watching,
    Watched
}

/// <summary>A person's list in its three parts.</summary>
public sealed record KostvMyListSections(
    IReadOnlyList<BaseItem> Watching,
    IReadOnlyList<BaseItem> ToStart,
    IReadOnlyList<BaseItem> Watched);

/// <summary>A person's home page as worked out, with what it was worked out from.</summary>
public sealed record KostvHomePage(
    IReadOnlyList<KostvHomeRow> Rows,
    int Seeds,
    int Library,
    bool Tmdb,
    DateTimeOffset BuiltAt,
    IReadOnlyDictionary<string, Guid> Index,
    string Stamp,
    IReadOnlySet<Guid>? Followed = null);

/// <summary>
/// kOS TV: works out each person's home page. Reads what they watched from the server's own
/// play history, asks TMDB what people who liked those also liked (kept a month), keeps what is
/// on the home server, not seen and within their limits, and hands it to the engine. A page is
/// kept a while per person, so the apps only fetch.
/// </summary>
public sealed class KostvHomeService
{
    private const int MaxSeeds = 14;
    private const int RecommendationPages = 3;

    // TMDB, or a stand-in for it when the plugin is tried out against a made-up library.
    private static readonly string TmdbUrl =
        (Environment.GetEnvironmentVariable("KOSTV_TMDB_URL") ?? "https://api.themoviedb.org").TrimEnd('/');
    private static readonly TimeSpan PageLife = TimeSpan.FromMinutes(20);

    // With nothing new watched, a page stands this long even when asked to refresh.
    private static readonly TimeSpan StaleLife = TimeSpan.FromHours(6);

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

    private readonly ILibraryManager _libraryManager;
    private readonly IUserDataManager _userDataManager;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly MoonfinSettingsService _settings;
    private readonly KostvTasteCache _cache;
    private readonly KostvDismissals _dismissals;
    private readonly KostvMyList _myList;
    private readonly ILogger<KostvHomeService> _logger;

    /// <summary>How many of the titles turned down lately TMDB is asked about, to rank what is like them lower.</summary>
    private const int MaxAvoided = 30;

    /// <summary>An episode added this long ago still counts as new.</summary>
    public static readonly TimeSpan NewEpisodeWindow = TimeSpan.FromDays(14);

    private readonly ConcurrentDictionary<Guid, KostvHomePage> _pages = new();
    private readonly ConcurrentDictionary<Guid, Lazy<Task<KostvHomePage>>> _building = new();
    private readonly SemaphoreSlim _tmdbGate = new(4, 4);

    public KostvHomeService(
        ILibraryManager libraryManager,
        IUserDataManager userDataManager,
        IHttpClientFactory httpClientFactory,
        MoonfinSettingsService settings,
        KostvTasteCache cache,
        KostvDismissals dismissals,
        KostvMyList myList,
        ILogger<KostvHomeService> logger)
    {
        _dismissals = dismissals;
        _myList = myList;
        _libraryManager = libraryManager;
        _userDataManager = userDataManager;
        _httpClientFactory = httpClientFactory;
        _settings = settings;
        _cache = cache;
        _logger = logger;
    }

    /// <summary>The page of <paramref name="userId"/>, worked out again when it's old or asked to.</summary>
    public Task<KostvHomePage> GetAsync(Guid userId, object user, bool refresh)
    {
        if (_pages.TryGetValue(userId, out var page))
        {
            var age = DateTimeOffset.UtcNow - page.BuiltAt;
            // Asked to work it out again: only when the person has watched something since,
            // which one small query tells. The apps ask every time Home comes back up.
            if (refresh ? age < StaleLife && HistoryStamp(user) == page.Stamp : age < PageLife)
            {
                return Task.FromResult(page);
            }
        }

        // Two apps asking at once share the one build. Lazy, and run off this thread, so the
        // entry is in the map before the build can finish and take it out.
        return _building.GetOrAdd(
            userId,
            _ => new Lazy<Task<KostvHomePage>>(() => Task.Run(() => BuildAndKeepAsync(userId, user)))).Value;
    }

    /// <summary>The last thing the person played and when: changes when they watch something.</summary>
    private string HistoryStamp(object user)
    {
        var last = Query(user, [BaseItemKind.Movie, BaseItemKind.Episode], q => q.IsPlayed = true, 1, ItemSortBy.DatePlayed).FirstOrDefault();
        return last == null ? "none" : $"{last.Id:N}:{LastPlayed(user, last)?.Ticks}";
    }

    private async Task<KostvHomePage> BuildAndKeepAsync(Guid userId, object user)
    {
        try
        {
            var page = await BuildAsync(userId, user).ConfigureAwait(false);
            _pages[userId] = page;
            return page;
        }
        finally
        {
            _building.TryRemove(userId, out _);
        }
    }

    private async Task<KostvHomePage> BuildAsync(Guid userId, object user)
    {
        var now = DateTimeOffset.UtcNow;
        var stamp = HistoryStamp(user);
        var (library, items) = ReadLibrary(user);
        var listed = _myList.For(userId);
        var (seeds, followed) = ReadSeeds(user, items, now, listed);
        var dismissed = _dismissals.For(userId);
        var avoid = new List<KostvSeedFacts>();

        var apiKey = await TmdbApiKeys.ResolveAsync(_settings, userId).ConfigureAwait(false);
        var facts = new Dictionary<string, KostvSeedFacts>(StringComparer.Ordinal);
        var credits = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        var hasKey = !string.IsNullOrWhiteSpace(apiKey);
        if (hasKey)
        {
            var asked = await Task.WhenAll(seeds.Select(async seed => (seed.Key, Entry: await SeedFactsAsync(seed.Key, apiKey!).ConfigureAwait(false)))).ConfigureAwait(false);
            foreach (var (key, entry) in asked)
            {
                if (entry != null)
                {
                    facts[key] = new KostvSeedFacts(
                        entry.Recs,
                        entry.People.Select(p => new KostvPerson(p.Id, p.Name, p.Director)).ToList());
                }
            }

            var people = KostvHomeEngine.PeopleToAsk(seeds, facts);
            var works = await Task.WhenAll(people.Select(async person => (person.Id, Entry: await PersonCreditsAsync(person.Id, apiKey!).ConfigureAwait(false)))).ConfigureAwait(false);
            foreach (var (id, entry) in works)
            {
                if (entry != null)
                {
                    credits[id] = entry.Credits;
                }
            }

            var avoided = await Task.WhenAll(dismissed.TakeLast(MaxAvoided).Select(key => SeedFactsAsync(key, apiKey!))).ConfigureAwait(false);
            foreach (var entry in avoided)
            {
                if (entry != null)
                {
                    avoid.Add(new KostvSeedFacts(entry.Recs, []));
                }
            }

            await _cache.FlushAsync().ConfigureAwait(false);
        }

        // The day, and the person, so two people at home don't get the same shuffle.
        var day = (int)(now.ToUnixTimeSeconds() / 86400) + (userId.GetHashCode() & 0xFFFF);
        // What is on their list they know about already: not offered again.
        var onList = listed.Select(e => e.Key).OfType<string>().ToList();
        var rows = KostvHomeEngine.Build(seeds, facts, credits, library, day, dismissed, avoid, onList);
        var index = new Dictionary<string, Guid>(StringComparer.Ordinal);
        foreach (var (id, item) in items)
        {
            if (KeyOf(item) is { } key)
            {
                index.TryAdd(key, id);
            }
        }

        return new KostvHomePage(rows, seeds.Count, library.Count, hasKey, now, index, stamp, followed);
    }

    /// <summary>
    /// Notes that the person isn't interested in <paramref name="itemId"/>, a film or series of
    /// the home server, and has their page worked out again without it. Null when it isn't one
    /// of those, or has no TMDB id to keep it by.
    /// </summary>
    public async Task<string?> DismissAsync(Guid userId, Guid itemId, bool undo)
    {
        if (_libraryManager.GetItemById(itemId) is not { } item || KeyOf(item) is not { } key)
        {
            return null;
        }

        if (undo ? _dismissals.Remove(userId, key) : _dismissals.Add(userId, key))
        {
            await _dismissals.FlushAsync().ConfigureAwait(false);
            _pages.TryRemove(userId, out _);
        }

        return key;
    }

    /// <summary>
    /// The home server's items of the titles the person turned down, for the rows the app makes
    /// itself (what is most watched now) to leave out too.
    /// </summary>
    public IReadOnlyList<Guid> Hidden(Guid userId, KostvHomePage page) =>
        _dismissals.For(userId)
            .Select(key => page.Index.TryGetValue(key, out var id) ? id : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .ToList();

    /// <summary>
    /// New episodes of the series the person follows: added in the last two weeks, not seen,
    /// of a series they have watched some of. One per series, the first of its new ones, the
    /// series with the latest arrival first. Read each time, so an episode shows as it lands.
    /// </summary>
    public IReadOnlyList<BaseItem> NewEpisodes(object user, KostvHomePage page, int max = 20)
    {
        var followed = page.Followed;
        if (followed == null || followed.Count == 0)
        {
            return [];
        }

        var since = DateTime.UtcNow - NewEpisodeWindow;
        var bySeries = new Dictionary<Guid, (Episode First, DateTime Latest)>();
        foreach (var item in Query(user, [BaseItemKind.Episode], q =>
        {
            q.IsPlayed = false;
            q.MinDateCreated = since;
        }, 300, ItemSortBy.DateCreated))
        {
            if (item is not Episode { SeriesId: var seriesId } episode || !followed.Contains(seriesId))
            {
                continue;
            }

            if (!bySeries.TryGetValue(seriesId, out var had))
            {
                bySeries[seriesId] = (episode, episode.DateCreated);
                continue;
            }

            var earlier = (episode.ParentIndexNumber ?? 0, episode.IndexNumber ?? 0).CompareTo(
                (had.First.ParentIndexNumber ?? 0, had.First.IndexNumber ?? 0)) < 0;
            bySeries[seriesId] = (earlier ? episode : had.First, had.Latest > episode.DateCreated ? had.Latest : episode.DateCreated);
        }

        return bySeries.Values
            .OrderByDescending(v => v.Latest)
            .Take(max)
            .Select(v => (BaseItem)v.First)
            .ToList();
    }

    /// <summary>
    /// The films and series on the home server, of those the person may see, that are the TMDB
    /// titles in <paramref name="keys"/> ("movie:123", "tv:45"), in that order. Found through the
    /// index kept with the person's page, so the library isn't read again for each list.
    /// </summary>
    public async Task<IReadOnlyList<(string Key, BaseItem Item)>> FindAsync(Guid userId, object user, IReadOnlyList<string> keys)
    {
        var page = await GetAsync(userId, user, refresh: false).ConfigureAwait(false);
        var found = new List<(string, BaseItem)>();
        foreach (var key in keys.Distinct())
        {
            if (page.Index.TryGetValue(key, out var id) &&
                _libraryManager.GetItemById(id) is { } item &&
                UserReflection.IsVisibleTo(item, user))
            {
                found.Add((key, item));
            }
        }

        return found;
    }

    // ---------------------------------------------------------------- the server

    /// <summary>Every film and series the person may see, and which of them they have seen.</summary>
    private (List<KostvCandidate> Library, Dictionary<Guid, BaseItem> Items) ReadLibrary(object user)
    {
        var items = new Dictionary<Guid, BaseItem>();
        var library = new List<KostvCandidate>();

        var seen = new HashSet<Guid>(Query(user, [BaseItemKind.Movie], q => q.IsPlayed = true).Select(i => i.Id));
        // A series counts as seen once any of it has been: it's offered under "carry on", not
        // as something new.
        foreach (var episode in Query(user, [BaseItemKind.Episode], q => q.IsPlayed = true, 20000, ItemSortBy.DatePlayed))
        {
            if (episode is Episode { SeriesId: var seriesId } && seriesId != Guid.Empty)
            {
                seen.Add(seriesId);
            }
        }

        foreach (var item in Query(user, [BaseItemKind.Movie, BaseItemKind.Series], null))
        {
            if (!UserReflection.IsVisibleTo(item, user))
            {
                continue;
            }

            items[item.Id] = item;
            var key = KeyOf(item);
            if (key == null)
            {
                continue;
            }

            library.Add(new KostvCandidate(
                item.Id.ToString("N"),
                key,
                item is Series,
                seen.Contains(item.Id),
                item.CommunityRating ?? 0,
                item.Genres ?? []));
        }

        return (library, items);
    }

    /// <summary>What the person watched lately and what they marked as favourite, weighed.</summary>
    private (List<KostvSeed> Seeds, HashSet<Guid> Followed) ReadSeeds(object user, Dictionary<Guid, BaseItem> items, DateTimeOffset now, IReadOnlyList<KostvMyListEntry> listed)
    {
        var seeds = new Dictionary<string, KostvSeed>(StringComparer.Ordinal);

        void Add(BaseItem item, KostvSeedKind kind, double weight)
        {
            var key = KeyOf(item);
            if (key == null || (seeds.TryGetValue(key, out var had) && had.Weight >= weight))
            {
                return;
            }

            seeds[key] = new KostvSeed(key, item.Id.ToString("N"), item.Name, item is Series, kind, weight);
        }

        foreach (var movie in Query(user, [BaseItemKind.Movie], q => q.IsPlayed = true, 40, ItemSortBy.DatePlayed))
        {
            Add(movie, KostvSeedKind.Finished, KostvHomeEngine.Recency(DaysSince(LastPlayed(user, movie), now)));
        }

        // Episodes come newest first, so the first of each series is its latest.
        var series = new Dictionary<Guid, (DateTime? Last, int Count)>();
        foreach (var episode in Query(user, [BaseItemKind.Episode], q => q.IsPlayed = true, 400, ItemSortBy.DatePlayed))
        {
            if (episode is not Episode { SeriesId: var seriesId } || seriesId == Guid.Empty)
            {
                continue;
            }

            series[seriesId] = series.TryGetValue(seriesId, out var had)
                ? (had.Last, had.Count + 1)
                : (LastPlayed(user, episode), 1);
        }

        foreach (var (seriesId, (last, count)) in series)
        {
            if (!items.TryGetValue(seriesId, out var show))
            {
                continue;
            }

            // One episode says little; three, that they are into it.
            var weight = KostvHomeEngine.Recency(DaysSince(last, now)) * Math.Min(1.0, count / 3.0);
            var unwatched = Query(user, [BaseItemKind.Episode], q =>
            {
                q.IsPlayed = false;
                q.AncestorIds = [seriesId];
            }, 1).Any();
            Add(show, unwatched ? KostvSeedKind.Watching : KostvSeedKind.Finished, weight);
        }

        foreach (var liked in Query(user, [BaseItemKind.Movie, BaseItemKind.Series], q => q.IsFavorite = true, 30))
        {
            Add(liked, KostvSeedKind.Liked, 0.35);
        }

        // What they put on their list says as much of their taste as a favourite.
        foreach (var entry in listed.Take(30))
        {
            if (Guid.TryParse(entry.ItemId, out var id) && items.TryGetValue(id, out var wanted))
            {
                Add(wanted, KostvSeedKind.Liked, 0.35);
            }
        }

        return (seeds.Values.OrderByDescending(s => s.Weight).Take(MaxSeeds).ToList(), series.Keys.ToHashSet());
    }

    private IEnumerable<BaseItem> Query(
        object user,
        BaseItemKind[] kinds,
        Action<InternalItemsQuery>? filter,
        int? limit = null,
        ItemSortBy? newestBy = null)
    {
        var query = new InternalItemsQuery
        {
            IncludeItemTypes = kinds,
            IsVirtualItem = false,
            Recursive = true,
            Limit = limit,
            EnableTotalRecordCount = false
        };
        filter?.Invoke(query);
        if (newestBy.HasValue)
        {
            OrderDescending(query, newestBy.Value);
        }

        // Without the person's limits applied nothing is read, rather than everything.
        if (!UserReflection.ApplyUser(query, user))
        {
            return [];
        }

        try
        {
            return _libraryManager.GetItemsResult(query).Items;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV home: a library query failed");
            return [];
        }
    }

    // The tuple type of OrderBy changed between server versions, so it is built by reflection.
    private static void OrderDescending(InternalItemsQuery query, ItemSortBy sortBy)
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
            // Unordered is still right, only less recent first.
        }
    }

    private DateTime? LastPlayed(object user, BaseItem item) => UserDataOf(user, item)?.LastPlayedDate;

    private UserItemData? UserDataOf(object user, BaseItem item)
    {
        try
        {
            return GetUserData?.Invoke(_userDataManager, [user, item]) as UserItemData;
        }
        catch
        {
            return null;
        }
    }

    // ---------------------------------------------------------------- my list

    /// <summary>
    /// The film or series <paramref name="itemId"/> stands for on a list: itself, or the series
    /// of an episode or season. Null when it is none of those or the person can't see it.
    /// </summary>
    public BaseItem? ListItemFor(Guid itemId, object user)
    {
        var item = _libraryManager.GetItemById(itemId);
        item = item switch
        {
            Episode { SeriesId: var s } when s != Guid.Empty => _libraryManager.GetItemById(s),
            Season { SeriesId: var s } when s != Guid.Empty => _libraryManager.GetItemById(s),
            _ => item
        };
        return item is Movie or Series && UserReflection.IsVisibleTo(item, user) ? item : null;
    }

    /// <summary>
    /// Puts <paramref name="item"/> on the person's list, or with <paramref name="remove"/> takes
    /// it off. <paramref name="arrived"/>: put on by itself, because something they asked for
    /// arrived; only the first time. Whether it is on the list afterwards.
    /// </summary>
    public async Task<bool> SetOnListAsync(Guid userId, BaseItem item, bool remove, bool arrived)
    {
        var id = item.Id.ToString("N");
        var changed = remove
            ? _myList.Remove(userId, [id]) > 0
            : _myList.Add(userId, id, KeyOf(item), arrived);
        if (changed)
        {
            await _myList.FlushAsync().ConfigureAwait(false);
            // What is on the list leaves the recommendations, and the other way round.
            _pages.TryRemove(userId, out _);
        }

        return _myList.For(userId).Any(e => e.ItemId == id);
    }

    /// <summary>The person's list, in its three parts.</summary>
    public KostvMyListSections MyList(Guid userId, object user)
    {
        var watching = new List<(BaseItem Item, DateTime When)>();
        var toStart = new List<BaseItem>();
        var watched = new List<(BaseItem Item, DateTime When)>();
        var gone = new List<string>();
        foreach (var entry in _myList.For(userId))
        {
            if (!Guid.TryParse(entry.ItemId, out var id) || _libraryManager.GetItemById(id) is not { } item)
            {
                gone.Add(entry.ItemId);
                continue;
            }

            if (!UserReflection.IsVisibleTo(item, user))
            {
                continue;
            }

            var (state, when) = Progress(user, item);
            switch (state)
            {
                case KostvListState.Watching:
                    watching.Add((item, when ?? entry.AddedAt.UtcDateTime));
                    break;
                case KostvListState.Watched:
                    watched.Add((item, when ?? entry.AddedAt.UtcDateTime));
                    break;
                default:
                    toStart.Add(item);
                    break;
            }
        }

        // What is no longer on the server leaves the list.
        if (gone.Count > 0)
        {
            _myList.Remove(userId, gone);
            _ = _myList.FlushAsync();
        }

        return new KostvMyListSections(
            watching.OrderByDescending(w => w.When).Select(w => w.Item).ToList(),
            toStart,
            watched.OrderByDescending(w => w.When).Select(w => w.Item).ToList());
    }

    /// <summary>Takes off the person's list everything they have watched; how many went.</summary>
    public async Task<int> ClearWatchedAsync(Guid userId, object user)
    {
        var done = MyList(userId, user).Watched.Select(i => i.Id.ToString("N")).ToList();
        var removed = _myList.Remove(userId, done);
        if (removed > 0)
        {
            await _myList.FlushAsync().ConfigureAwait(false);
            _pages.TryRemove(userId, out _);
        }

        return removed;
    }

    /// <summary>The ids of what is on the person's list.</summary>
    public IReadOnlyList<string> MyListIds(Guid userId) => _myList.For(userId).Select(e => e.ItemId).ToList();

    /// <summary>
    /// How far the person is with a film or series of their list, and when they last watched it.
    /// A series is watched when nothing of it is left unseen, so a new season brings it back.
    /// </summary>
    private (KostvListState State, DateTime? When) Progress(object user, BaseItem item)
    {
        if (item is not Series)
        {
            var data = UserDataOf(user, item);
            return data switch
            {
                { Played: true } => (KostvListState.Watched, data.LastPlayedDate),
                { PlaybackPositionTicks: > 0 } => (KostvListState.Watching, data.LastPlayedDate),
                _ => (KostvListState.ToStart, null)
            };
        }

        var lastPlayed = Query(user, [BaseItemKind.Episode], q =>
        {
            q.IsPlayed = true;
            q.AncestorIds = [item.Id];
        }, 1, ItemSortBy.DatePlayed).FirstOrDefault();
        var partway = Query(user, [BaseItemKind.Episode], q =>
        {
            q.IsResumable = true;
            q.AncestorIds = [item.Id];
        }, 1, ItemSortBy.DatePlayed).FirstOrDefault();
        if (lastPlayed == null && partway == null)
        {
            return (KostvListState.ToStart, null);
        }

        var when = new[] { lastPlayed, partway }
            .Where(e => e != null)
            .Select(e => LastPlayed(user, e!))
            .Max();
        var left = Query(user, [BaseItemKind.Episode], q =>
        {
            q.IsPlayed = false;
            q.AncestorIds = [item.Id];
        }, 1).Any();
        return (left ? KostvListState.Watching : KostvListState.Watched, when);
    }

    // Played with no date known: taken as a couple of months ago.
    private static double DaysSince(DateTime? when, DateTimeOffset now) =>
        when.HasValue ? Math.Max(0, (now.UtcDateTime - when.Value.ToUniversalTime()).TotalDays) : 60;

    internal static string? KeyOf(BaseItem item)
    {
        var id = item.GetProviderId(MetadataProvider.Tmdb);
        return string.IsNullOrWhiteSpace(id) || !long.TryParse(id, out var number)
            ? null
            : $"{(item is Series ? "tv" : "movie")}:{number}";
    }

    // ---------------------------------------------------------------- TMDB

    private async Task<KostvTasteEntry?> SeedFactsAsync(string key, string apiKey)
    {
        if (_cache.Get(key) is { } cached)
        {
            return cached;
        }

        var parts = key.Split(':');
        var (type, id) = (parts[0], parts[1]);
        using var first = await GetAsync($"{TmdbUrl}/3/{type}/{id}?append_to_response=recommendations,credits", apiKey).ConfigureAwait(false);
        if (first == null)
        {
            return null;
        }

        var entry = ParseSeed(first.RootElement, type);
        for (var page = 2; page <= RecommendationPages; page++)
        {
            using var more = await GetAsync($"{TmdbUrl}/3/{type}/{id}/recommendations?page={page}", apiKey).ConfigureAwait(false);
            if (more == null || !AddRecommendations(entry.Recs, more.RootElement, type))
            {
                break;
            }
        }

        _cache.Set(key, entry);
        return entry;
    }

    private async Task<KostvTasteEntry?> PersonCreditsAsync(string personId, string apiKey)
    {
        var key = "person:" + personId;
        if (_cache.Get(key) is { } cached)
        {
            return cached;
        }

        using var doc = await GetAsync($"{TmdbUrl}/3/person/{personId}/combined_credits", apiKey).ConfigureAwait(false);
        if (doc == null)
        {
            return null;
        }

        var entry = new KostvTasteEntry { Credits = ParseCredits(doc.RootElement) };
        _cache.Set(key, entry);
        return entry;
    }

    /// <summary>A title's recommendations (first page) and its director or creator and leads.</summary>
    internal static KostvTasteEntry ParseSeed(JsonElement root, string type)
    {
        var entry = new KostvTasteEntry();
        if (root.TryGetProperty("recommendations", out var recommendations))
        {
            AddRecommendations(entry.Recs, recommendations, type);
        }

        void AddPerson(JsonElement person, bool director)
        {
            if (person.TryGetProperty("id", out var id) && id.TryGetInt64(out var number) &&
                person.TryGetProperty("name", out var name) && name.GetString() is { Length: > 0 } text &&
                entry.People.All(p => p.Id != number.ToString()))
            {
                entry.People.Add(new KostvTastePerson { Id = number.ToString(), Name = text, Director = director });
            }
        }

        if (root.TryGetProperty("created_by", out var creators) && creators.ValueKind == JsonValueKind.Array)
        {
            foreach (var creator in creators.EnumerateArray().Take(1))
            {
                AddPerson(creator, true);
            }
        }

        if (root.TryGetProperty("credits", out var credits))
        {
            if (credits.TryGetProperty("crew", out var crew) && crew.ValueKind == JsonValueKind.Array)
            {
                foreach (var member in crew.EnumerateArray()
                    .Where(m => m.TryGetProperty("job", out var job) && job.GetString() == "Director")
                    .Take(1))
                {
                    AddPerson(member, true);
                }
            }

            if (credits.TryGetProperty("cast", out var cast) && cast.ValueKind == JsonValueKind.Array)
            {
                foreach (var member in cast.EnumerateArray().Take(2))
                {
                    AddPerson(member, false);
                }
            }
        }

        return entry;
    }

    /// <summary>Adds a page of recommendations; false when the page had none.</summary>
    internal static bool AddRecommendations(List<string> into, JsonElement page, string type)
    {
        if (!page.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        var any = false;
        foreach (var result in results.EnumerateArray())
        {
            if (!result.TryGetProperty("id", out var id) || !id.TryGetInt64(out var number))
            {
                continue;
            }

            var kind = result.TryGetProperty("media_type", out var media) && media.GetString() is "movie" or "tv"
                ? media.GetString()!
                : type;
            var key = $"{kind}:{number}";
            if (!into.Contains(key))
            {
                into.Add(key);
            }

            any = true;
        }

        return any;
    }

    /// <summary>What a person acted in or directed, the best known first.</summary>
    internal static List<string> ParseCredits(JsonElement root)
    {
        var found = new List<(string Key, double Popularity)>();

        void Add(JsonElement credit)
        {
            if (credit.TryGetProperty("id", out var id) && id.TryGetInt64(out var number) &&
                credit.TryGetProperty("media_type", out var media) && media.GetString() is "movie" or "tv")
            {
                var popularity = credit.TryGetProperty("popularity", out var p) && p.TryGetDouble(out var value) ? value : 0;
                found.Add(($"{media.GetString()}:{number}", popularity));
            }
        }

        if (root.TryGetProperty("cast", out var cast) && cast.ValueKind == JsonValueKind.Array)
        {
            foreach (var credit in cast.EnumerateArray())
            {
                Add(credit);
            }
        }

        if (root.TryGetProperty("crew", out var crew) && crew.ValueKind == JsonValueKind.Array)
        {
            foreach (var credit in crew.EnumerateArray()
                .Where(c => c.TryGetProperty("job", out var job) && job.GetString() == "Director"))
            {
                Add(credit);
            }
        }

        return found.OrderByDescending(f => f.Popularity).Select(f => f.Key).Distinct().ToList();
    }

    private async Task<JsonDocument?> GetAsync(string url, string apiKey)
    {
        await _tmdbGate.WaitAsync().ConfigureAwait(false);
        try
        {
            var client = _httpClientFactory.CreateClient("MoonfinHttpClient");
            for (var attempt = 0; attempt < 2; attempt++)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                TmdbRequestHelper.ApplyAuth(request, apiKey);
                using var response = await client.SendAsync(request).ConfigureAwait(false);
                if ((int)response.StatusCode == 429 && attempt == 0)
                {
                    await Task.Delay(TimeSpan.FromSeconds(2)).ConfigureAwait(false);
                    continue;
                }

                if (!response.IsSuccessStatusCode)
                {
                    _logger.LogDebug("kOS TV home: TMDB answered {Status}", (int)response.StatusCode);
                    return null;
                }

                await using var stream = await response.Content.ReadAsStreamAsync().ConfigureAwait(false);
                return await JsonDocument.ParseAsync(stream).ConfigureAwait(false);
            }

            return null;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "kOS TV home: TMDB could not be reached");
            return null;
        }
        finally
        {
            _tmdbGate.Release();
        }
    }
}
