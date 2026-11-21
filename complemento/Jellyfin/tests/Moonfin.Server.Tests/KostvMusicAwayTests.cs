using System.Text.Json;
using Jellyfin.Data.Entities;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Playlists;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Querying;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: songs not at home («Toda la música») in the server's playlists and with a heart: the
/// «huecos» of each playlist and who may see and change them, the hearts of each person and what
/// they weigh in the taste, and what is done when one of those songs comes home.
/// </summary>
public sealed class KostvMusicAwayTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-away-" + Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 11, 21, 10, 0, 0, TimeSpan.Zero);

    // The server: its people, items and playlists.
    private readonly Dictionary<Guid, User> _users = [];
    private readonly Dictionary<Guid, BaseItem> _items = [];
    private readonly List<(object User, BaseItem Item)> _hearted = [];
    private readonly HashSet<(Guid User, Guid Item)> _hidden = [];
    private int _adds;
    private int _moves;

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private Guid Person(string name)
    {
        var user = new User(name, "auth", "reset");
        _users[user.Id] = user;
        return user.Id;
    }

    private Audio Song(string title, string artist, string album, int seconds = 200)
    {
        var song = new Audio { Id = Guid.NewGuid(), Name = title, Artists = [artist], Album = album, RunTimeTicks = TimeSpan.FromSeconds(seconds).Ticks };
        _items[song.Id] = song;
        return song;
    }

    private Playlist List(Guid owner, IEnumerable<BaseItem>? songs = null, bool open = false, params (Guid User, bool CanEdit)[] shares)
    {
        var playlist = new Playlist
        {
            Id = Guid.NewGuid(),
            Name = "Lista",
            OwnerUserId = owner,
            OpenAccess = open,
            Shares = shares.Select(s => new PlaylistUserPermissions(s.User, s.CanEdit)).ToList(),
            LinkedChildren = (songs ?? []).Select(s => new LinkedChild { Id = Guid.NewGuid().ToString("N"), ItemId = s.Id }).ToArray()
        };
        _items[playlist.Id] = playlist;
        return playlist;
    }

    private ILibraryManager Library() => RecordingHostProxy.Create<ILibraryManager>((method, args) => method.Name switch
    {
        "GetItemById" when args is [Guid id] => _items.GetValueOrDefault(id),
        "GetItemsResult" => new QueryResult<BaseItem>(_items.Values
            .Where(i => i is Audio && ((InternalItemsQuery)args![0]!).SearchTerm is { } term && i.Name.Contains(term, StringComparison.OrdinalIgnoreCase))
            .ToList()),
        _ => throw new NotSupportedException(method.Name)
    });

    /// <summary>The server's playlist manager of 10.10: adds at the end, moves by the element's id.</summary>
    private IPlaylistManager Playlists() => RecordingHostProxy.Create<IPlaylistManager>((method, args) =>
    {
        switch (method.Name)
        {
            case "AddItemToPlaylistAsync" when args is [Guid playlistId, IReadOnlyCollection<Guid> ids, Guid _]:
            {
                _adds++;
                var playlist = (Playlist)_items[playlistId];
                var have = playlist.LinkedChildren.Select(c => c.ItemId).ToHashSet();
                playlist.LinkedChildren = [.. playlist.LinkedChildren, .. ids.Where(id => !have.Contains(id)).Select(id => new LinkedChild { Id = Guid.NewGuid().ToString("N"), ItemId = id })];
                return Task.CompletedTask;
            }

            case "MoveItemAsync" when args is [string playlistId, string entryId, int index]:
            {
                _moves++;
                var playlist = (Playlist)_items[Guid.Parse(playlistId)];
                var children = playlist.LinkedChildren.ToList();
                var child = children.Single(c => c.Id == entryId);
                children.Remove(child);
                children.Insert(Math.Min(index, children.Count), child);
                playlist.LinkedChildren = children.ToArray();
                return Task.CompletedTask;
            }

            default:
                throw new NotSupportedException(method.Name);
        }
    });

    private KostvAwayStore NewStore() => new(_root, () => _now);

    private KostvMusicAway NewAway(KostvAwayStore? store = null, IPlaylistManager? playlists = null) =>
        new(Library(), null!, new KostvPlaylistEditor(playlists ?? Playlists()), store ?? NewStore(), NullLogger<KostvMusicAway>.Instance)
        {
            UserOf = id => _users.GetValueOrDefault(id),
            Sees = (item, user) => !_hidden.Contains((((User)user).Id, item.Id)),
            SetFavorite = (user, item) =>
            {
                _hearted.Add((user, item));
                return true;
            }
        };

    private sealed class Services(object users) : IServiceProvider
    {
        public object? GetService(Type serviceType) => serviceType == typeof(IUserManager) ? users : null;
    }

    private KostvMusicAwayController Controller(KostvMusicAway away, Guid userId)
    {
        var users = RecordingHostProxy.Create<IUserManager>((method, args) => method.Name == "GetUserById" && args is [Guid id] ? _users.GetValueOrDefault(id) : null);
        var http = new Microsoft.AspNetCore.Http.DefaultHttpContext
        {
            User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity([new System.Security.Claims.Claim("Jellyfin-UserId", userId.ToString())], "test")),
            RequestServices = new Services(users)
        };
        return new KostvMusicAwayController(away) { ControllerContext = new ControllerContext { HttpContext = http } };
    }

    private static JsonElement Body(object value) => JsonSerializer.SerializeToElement(value);

    private static JsonElement Json(IActionResult result) => JsonDocument.Parse(Assert.IsType<ContentResult>(result).Content!).RootElement.Clone();

    private static object Away(string deezerId, string title = "Canción de fuera", string? artist = "Fuera de Casa", string? album = "Disco de fuera", int? duration = 200, bool isExplicit = false) =>
        new { DeezerId = deezerId, Title = title, Artist = artist, Album = album, AlbumDeezerId = "302127", ArtistDeezerId = "27", Cover = "https://e-cdns-images.dzcdn.net/images/cover/abc/500x500.jpg", Duration = duration, Explicit = isExplicit };

    private static KostvAwaySong Entry(string deezerId, string? after) => new() { DeezerId = deezerId, Title = "T" + deezerId, After = after };

    private static string S(string deezerId) => "stremfin:" + deezerId;

    private static string N(BaseItem item) => item.Id.ToString("N");

    private static List<string> Keys(JsonElement list) =>
        list.GetProperty("Entries").EnumerateArray().Select(e => e.GetProperty("DeezerId").GetString()!).ToList();

    // ---------------------------------------------------------------- the order of a playlist

    [Fact]
    public void TheWholeListPlacesEachSongNotAtHomeAfterItsElement()
    {
        var jellyfin = new List<string> { "a", "b", "c" };
        var entries = new List<KostvAwaySong>
        {
            Entry("1", "b"),
            Entry("2", null),
            Entry("3", S("1")),
            Entry("4", "gone"),
            Entry("5", S("4"))
        };

        // The first ones at the start; after b the 1 and the one after it; what was after an
        // element no longer there, at the end, with what follows it.
        Assert.Equal([S("2"), "a", "b", S("1"), S("3"), "c", S("4"), S("5")], KostvAwayOrder.Merged(jellyfin, entries));
        Assert.Equal(0, KostvAwayOrder.TargetIndex(jellyfin, entries, "2"));
        Assert.Equal(2, KostvAwayOrder.TargetIndex(jellyfin, entries, "3"));
        Assert.Equal(3, KostvAwayOrder.TargetIndex(jellyfin, entries, "5"));

        // A cycle written by hand doesn't hang it, nor loses the songs.
        var cycle = new List<KostvAwaySong> { Entry("1", S("2")), Entry("2", S("1")) };
        Assert.Equal(2, KostvAwayOrder.Merged(["a"], cycle).Count(k => k.StartsWith("stremfin:")));

        // A long chain, one after the other.
        var chain = Enumerable.Range(1, 500).Select(i => Entry(i.ToString(), i == 1 ? "a" : S((i - 1).ToString()))).ToList();
        Assert.Equal(["a", .. Enumerable.Range(1, 500).Select(i => S(i.ToString()))], KostvAwayOrder.Merged(["a"], chain));
    }

    [Fact]
    public void SongsAddedGoRightAfterTheirElementOrAtTheEnd()
    {
        var jellyfin = new List<string> { "a", "b" };
        var entries = new List<KostvAwaySong> { Entry("1", "a") };
        KostvAwaySong New(string id) => new() { DeezerId = id, Title = "T" + id };

        // After a: before what was after it.
        Assert.Equal(KostvAwayOrder.InsertRefusal.None, KostvAwayOrder.Insert(entries, jellyfin, [New("2"), New("3")], true, "a", _now));
        Assert.Equal(["a", S("2"), S("3"), S("1"), "b"], KostvAwayOrder.Merged(jellyfin, entries));
        Assert.All(entries.Where(e => e.DeezerId != "1"), e => Assert.Equal(_now, e.Added));

        // Without After: at the end of the whole list.
        KostvAwayOrder.Insert(entries, jellyfin, [New("4")], false, null, _now);
        Assert.Equal(["a", S("2"), S("3"), S("1"), "b", S("4")], KostvAwayOrder.Merged(jellyfin, entries));
        Assert.Equal("b", entries.Single(e => e.DeezerId == "4").After);

        // After null: the first.
        KostvAwayOrder.Insert(entries, jellyfin, [New("5")], true, null, _now);
        Assert.Equal(S("5"), KostvAwayOrder.Merged(jellyfin, entries)[0]);

        // One already in it isn't added again, nor moved; nor one said twice.
        KostvAwayOrder.Insert(entries, jellyfin, [New("2"), New("6"), New("6")], true, "b", _now);
        Assert.Equal(6, entries.Count);
        Assert.Equal(["a", S("2"), S("3"), S("1"), "b", S("6"), S("4")], KostvAwayOrder.Merged(jellyfin, entries).Skip(1));

        // Not after one of those added.
        Assert.Equal(KostvAwayOrder.InsertRefusal.AfterItself, KostvAwayOrder.Insert(entries, jellyfin, [New("7")], true, S("7"), _now));
        // Up to 500.
        var many = Enumerable.Range(100, KostvAwayStore.MaxPerPlaylist - 5).Select(i => New(i.ToString())).ToList();
        Assert.Equal(KostvAwayOrder.InsertRefusal.TooMany, KostvAwayOrder.Insert(entries, jellyfin, many, false, null, _now));
        Assert.Equal(6, entries.Count);
        Assert.Equal(KostvAwayOrder.InsertRefusal.None, KostvAwayOrder.Insert(entries, jellyfin, many.Take(KostvAwayStore.MaxPerPlaylist - 6).ToList(), false, null, _now));
        Assert.Equal(KostvAwayStore.MaxPerPlaylist, entries.Count);
    }

    [Fact]
    public void TakingOneOutOrReorderingKeepsTheRestInTheirPlace()
    {
        var jellyfin = new List<string> { "a", "b" };
        var entries = new List<KostvAwaySong> { Entry("1", "a"), Entry("2", S("1")), Entry("3", "b") };

        Assert.True(KostvAwayOrder.Remove(entries, "1"));
        Assert.False(KostvAwayOrder.Remove(entries, "1"));
        Assert.Equal(["a", S("2"), "b", S("3")], KostvAwayOrder.Merged(jellyfin, entries));

        // The whole order as the app has it now (b moved first by the app, with the server's routes).
        KostvAwayOrder.Reorder(entries, [S("3"), "b", "a", S("2")]);
        Assert.Equal([S("3"), "b", "a", S("2")], KostvAwayOrder.Merged(["b", "a"], entries));
        Assert.Equal((null, "a"), (entries.Single(e => e.DeezerId == "3").After, entries.Single(e => e.DeezerId == "2").After));

        Assert.Equal("stremfin:12", KostvAwayOrder.NormalizeId(" stremfin:12 "));
        var id = Guid.NewGuid();
        Assert.Equal(id.ToString("N"), KostvAwayOrder.NormalizeId(id.ToString()));
        Assert.Null(KostvAwayOrder.NormalizeId("stremfin:abc"));
        Assert.Null(KostvAwayOrder.NormalizeId(Guid.Empty.ToString()));
        Assert.Null(KostvAwayOrder.NormalizeId("12"));
    }

    // ---------------------------------------------------------------- the playlist routes

    [Fact]
    public async Task APlaylistsSongsNotAtHomeAreForWhoeverSeesItAndChangedByWhoeverMayChangeIt()
    {
        var ana = Person("ana");
        var luis = Person("luis");
        var eva = Person("eva");
        var pepe = Person("pepe");
        var home = Song("De casa", "Artista", "Disco");
        var playlist = List(ana, [home], shares: [(luis, true), (eva, false)]);
        var away = NewAway();

        // Its owner adds; after the song at home.
        var added = Json(await Controller(away, ana).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("1"), Away("2") }, After = home.Id.ToString() })));
        Assert.Equal(["1", "2"], Keys(added));
        var first = added.GetProperty("Entries")[0];
        Assert.Equal(N(home), first.GetProperty("After").GetString());
        Assert.Equal(("Canción de fuera", "Fuera de Casa", "Disco de fuera", 200, false), (first.GetProperty("Title").GetString(), first.GetProperty("Artist").GetString(), first.GetProperty("Album").GetString(), first.GetProperty("Duration").GetInt32(), first.GetProperty("Explicit").GetBoolean()));
        Assert.Equal(("302127", "27"), (first.GetProperty("AlbumDeezerId").GetString(), first.GetProperty("ArtistDeezerId").GetString()));
        Assert.Equal(_now.UtcDateTime, first.GetProperty("Added").GetDateTime());
        Assert.Equal(S("1"), added.GetProperty("Entries")[1].GetProperty("After").GetString());

        // Shared to edit: adds, first in the list (After null, written).
        var byLuis = Json(await Controller(away, luis).AddToPlaylist(playlist.Id.ToString("N"), Body(new { Songs = new[] { Away("3") }, After = (string?)null })));
        Assert.Equal(["3", "1", "2"], Keys(byLuis));
        Assert.Equal(JsonValueKind.Null, byLuis.GetProperty("Entries")[0].GetProperty("After").ValueKind);

        // Shared to see: sees it, may not change it.
        Assert.Equal(["3", "1", "2"], Keys(Json(Controller(away, eva).GetPlaylist(playlist.Id.ToString()))));
        Assert.Equal(403, Assert.IsType<ObjectResult>(await Controller(away, eva).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("4") } }))).StatusCode);
        Assert.Equal(403, Assert.IsType<ObjectResult>(await Controller(away, eva).RemoveFromPlaylist(playlist.Id.ToString(), "1")).StatusCode);
        Assert.Equal(403, Assert.IsType<ObjectResult>(await Controller(away, eva).OrderPlaylist(playlist.Id.ToString(), Body(new { Ids = Array.Empty<string>() }))).StatusCode);

        // Not shared: as if it weren't there.
        Assert.IsType<NotFoundObjectResult>(Controller(away, pepe).GetPlaylist(playlist.Id.ToString()));
        Assert.IsType<NotFoundObjectResult>(await Controller(away, pepe).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("4") } })));
        Assert.IsType<NotFoundObjectResult>(Controller(away, ana).GetPlaylist(Guid.NewGuid().ToString()));
        Assert.IsType<NotFoundObjectResult>(Controller(away, ana).GetPlaylist("lista"));
        // Not a playlist.
        Assert.IsType<NotFoundObjectResult>(Controller(away, ana).GetPlaylist(home.Id.ToString()));

        // Open to all: anyone sees it, only its owner (and who it's shared with to edit) changes it.
        var open = List(ana, open: true);
        await Controller(away, ana).AddToPlaylist(open.Id.ToString(), Body(new { Songs = new[] { Away("9") } }));
        Assert.Equal(["9"], Keys(Json(Controller(away, pepe).GetPlaylist(open.Id.ToString()))));
        Assert.Equal(403, Assert.IsType<ObjectResult>(await Controller(away, pepe).RemoveFromPlaylist(open.Id.ToString(), "9")).StatusCode);

        // Taken out (also when it wasn't in it), as a Deezer id or stremfin:<id>.
        Assert.IsType<NoContentResult>(await Controller(away, luis).RemoveFromPlaylist(playlist.Id.ToString(), "stremfin:1"));
        Assert.IsType<NoContentResult>(await Controller(away, ana).RemoveFromPlaylist(playlist.Id.ToString(), "1"));
        Assert.IsType<BadRequestObjectResult>(await Controller(away, ana).RemoveFromPlaylist(playlist.Id.ToString(), "uno"));
        var now = Json(Controller(away, ana).GetPlaylist(playlist.Id.ToString()));
        Assert.Equal(["3", "2"], Keys(now));
        // What was after it, after what it was after.
        Assert.Equal(N(home), now.GetProperty("Entries")[1].GetProperty("After").GetString());

        // The order as the app has it now.
        Assert.IsType<NoContentResult>(await Controller(away, ana).OrderPlaylist(playlist.Id.ToString(), Body(new { Ids = new[] { home.Id.ToString(), "stremfin:2", "stremfin:3" } })));
        Assert.Equal(["2", "3"], Keys(Json(Controller(away, ana).GetPlaylist(playlist.Id.ToString()))));
        Assert.IsType<BadRequestObjectResult>(await Controller(away, ana).OrderPlaylist(playlist.Id.ToString(), Body(new { Ids = new[] { "otra" } })));
        Assert.IsType<BadRequestObjectResult>(await Controller(away, ana).OrderPlaylist(playlist.Id.ToString(), Body(new { })));

        // Kept in a file of the playlist, the same for all, read after a restart.
        Assert.True(File.Exists(Path.Combine(_root, KostvAwayStore.PlaylistsFolder, playlist.Id.ToString("N") + ".json")));
        Assert.Equal(["2", "3"], NewStore().Entries(playlist.Id).Select(e => e.DeezerId));
    }

    [Fact]
    public async Task WhatIsNotAsSaidIsTurnedAway()
    {
        var ana = Person("ana");
        var playlist = List(ana);
        var away = NewAway();
        var controller = Controller(away, ana);
        var long300 = new string('a', 300);

        object[] wrong =
        [
            new { },
            new { Songs = Array.Empty<object>() },
            new { Songs = new[] { new { DeezerId = "12a", Title = "x" } } },
            new { Songs = new[] { new { DeezerId = new string('1', 33), Title = "x" } } },
            new { Songs = new[] { new { DeezerId = "12" } } },
            new { Songs = new object[] { new { DeezerId = "12", Title = "x", Explicit = "sí" } } },
            new { Songs = new object[] { new { DeezerId = "12", Title = "x", Duration = -1 } } },
            new { Songs = new object[] { new { DeezerId = "12", Title = "x", Cover = "javascript:alert(1)" } } },
            new { Songs = new object[] { new { DeezerId = "12", Title = "x", AlbumDeezerId = "abc" } } },
            new { Songs = new object[] { new { DeezerId = "12", Title = 3 } } },
            new { Songs = new[] { Away("1") }, After = "otra" },
            new { Songs = new[] { Away("1") }, After = 3 },
            new { Songs = new[] { Away("1") }, After = "stremfin:1" }
        ];
        foreach (var body in wrong)
        {
            Assert.IsType<BadRequestObjectResult>(await controller.AddToPlaylist(playlist.Id.ToString(), Body(body)));
        }

        Assert.Empty(away.Store.Entries(playlist.Id));

        // A number for a Deezer id is fine; a text too long is cut, not turned away.
        var kept = Json(await controller.AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new object[] { new { DeezerId = 3135556, Title = long300, Artist = long300, Album = (string?)null } } })));
        var song = kept.GetProperty("Entries")[0];
        Assert.Equal("3135556", song.GetProperty("DeezerId").GetString());
        Assert.Equal(200, song.GetProperty("Title").GetString()!.Length);
        Assert.Equal(200, song.GetProperty("Artist").GetString()!.Length);
        Assert.Equal(JsonValueKind.Null, song.GetProperty("Album").ValueKind);
        Assert.False(song.GetProperty("Explicit").GetBoolean());

        // Up to 500 in a playlist.
        var many = Enumerable.Range(1000, KostvAwayStore.MaxPerPlaylist).Select(i => Away(i.ToString())).ToArray();
        Assert.IsType<BadRequestObjectResult>(await controller.AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = many })));
        Assert.Single(away.Store.Entries(playlist.Id));
    }

    [Fact]
    public async Task APlaylistDeletedTakesItsSongsNotAtHomeWithIt()
    {
        var ana = Person("ana");
        var gone = List(ana);
        var stays = List(ana);
        var store = NewStore();
        var away = NewAway(store);
        await Controller(away, ana).AddToPlaylist(gone.Id.ToString(), Body(new { Songs = new[] { Away("1") } }));
        await Controller(away, ana).AddToPlaylist(stays.Id.ToString(), Body(new { Songs = new[] { Away("2") } }));

        // The server says it was deleted.
        var watcher = new KostvMusicAwayWatcher(Library(), away, new KostvMusicStore(_root, () => _now), NullLogger<KostvMusicAwayWatcher>.Instance);
        _items.Remove(gone.Id);
        watcher.OnItemRemoved(null, new ItemChangeEventArgs { Item = gone });
        for (var i = 0; i < 100 && store.Playlists().Contains(gone.Id); i++)
        {
            await Task.Delay(20);
        }

        Assert.Equal([stays.Id], store.Playlists());

        // One the server deleted while the plugin was off: gone in the daily round.
        _items.Remove(stays.Id);
        await away.RoundAsync();
        Assert.Empty(store.Playlists());
        Assert.False(File.Exists(AtomicBackup(stays.Id)));
    }

    private string AtomicBackup(Guid playlistId) => Path.Combine(_root, KostvAwayStore.PlaylistsFolder, playlistId.ToString("N") + ".json.bak");

    // ---------------------------------------------------------------- hearts

    [Fact]
    public void EachPersonsHeartsOnSongsNotAtHome()
    {
        var ana = Person("ana");
        var luis = Person("luis");
        var away = NewAway();
        var controller = Controller(away, ana);

        Assert.IsType<NoContentResult>(controller.AddFavorite(Body(Away("1", title: "Primera"))));
        _now = _now.AddMinutes(1);
        Assert.IsType<NoContentResult>(controller.AddFavorite(Body(Away("2", title: "Segunda"))));
        _now = _now.AddMinutes(1);
        // Said again: when it was first put on, with what the app says of it now.
        Assert.IsType<NoContentResult>(controller.AddFavorite(Body(Away("1", title: "Primera (otra vez)"))));

        var songs = Json(controller.GetFavorites()).GetProperty("Songs");
        Assert.Equal(["2", "1"], songs.EnumerateArray().Select(s => s.GetProperty("DeezerId").GetString()));
        Assert.Equal("Primera (otra vez)", songs[1].GetProperty("Title").GetString());
        Assert.Equal(_now.AddMinutes(-2).UtcDateTime, songs[1].GetProperty("Added").GetDateTime());
        Assert.False(songs[0].TryGetProperty("After", out _));

        // Each person their own, kept in their folder.
        Assert.Empty(Json(Controller(away, luis).GetFavorites()).GetProperty("Songs").EnumerateArray());
        Assert.True(File.Exists(Path.Combine(_root, ana.ToString("N"), KostvAwayStore.FavoritesFile)));

        Assert.IsType<NoContentResult>(controller.RemoveFavorite("stremfin:2"));
        Assert.IsType<NoContentResult>(controller.RemoveFavorite("2"));
        Assert.IsType<BadRequestObjectResult>(controller.RemoveFavorite("dos"));
        Assert.IsType<BadRequestObjectResult>(controller.AddFavorite(Body(new { DeezerId = "x", Title = "y" })));
        Assert.Equal(["1"], NewStore().Favorites(ana).Select(s => s.DeezerId));

        // Up to 2000.
        var store = NewStore();
        for (var i = 0; i < KostvAwayStore.MaxFavorites - 1; i++)
        {
            Assert.Equal(KostvAwayStore.FavoriteResult.Stored, store.AddFavorite(luis, new KostvAwaySong { DeezerId = (5000 + i).ToString(), Title = "t" }));
        }

        Assert.Equal(KostvAwayStore.FavoriteResult.Stored, store.AddFavorite(luis, new KostvAwaySong { DeezerId = "1", Title = "t" }));
        Assert.IsType<BadRequestObjectResult>(Controller(away, luis).AddFavorite(Body(Away("2"))));
        // One already there may still be said again.
        Assert.IsType<NoContentResult>(Controller(away, luis).AddFavorite(Body(Away("1"))));
    }

    [Fact]
    public void AHeartOnASongNotAtHomeWeighsItsArtistAsOneAtHome()
    {
        var home = new KostvMusicTrack(Guid.NewGuid(), ["De Casa"], ["Pop"], 3, new DateTime(2026, 11, 10, 0, 0, 0, DateTimeKind.Utc));
        var hearts = new[] { new KostvAwayHeart("1", "Fuera de Casa"), new KostvAwayHeart("2", null), new KostvAwayHeart("x", "Otro") };
        foreach (var profile in new[]
        {
            KostvMusicEngine.LearnedProfile([home], null, _now, null, hearts),
            KostvMusicEngine.Profile([home], new Dictionary<Guid, KostvTrackListens>(), _now, null, null, hearts)
        })
        {
            // Never heard, its artist counts; one without an artist, or not a Deezer id, doesn't.
            Assert.Contains(profile.Artists, a => a.Name == "Fuera de Casa" && a.Weight > 0);
            Assert.DoesNotContain(profile.Artists, a => a.Name == "Otro");
            Assert.Contains(profile.Artists, a => a.Name == "De Casa");
        }

        var learned = KostvMusicEngine.LearnedProfile([home], null, _now, null, hearts);
        Assert.Contains(learned.Background!, a => a.Name == "Fuera de Casa");
        Assert.Contains(learned.Recent!, a => a.Name == "Fuera de Casa");

        // Heard and skipped often: out, unless it has a heart; and the heart adds to what was heard.
        var events = Enumerable.Range(0, 5).Select(i => new KostvMusicEvent
        {
            Item = "stremfin:1",
            Title = "Canción",
            Artists = ["Fuera de Casa"],
            Genres = ["Indie"],
            Played = 10,
            Duration = 200,
            Outcome = KostvListenOutcome.Skipped
        }.Stamp(_now.AddDays(-i - 1), TimeZoneInfo.Utc)).ToList();
        var summary = KostvMusicEngine.Summarize(events, _now);
        Assert.DoesNotContain(KostvMusicEngine.LearnedProfile([home], summary, _now).Artists, a => a.Name == "Fuera de Casa");
        var hearted = KostvMusicEngine.LearnedProfile([home], summary, _now, null, [new KostvAwayHeart("1", "Fuera de Casa")]);
        Assert.Contains(hearted.Artists, a => a.Name == "Fuera de Casa");
        // With its genre, from what was heard.
        Assert.Contains(hearted.Genres, g => g.Name == "Indie");

        // «No me gusta» to the song, or its artist: no heart counts.
        var dislikes = new KostvDislikeSet([], [], new Dictionary<string, int>(), streamedSongs: ["1"]);
        Assert.DoesNotContain(KostvMusicEngine.LearnedProfile([home], null, _now, dislikes, hearts).Artists, a => a.Name == "Fuera de Casa");
        var artistOut = new KostvDislikeSet([], ["Fuera de Casa"], new Dictionary<string, int>());
        Assert.DoesNotContain(KostvMusicEngine.Profile([home], new Dictionary<Guid, KostvTrackListens>(), _now, artistOut, null, hearts).Artists, a => a.Name == "Fuera de Casa");
    }

    [Fact]
    public async Task TheTasteTakesTheHeartsOfThePluginsStore()
    {
        var ana = Guid.NewGuid();
        var store = NewStore();
        store.AddFavorite(ana, new KostvAwaySong { DeezerId = "1", Title = "Canción", Artist = "Fuera de Casa" });
        var library = RecordingHostProxy.Create<ILibraryManager>((method, _) => method.Name switch
        {
            "GetItemList" => new List<BaseItem>(),
            "GetItemsResult" => new QueryResult<BaseItem>(new List<BaseItem>()),
            "GetItemIds" => new List<Guid>(),
            _ => null
        });
        var music = new KostvMusicService(library, RecordingHostProxy.Create<IUserDataManager>((_, _) => null), new KostvMusicStore(_root, () => _now), NullLogger<KostvMusicService>.Instance, store)
        {
            Sees = (_, _) => true
        };

        var taste = await music.TasteAsync(ana, new User("ana", "auth", "reset"));
        Assert.Contains(taste.Artists, a => a.Name == "Fuera de Casa" && a.Id == null);
        Assert.Equal(0, taste.Learned);
    }

    // ---------------------------------------------------------------- a song comes home

    [Fact]
    public async Task ASongComeHomeTakesItsPlaceInThePlaylistsAndItsHeartBecomesTheServers()
    {
        var ana = Person("ana");
        var luis = Person("luis");
        var eva = Person("eva");
        var a = Song("A", "Artista", "Disco");
        var b = Song("B", "Artista", "Disco");
        var playlist = List(ana, [a, b], shares: [(luis, true)]);
        var away = NewAway();
        // a, 1, 2, b, 3 in the whole list.
        await Controller(away, ana).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("1"), Away("2") }, After = a.Id.ToString() }));
        await Controller(away, ana).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("3") } }));
        Controller(away, luis).AddFavorite(Body(Away("1")));
        Controller(away, eva).AddFavorite(Body(Away("1")));
        Controller(away, eva).AddFavorite(Body(Away("2")));
        // Eva may not see the song once at home (out of her libraries).
        var one = Song("Canción de fuera", "Fuera de Casa", "Disco de fuera");
        _hidden.Add((eva, one.Id));

        Assert.IsType<NoContentResult>(await Controller(away, luis).Arrived(Body(new { DeezerId = "1", JellyfinId = one.Id.ToString() })));

        // In the server's list where it was, its «hueco» gone, and what was after it after it.
        Assert.Equal([N(a), N(one), N(b)], KostvMusicAway.JellyfinIdsOf(playlist));
        var entries = away.Store.Entries(playlist.Id);
        Assert.Equal(["2", "3"], entries.Select(e => e.DeezerId));
        Assert.Equal(N(one), entries[0].After);
        Assert.Equal([N(a), N(one), S("2"), N(b), S("3")], KostvAwayOrder.Merged(KostvMusicAway.JellyfinIdsOf(playlist), entries));

        // The server's heart for who had it and may see it; who may not keeps hers, not at home.
        Assert.Equal([luis], _hearted.Select(h => ((User)h.User).Id));
        Assert.Same(one, _hearted[0].Item);
        Assert.Empty(away.Store.Favorites(luis));
        Assert.Equal(["2", "1"], away.Store.Favorites(eva).Select(s => s.DeezerId).OrderByDescending(s => s));

        // Said again: nothing more.
        var adds = _adds;
        Assert.IsType<NoContentResult>(await Controller(away, ana).Arrived(Body(new { DeezerId = "stremfin:1", JellyfinId = one.Id.ToString("N") })));
        Assert.Equal(adds, _adds);
        Assert.Single(_hearted);
        Assert.Equal([N(a), N(one), N(b)], KostvMusicAway.JellyfinIdsOf(playlist));

        // Already in the list some other way: only the «hueco» goes.
        var three = Song("Tres", "Fuera de Casa", "Disco de fuera");
        playlist.LinkedChildren = [.. playlist.LinkedChildren, new LinkedChild { Id = Guid.NewGuid().ToString("N"), ItemId = three.Id }];
        await away.ArriveAsync("3", three);
        Assert.Equal(adds, _adds);
        Assert.Equal(["2"], away.Store.Entries(playlist.Id).Select(e => e.DeezerId));
    }

    [Fact]
    public async Task ASongComeHomeIsOnlyForWhatItsPeopleMaySee()
    {
        var ana = Person("ana");
        var luis = Person("luis");
        var playlist = List(ana);
        var away = NewAway();
        await Controller(away, ana).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("1") } }));
        var one = Song("Canción de fuera", "Fuera de Casa", "Disco de fuera");

        // Not a song of the library, or not one the caller may see: a 404, and nothing done.
        _hidden.Add((luis, one.Id));
        Assert.IsType<NotFoundObjectResult>(await Controller(away, luis).Arrived(Body(new { DeezerId = "1", JellyfinId = one.Id.ToString() })));
        Assert.IsType<NotFoundObjectResult>(await Controller(away, ana).Arrived(Body(new { DeezerId = "1", JellyfinId = playlist.Id.ToString() })));
        Assert.IsType<NotFoundObjectResult>(await Controller(away, ana).Arrived(Body(new { DeezerId = "1", JellyfinId = Guid.NewGuid().ToString() })));
        Assert.IsType<BadRequestObjectResult>(await Controller(away, ana).Arrived(Body(new { DeezerId = "uno", JellyfinId = one.Id.ToString() })));
        Assert.IsType<BadRequestObjectResult>(await Controller(away, ana).Arrived(Body(new { DeezerId = "1" })));
        Assert.Equal(0, _adds);

        // The playlist's owner may not see it: it stays not at home in her list.
        _hidden.Add((ana, one.Id));
        _hidden.Remove((luis, one.Id));
        Assert.IsType<NoContentResult>(await Controller(away, luis).Arrived(Body(new { DeezerId = "1", JellyfinId = one.Id.ToString() })));
        Assert.Equal(0, _adds);
        Assert.Single(away.Store.Entries(playlist.Id));

        // Once she may: at home.
        _hidden.Remove((ana, one.Id));
        await away.ArriveOnceAsync("1", one);
        Assert.Equal([N(one)], KostvMusicAway.JellyfinIdsOf(playlist));
        Assert.Empty(away.Store.Entries(playlist.Id));
        Assert.Empty(away.Store.Playlists());
    }

    [Fact]
    public async Task TheSongsComeHomeAreToldApartAsTheyEnterTheLibraryAndOnTheDailyRound()
    {
        var ana = Person("ana");
        var playlist = List(ana);
        var store = NewStore();
        var away = NewAway(store);
        await Controller(away, ana).AddToPlaylist(playlist.Id.ToString(), Body(new { Songs = new[] { Away("1", title: "Canción de Fuera (Remix)", artist: "Ñandú y Cía", album: "Él disco", duration: 200) } }));
        Controller(away, ana).AddFavorite(Body(Away("2", title: "Otra", artist: "Fuera de Casa", album: "Disco de fuera", duration: 180)));
        var watcher = new KostvMusicAwayWatcher(Library(), away, new KostvMusicStore(_root, () => _now), NullLogger<KostvMusicAwayWatcher>.Instance);

        // Another song, another album, or longer by more than 3 s: not it.
        foreach (var other in new[]
        {
            Song("Canción de fuera (remix)", "Otro", "El Disco"),
            Song("Canción de fuera (remix)", "Ñandú y Cía", "Otro disco"),
            Song("Canción de fuera (remix)", "Ñandú y Cía", "El Disco", seconds: 204)
        })
        {
            Assert.Null(away.Kept(other));
            watcher.OnItemChanged(null, new ItemChangeEventArgs { Item = other });
        }

        await away.Settled();
        Assert.Equal(0, _adds);

        // The same, written otherwise (accents, case, marks) and 3 s off: it came home.
        var one = Song("cancion de fuera - REMIX", "Nandu y Cia", "El disco", seconds: 197);
        Assert.Equal("1", away.Kept(one)?.DeezerId);
        watcher.OnItemChanged(null, new ItemChangeEventArgs { Item = one });
        await away.Settled();
        Assert.Equal([N(one)], KostvMusicAway.JellyfinIdsOf(playlist));
        Assert.Empty(store.Entries(playlist.Id));
        // Kept no longer: told apart no more.
        Assert.Null(away.Kept(one));

        // A song by an album artist; without a length known yet. Found on the daily round.
        var two = new Audio { Id = Guid.NewGuid(), Name = "Otra", Artists = [], AlbumArtists = ["Fuera de Casa"], Album = "Disco de fuera" };
        _items[two.Id] = two;
        Assert.Equal(1, await away.RoundAsync());
        Assert.Equal([two.Id], _hearted.Select(h => h.Item.Id));
        Assert.Empty(store.Favorites(ana));
        Assert.Equal(0, await away.RoundAsync());
    }

    [Fact]
    public void AnAwaySongMatchesByItsNamesAndLength()
    {
        var song = new KostvAwaySong { DeezerId = "1", Title = "Despechá", Artist = "ROSALÍA", Album = "MOTOMAMI +", Duration = 157 };
        Assert.True(KostvMusicAway.Matches(song, new Audio { Name = "despecha", Artists = ["Rosalía"], Album = "Motomami+", RunTimeTicks = TimeSpan.FromSeconds(159).Ticks }));
        Assert.False(KostvMusicAway.Matches(song, new Audio { Name = "despecha", Artists = ["Rosalía"], Album = "Motomami+", RunTimeTicks = TimeSpan.FromSeconds(161).Ticks }));
        Assert.False(KostvMusicAway.Matches(song, new Audio { Name = "despecha", Artists = ["Rosalía"], Album = "El mal querer" }));
        Assert.False(KostvMusicAway.Matches(song, new Audio { Name = "despecha", Artists = ["Rosalía"], Album = "Motomami+", IsVirtualItem = true }));
        Assert.False(KostvMusicAway.Matches(song, new MusicAlbum { Name = "despecha" }));
        // Without an album said, any album.
        song.Album = null;
        Assert.True(KostvMusicAway.Matches(song, new Audio { Name = "Despechá", Artists = ["Otra", "Rosalía"], Album = "Lo que sea" }));
        // Without an artist, never by title alone.
        song.Artist = null;
        Assert.False(KostvMusicAway.Matches(song, new Audio { Name = "Despechá", Artists = ["Rosalía"] }));
        Assert.Equal("mas alla del sol 2", KostvMusicAway.Normalize("  ¡Más allá   del SOL! (2) "));
    }

    // ---------------------------------------------------------------- the server's playlist manager

    /// <summary>The playlist manager as 10.11 has it: where to add, and who moves.</summary>
    public interface INewerPlaylistManager
    {
        Task AddItemToPlaylistAsync(Guid playlistId, IReadOnlyCollection<Guid> newItemIds, int? position, Guid userId);

        Task MoveItemAsync(string playlistId, string entryId, int newIndex, Guid callingUserId);
    }

    private sealed class NewerPlaylistManager : INewerPlaylistManager
    {
        public List<string> Calls { get; } = [];

        public Task AddItemToPlaylistAsync(Guid playlistId, IReadOnlyCollection<Guid> newItemIds, int? position, Guid userId)
        {
            Calls.Add($"add {playlistId:N} {string.Join(",", newItemIds)} {position?.ToString() ?? "null"} {userId:N}");
            return Task.CompletedTask;
        }

        public Task MoveItemAsync(string playlistId, string entryId, int newIndex, Guid callingUserId)
        {
            Calls.Add($"move {playlistId} {entryId} {newIndex} {callingUserId:N}");
            return Task.CompletedTask;
        }
    }

    [Fact]
    public async Task ThePlaylistManagerIsBoundOnEachServerVersion()
    {
        var playlist = Guid.NewGuid();
        var item = Guid.NewGuid();
        var owner = Guid.NewGuid();
        var newer = new NewerPlaylistManager();
        var editor = new KostvPlaylistEditor(newer, typeof(INewerPlaylistManager));
        Assert.True(editor.CanEdit);
        await editor.AddAsync(playlist, item, owner);
        await editor.MoveAsync(playlist, "entry", 2, owner);
        Assert.Equal([$"add {playlist:N} {item} null {owner:N}", $"move {playlist:N} entry 2 {owner:N}"], newer.Calls);

        // 10.10's, as the server gives it.
        Assert.True(new KostvPlaylistEditor(Playlists()).CanEdit);
        // Without one: nothing is changed.
        var none = new KostvPlaylistEditor(null);
        Assert.False(none.CanEdit);
        await Assert.ThrowsAsync<NotSupportedException>(() => none.AddAsync(playlist, item, owner));
    }

    [Fact]
    public void TheServersHeartIsPutOnThroughItsUserData()
    {
        var user = new User("ana", "auth", "reset");
        var song = new Audio { Id = Guid.NewGuid() };
        var data = new UserItemData { Key = song.Id.ToString("N") };
        var saved = new List<(UserItemData Data, UserDataSaveReason Reason)>();
        var userData = RecordingHostProxy.Create<IUserDataManager>((method, args) =>
        {
            switch (method.Name)
            {
                case "GetUserData":
                    return data;
                case "SaveUserData" when args is [_, _, UserItemData d, UserDataSaveReason reason, _]:
                    saved.Add((d, reason));
                    return null;
                default:
                    throw new NotSupportedException(method.Name);
            }
        });

        Assert.True(KostvMusicAway.SetServerFavorite(userData, user, song, NullLogger.Instance));
        Assert.True(data.IsFavorite);
        // As a heart put on by hand: the music notes it as one.
        Assert.Equal([UserDataSaveReason.UpdateUserRating], saved.Select(s => s.Reason));
        // Already on: not saved again.
        Assert.True(KostvMusicAway.SetServerFavorite(userData, user, song, NullLogger.Instance));
        Assert.Single(saved);
        // Not a user: not put on.
        Assert.False(KostvMusicAway.SetServerFavorite(userData, "ana", song, NullLogger.Instance));
    }
}
