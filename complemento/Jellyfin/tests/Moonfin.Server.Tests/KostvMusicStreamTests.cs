using System.Security.Claims;
using System.Text.Json;
using Jellyfin.Data.Entities;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: «Toda la música» in the plugin: each person's setting of what music the app offers,
/// the songs not at home heard through Stremfin noted as listens (and what they weigh in the
/// taste), and «no me gusta» to them.
/// </summary>
public sealed partial class KostvMusicTests
{
    private static object StreamListenBody(
        string deezerId = "3135556",
        string artist = "Fuera de Casa",
        string? genre = "Indie",
        double played = 200,
        double? duration = 200,
        string endedBy = "natural",
        string? source = "discovery",
        bool? shuffle = false) =>
        new { Type = "stream_listen", DeezerId = deezerId, Title = "Canción de fuera", Artist = artist, Album = "Disco de fuera", Genre = genre, Played = played, Duration = duration, EndedBy = endedBy, Source = source, Shuffle = shuffle };

    /// <summary>The caller's session as kOS TV on a TV says it.</summary>
    private static void OnTv(KostvMusicController controller, Guid userId) =>
        controller.ControllerContext.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("Jellyfin-UserId", userId.ToString()),
            new Claim("Jellyfin-Client", "kOS TV para Android TV"),
            new Claim("Jellyfin-Device", "SHIELD Android TV")
        ], "test"));

    // ---------------------------------------------------------------- the setting

    [Fact]
    public void TheCatalogIsAllByDefaultAndEachPersonChoosesIt()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);

        var settings = Json(controller.GetSettings());
        Assert.Equal(("all", true), (settings.GetProperty("Catalog").GetString(), settings.GetProperty("Learn").GetBoolean()));

        // Only Catalog: Learn as it was.
        settings = Json(controller.SetSettings(Body(new { Catalog = "home" })));
        Assert.Equal(("home", true), (settings.GetProperty("Catalog").GetString(), settings.GetProperty("Learn").GetBoolean()));
        // Only Learn: Catalog as it was.
        settings = Json(controller.SetSettings(Body(new { Learn = false })));
        Assert.Equal(("home", false), (settings.GetProperty("Catalog").GetString(), settings.GetProperty("Learn").GetBoolean()));
        // Both, in any case.
        settings = Json(controller.SetSettings(Body(new { learn = true, catalog = " ALL " })));
        Assert.Equal(("all", true), (settings.GetProperty("Catalog").GetString(), settings.GetProperty("Learn").GetBoolean()));

        object[] wrong =
        [
            new { },
            new { Catalog = "todo" },
            new { Catalog = 1 },
            new { Catalog = (string?)null },
            new { Learn = "no" },
            new { Learn = true, Catalog = "fuera" },
            new { Learn = 0, Catalog = "home" }
        ];
        foreach (var body in wrong)
        {
            Assert.IsType<BadRequestObjectResult>(controller.SetSettings(Body(body)));
        }

        Assert.IsType<BadRequestObjectResult>(controller.SetSettings(default));
        // Nothing changed by what was turned away.
        Assert.Equal("all", store.Catalog(userId));
        Assert.True(store.Learns(userId));

        // Per person, kept in their folder (a restart reads it), and kept when the listens go.
        var other = Guid.NewGuid();
        controller.SetSettings(Body(new { Catalog = "home" }));
        Assert.Equal("all", store.Catalog(other));
        var restarted = NewStore();
        Assert.Equal("home", restarted.Catalog(userId));
        Assert.Contains("\"catalog\":\"home\"", File.ReadAllText(Path.Combine(_root, userId.ToString("N"), "settings.json")));
        Assert.IsType<NoContentResult>(controller.DeleteListens());
        Assert.Equal("home", Json(controller.GetSettings()).GetProperty("Catalog").GetString());
        Assert.Equal("home", NewStore().Catalog(userId));

        // A settings file of before, without it: all.
        Directory.CreateDirectory(Path.Combine(_root, other.ToString("N")));
        File.WriteAllText(Path.Combine(_root, other.ToString("N"), "settings.json"), "{\"learn\":false}");
        var old = NewStore();
        Assert.Equal(("all", false), (old.Catalog(other), old.Learns(other)));

        // The user deleted: their setting goes with them.
        store.DeleteUser(userId);
        Assert.Equal("all", store.Catalog(userId));
        Assert.Equal("all", NewStore().Catalog(userId));
    }

    // ---------------------------------------------------------------- a song not at home heard

    [Fact]
    public void ASongNotAtHomeIsNotedAsAListenLinkedToTheOthers()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        OnTv(controller, userId);

        // A song at home just before.
        var home = Guid.NewGuid();
        var before = Listen(home, _now.AddSeconds(-200));
        store.Link(userId, before, _now);
        store.Append(userId, before);

        _now = _now.AddSeconds(205);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenBody(source: "DISCOVERY"))));
        var listen = store.Read(userId).Last();
        Assert.Equal(KostvMusicEvent.ListenType, listen.Type);
        Assert.Equal("stremfin:3135556", listen.Item);
        Assert.True(listen.IsStreamed);
        Assert.Equal(("Canción de fuera", "Disco de fuera"), (listen.Title, listen.AlbumName));
        Assert.Null(listen.Album);
        Assert.Null(listen.ArtistIds);
        Assert.Equal(["Fuera de Casa"], listen.Artists!);
        Assert.Equal(["Indie"], listen.Genres!);
        Assert.Equal((200, 200), (listen.Played, listen.Duration));
        Assert.Equal((KostvListenOutcome.Completed, KostvListenEnd.Natural), (listen.Outcome, listen.EndedBy));
        Assert.Equal(("discovery", false, "tv"), (listen.Source, listen.Shuffle, listen.Device));
        // It started what was heard of it ago, with the day and hour at home.
        Assert.Equal(_now.AddSeconds(-200), listen.At);
        Assert.Equal(11, listen.Hour);
        // In the session of the one before, after it.
        Assert.Equal((before.Session, home.ToString("N"), (string?)null), (listen.Session, listen.Prev, listen.PrevEndedBy));

        // Skipped early into the next one, by the same rule as those at home; then stopped.
        _now = _now.AddSeconds(12);
        controller.AddEvent(Body(StreamListenBody(deezerId: "42", played: 12.4, endedBy: "next", source: null, shuffle: null)));
        _now = _now.AddSeconds(150);
        controller.AddEvent(Body(StreamListenBody(deezerId: "42", played: 150, endedBy: "stop", source: "algo raro")));
        var events = store.Read(userId);
        var skipped = events[^2];
        Assert.Equal(("stremfin:42", 12, KostvListenOutcome.Skipped, KostvListenEnd.Next), (skipped.Item, skipped.Played, skipped.Outcome, skipped.EndedBy));
        Assert.Equal((listen.Session, "stremfin:3135556", KostvListenEnd.Natural), (skipped.Session, skipped.Prev, skipped.PrevEndedBy));
        Assert.Null(skipped.Source);
        Assert.Null(skipped.Shuffle);
        var stopped = events[^1];
        Assert.Equal((KostvListenOutcome.Stopped, "other"), (stopped.Outcome, stopped.Source));
        Assert.Equal(("stremfin:42", KostvListenEnd.Next), (stopped.Prev, stopped.PrevEndedBy));

        // Without a duration, only the 30 s tell; played past it is as long as it is.
        _now = _now.AddSeconds(600);
        controller.AddEvent(Body(StreamListenBody(deezerId: "7", played: 31, duration: null, endedBy: "closed", genre: null)));
        _now = _now.AddSeconds(600);
        controller.AddEvent(Body(StreamListenBody(deezerId: "8", played: 500, duration: 0, endedBy: "error")));
        _now = _now.AddSeconds(600);
        controller.AddEvent(Body(StreamListenBody(deezerId: "9", played: 260, duration: 240, endedBy: "natural")));
        events = store.Read(userId);
        Assert.Equal((KostvListenOutcome.Stopped, (int?)null, (List<string>?)null), (events[^3].Outcome, events[^3].Duration, events[^3].Genres));
        Assert.Equal((500, (int?)null), (events[^2].Played, events[^2].Duration));
        Assert.Equal((240, 240), (events[^1].Played, events[^1].Duration));

        // They are listens: counted in the settings.
        Assert.Equal(7, Json(controller.GetSettings()).GetProperty("Listens").GetInt32());
        // Without the app's names, the device isn't guessed.
        var plain = Controller(service, userId);
        plain.AddEvent(Body(StreamListenBody(deezerId: "10")));
        Assert.Null(store.Read(userId)[^1].Device);
    }

    [Fact]
    public void ASongNotAtHomeNotAsSaidIsTurnedAway()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        var name = new string('a', KostvMusicController.MaxEventNameLength + 1);

        object[] wrong =
        [
            new { Type = "stream_listen" },
            new { Type = "stream_listen", Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = 123, Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "12a", Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "-12", Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "", Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = new string('1', KostvMusicController.MaxDeezerIdLength + 1), Title = "T", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "  ", Artist = "A", Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = 5, Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Genre = name, Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Genre = 3, Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Source = 3, Played = 10, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = "10", EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = -1, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = KostvMusicController.MaxStreamSeconds + 1, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, Duration = -5, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, Duration = 1e9, EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, Duration = "200", EndedBy = "next" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10 },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, EndedBy = "skip" },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, EndedBy = 1 },
            new { Type = "stream_listen", DeezerId = "1", Title = "T", Artist = "A", Played = 10, EndedBy = "next", Shuffle = "true" }
        ];
        foreach (var body in wrong)
        {
            Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(body)));
        }

        Assert.Empty(store.Read(userId));

        // The limits themselves are fine, and what is optional may be left out or null.
        var longest = new string('a', KostvMusicController.MaxEventNameLength);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = new string('9', KostvMusicController.MaxDeezerIdLength), Title = longest, Artist = longest, Album = longest, Genre = longest, Played = 0, Duration = KostvMusicController.MaxStreamSeconds, EndedBy = "ERROR", Shuffle = (bool?)null })));
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "Stream_Listen", DeezerId = " 1 ", Title = "T", Artist = "A", Played = KostvMusicController.MaxStreamSeconds, EndedBy = "stop" })));
        // Kos TV: without an artist (or with it null) it counts all the same, only without one.
        _now = _now.AddMinutes(10);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "2", Title = "Sin artista", Played = 200, EndedBy = "natural" })));
        _now = _now.AddMinutes(10);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "3", Title = "Sin artista", Artist = (string?)null, Played = 200, EndedBy = "natural" })));
        var lone = store.Read(userId).Where(e => e.Item is "stremfin:2" or "stremfin:3").ToList();
        Assert.Equal(2, lone.Count);
        Assert.All(lone, e => Assert.Null(e.Artists));
        Assert.All(lone, e => Assert.Equal(KostvListenOutcome.Completed, e.Outcome));
        var events = store.Read(userId).Where(e => e.Item is not ("stremfin:2" or "stremfin:3")).ToList();
        Assert.Equal(2, events.Count);
        var plain = events.Single(e => e.Item == "stremfin:1");
        Assert.Equal((KostvListenEnd.Stop, (string?)null, (int?)null), (plain.EndedBy, plain.AlbumName, plain.Duration));
        Assert.Equal(KostvListenEnd.Error, events.Single(e => e.Item != "stremfin:1").EndedBy);
    }

    [Fact]
    public void ASongNotAtHomeIsNotNotedWithLearnOff()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        controller.SetSettings(Body(new { Learn = false }));

        Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenBody())));
        // Still checked: one not as said is a 400 also then.
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(StreamListenBody(deezerId: "no"))));
        Assert.Empty(store.Read(userId));
        Assert.False(Directory.Exists(Path.Combine(_root, userId.ToString("N"))) && Directory.EnumerateFiles(Path.Combine(_root, userId.ToString("N")), "*.jsonl").Any());

        // Back on: a session of its own, not linked to what was heard while off.
        controller.SetSettings(Body(new { Learn = true }));
        _now = _now.AddSeconds(10);
        controller.AddEvent(Body(StreamListenBody(deezerId: "5")));
        var listen = Assert.Single(store.Read(userId));
        Assert.Null(listen.Prev);

        // Deleted with the rest of the listens, and the taste worked out of them.
        Assert.Equal(1, store.Taste(userId).Listens);
        Assert.IsType<NoContentResult>(controller.DeleteListens());
        Assert.Empty(store.Read(userId));
        Assert.Equal(0, store.Taste(userId).Listens);
    }

    // ---------------------------------------------------------------- what it weighs in the taste

    [Fact]
    public void ASongNotAtHomeIsInTheTasteByItsDeezerIdBroughtUpToDateAsWorkedOutInFull()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        // Worked out first, so the listens after are added to it line by line.
        Assert.Equal(0, store.Taste(userId).Listens);

        for (var i = 0; i < 5; i++)
        {
            _now = _now.AddMinutes(4);
            controller.AddEvent(Body(StreamListenBody(played: i == 2 ? 10 : 200, endedBy: i == 2 ? "next" : "natural")));
        }

        // A later listen without a genre doesn't forget it.
        _now = _now.AddMinutes(4);
        controller.AddEvent(Body(StreamListenBody(genre: null)));
        _now = _now.AddMinutes(4);
        controller.AddEvent(Body(StreamListenBody(deezerId: "77", artist: "Otra de Fuera", genre: "Pop")));

        var incremental = store.Taste(userId);
        var full = store.RecomputeTaste(userId);
        foreach (var summary in new[] { incremental, full })
        {
            Assert.Equal(7, summary.Listens);
            var song = summary.Songs["stremfin:3135556"];
            Assert.Equal((6, 1), (song.Plays, song.Skips));
            Assert.Equal(["Fuera de Casa"], song.Artists!);
            Assert.Equal(["Indie"], song.Genres!);
            Assert.NotNull(song.LastHeard);
            Assert.Equal(["3135556", "77"], summary.Streamed().Select(s => s.DeezerId));
            // Never read from the library.
            Assert.Empty(summary.PlayedSongs());
            Assert.Empty(summary.OldListens(_now));
        }

        Assert.Equal(full.Songs["stremfin:3135556"].Long, incremental.Songs["stremfin:3135556"].Long, 9);
        Assert.Equal(full.Songs["stremfin:3135556"].OldCompleted, incremental.Songs["stremfin:3135556"].OldCompleted);

        // Kept as written: a restart reads it.
        store.FlushTastes();
        var read = NewStore().Taste(userId);
        Assert.Equal(["Fuera de Casa"], read.Songs["stremfin:3135556"].Artists!);
        Assert.Equal(["Indie"], read.Songs["stremfin:3135556"].Genres!);
    }

    [Fact]
    public void SongsNotAtHomeWeighTheirArtistsAndGenresInBothEnginesAndAreNeverInAMix()
    {
        var now = _now;
        // Half the taste learned (by 150 listens at home, of a song not read for it): what is at
        // home still counts for what the server knows.
        var summary = new KostvTasteSummary();
        var elsewhere = Guid.NewGuid();
        for (var i = 0; i < 150; i++)
        {
            summary.Apply(new KostvMusicEvent { Item = "stremfin:1", Artists = ["Fuera", "Invitada"], Genres = ["Indie"], Outcome = KostvListenOutcome.Completed, Played = 200, Duration = 200, EndedBy = KostvListenEnd.Natural }.Stamp(now.AddMinutes(-i * 5), Home));
            summary.Apply(Listen(elsewhere, now.AddMinutes(-i * 5 - 2)));
        }

        Assert.Equal((300, 150), (summary.Listens, summary.HomeListens));
        Assert.Equal(0.5, summary.Learned, 9);

        var tracks = WideLibrary(genres: 1, artists: 6);
        foreach (var profile in new[] { KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), now, null, summary), KostvMusicEngine.LearnedProfile(tracks, summary, now) })
        {
            Assert.Equal("Fuera", profile.Artists[0].Name);
            Assert.Contains(profile.Artists, a => a.Name == "Invitada" && a.Weight < profile.Artists[0].Weight);
            Assert.Equal("Indie", profile.Genres[0].Name);
            Assert.Contains("Fuera", KostvMusicEngine.Seeds(profile));
            Assert.Contains("Fuera", KostvMusicEngine.Seeds(profile, Guid.NewGuid(), "2026-W47"));
            // Only songs at home are scored, and so in the mixes.
            Assert.All(profile.Scores.Keys, id => Assert.Contains(tracks, t => t.Id == id));
            var mixes = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile);
            Assert.NotEmpty(mixes);
            Assert.DoesNotContain(mixes, m => m.Genre == "Indie");
            Assert.All(mixes.SelectMany(m => m.Items), id => Assert.Contains(tracks, t => t.Id == id));
        }

        var learned = KostvMusicEngine.LearnedProfile(tracks, summary, now);
        Assert.Equal("Fuera", learned.Background![0].Name);
        Assert.Equal("Fuera", learned.Recent![0].Name);

        // Without the summary, or with Learn off (an empty one), nothing of it.
        Assert.DoesNotContain(KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), now).Artists, a => a.Name == "Fuera");
        Assert.DoesNotContain(KostvMusicEngine.LearnedProfile(tracks, new KostvTasteSummary(), now).Artists, a => a.Name == "Fuera");

        // Out with «no me gusta» to it, or to its artist.
        var song = new KostvDislikes { Songs = [new KostvDislikedSong { DeezerId = "1", Name = "Una", Artist = "Fuera" }] };
        var artist = new KostvDislikes { Artists = [new KostvDislikedArtist { Id = Guid.NewGuid().ToString("N"), Name = "Invitada" }] };
        foreach (var dislikes in new[] { KostvDislikeSet.Of(song), KostvDislikeSet.Of(artist) })
        {
            Assert.DoesNotContain(KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), now, dislikes, summary).Artists, a => a.Name == "Fuera");
            Assert.DoesNotContain(KostvMusicEngine.LearnedProfile(tracks, summary, now, dislikes).Artists, a => a.Name == "Fuera");
        }

        // Skipped too often: out of the taste, as a song at home.
        var skipped = new KostvTasteSummary();
        for (var i = 0; i < 6; i++)
        {
            skipped.Apply(new KostvMusicEvent { Item = "stremfin:2", Artists = ["Saltada"], Outcome = KostvListenOutcome.Skipped, Played = 5, Duration = 200, EndedBy = KostvListenEnd.Next }.Stamp(now.AddMinutes(-i), Home));
        }

        Assert.DoesNotContain(KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), now, null, skipped).Artists, a => a.Name == "Saltada");
        Assert.DoesNotContain(KostvMusicEngine.LearnedProfile(tracks, skipped, now).Artists, a => a.Name == "Saltada");
    }

    [Fact]
    public async Task SongsNotAtHomeHeardAreInTheTasteRouteAndTheSeedsAndTheMixesStayAtHome()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var user = new User("ana", "auth", "reset");
        for (var i = 0; i < 300; i++)
        {
            _now = _now.AddMinutes(4);
            Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenBody(deezerId: (i % 20).ToString(System.Globalization.CultureInfo.InvariantCulture)))));
        }

        _now = _now.AddDays(1);
        var taste = Json(await controller.GetTaste());
        // Listens not at home don't count for how much of the taste at home is learned.
        Assert.Equal(0, taste.GetProperty("Learned").GetDouble());
        // Not at home: by name, without an id, after the 20 at home.
        var artists = taste.GetProperty("Artists").EnumerateArray().ToList();
        Assert.Equal(KostvMusicService.TasteArtists + 1, artists.Count);
        Assert.All(artists.Take(KostvMusicService.TasteArtists), a => Assert.Equal(JsonValueKind.String, a.GetProperty("Id").ValueKind));
        Assert.Equal("Fuera de Casa", artists[^1].GetProperty("Name").GetString());
        Assert.Equal(JsonValueKind.Null, artists[^1].GetProperty("Id").ValueKind);
        Assert.Equal("Fuera de Casa", taste.GetProperty("Recent").EnumerateArray().Last().GetProperty("Name").GetString());
        // Kos TV: their genre too, but after those of the songs at home (named as at home).
        var genres = taste.GetProperty("Genres").EnumerateArray().Select(g => g.GetProperty("Name").GetString()).ToList();
        Assert.Equal("Indie", genres[^1]);
        Assert.All(genres.SkipLast(1), g => Assert.StartsWith("Género ", g));

        // «Descubrimiento semanal» asks for songs like theirs, with either engine.
        Assert.Contains("Fuera de Casa", await service.SeedsAsync(userId, user));
        service.EngineModeOf = () => "nuevo";
        service.Forget(userId);
        Assert.Contains("Fuera de Casa", await service.SeedsAsync(userId, user));

        // The mixes are of songs at home only, and nothing fails for what isn't.
        foreach (var mode in new[] { "nuevo", "actual" })
        {
            service.EngineModeOf = () => mode;
            service.Forget(userId);
            var mixes = await service.MixesAsync(userId, user);
            Assert.All(mixes.SelectMany(m => m.Items), id => Assert.Contains(library.Items.OfType<Audio>(), s => s.Id == id));
            Assert.DoesNotContain(mixes, m => m.Genre == "Indie");
        }
    }

    [Fact]
    public async Task SongsNotAtHomeHeardAtATimeOfDayMakeItsMixOfTheirArtistsAtHome()
    {
        var library = MusicLibrary.Made();
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        var controller = Controller(service, userId);
        // Songs of an artist there is at home, from an album that isn't: five a morning, six mornings.
        for (var d = 1; d <= 6; d++)
        {
            for (var i = 0; i < 5; i++)
            {
                _now = new DateTimeOffset(2026, 11, 20 - d, 8, i * 4 + 4, 0, TimeSpan.Zero);
                controller.AddEvent(Body(StreamListenBody(deezerId: (100 + i).ToString(System.Globalization.CultureInfo.InvariantCulture), artist: "Artista 3-2", genre: "Género 3")));
            }
        }

        _now = new DateTimeOffset(2026, 11, 20, 9, 0, 0, TimeSpan.Zero);
        Assert.True(KostvMusicEngine.MomentReady(service.Store.Read(userId), KostvMusicEngine.Morning, _now, Home));
        foreach (var mode in new[] { "actual", "nuevo" })
        {
            service.EngineModeOf = () => mode;
            service.Forget(userId);
            var moment = await service.MomentAsync(userId, user);
            Assert.True(moment.Ready);
            var songs = moment.Items.Select(id => library.Items.OfType<Audio>().First(s => s.Id == id)).ToList();
            Assert.Contains(songs, s => s.Artists[0] == "Artista 3-2");
            Assert.True(songs.Count(s => s.Genres[0] == "Género 3") > songs.Count / 2);
        }

        // «No me gusta» to the artist: not even then.
        var artist = library.Items.OfType<MusicArtist>().First(a => a.Name == "Artista 3-2");
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString() }, Kind = "artist" }));
        var after = await service.MomentAsync(userId, user);
        Assert.DoesNotContain(after.Items, id => library.Items.OfType<Audio>().First(s => s.Id == id).Artists[0] == "Artista 3-2");
    }

    // ---------------------------------------------------------------- «no me gusta» to them

    [Fact]
    public void DislikesOfSongsNotAtHomeAreKeptByTheirDeezerIdAndCanBeUndone()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        service.Store.SetSettings(userId, false, null);
        var home = library.Items.OfType<Audio>().First();

        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", Songs = new[] { new { DeezerId = "55", Name = "De fuera", Artist = "Fuera de Casa" } } })));
        _now = _now.AddMinutes(1);
        // With songs at home at once, and one said again moves to the top, once.
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", Kind = "song", ItemIds = new[] { home.Id.ToString() }, Songs = new object[] { new { DeezerId = "66" }, new { DeezerId = " 55 ", Name = "De fuera", Artist = "Fuera de Casa" } } })));
        Assert.Empty(service.Store.Read(userId));

        var songs = Json(controller.GetDislikes()).GetProperty("Songs").EnumerateArray().ToList();
        Assert.Equal(3, songs.Count);
        Assert.Equal(new[] { "55", "66" }, songs.Where(s => s.GetProperty("Id").ValueKind == JsonValueKind.Null).Select(s => s.GetProperty("DeezerId").GetString()!).OrderBy(d => d, StringComparer.Ordinal).ToArray());
        var outside = songs.First(s => s.GetProperty("DeezerId").GetString() == "55");
        Assert.Equal(("De fuera", "Fuera de Casa"), (outside.GetProperty("Name").GetString(), outside.GetProperty("Artist").GetString()));
        Assert.Equal(JsonValueKind.Null, outside.GetProperty("ArtistId").ValueKind);
        Assert.Equal(_now.UtcDateTime, outside.GetProperty("At").GetDateTime());
        var athome = songs.Single(s => s.GetProperty("Id").ValueKind != JsonValueKind.Null);
        Assert.Equal((home.Id, JsonValueKind.Null), (athome.GetProperty("Id").GetGuid(), athome.GetProperty("DeezerId").ValueKind));

        // Kept in dislikes.json with their Deezer id and no id: a restart reads them, and deleting the listens leaves them.
        var stored = File.ReadAllText(Path.Combine(_root, userId.ToString("N"), "dislikes.json"));
        Assert.Contains("\"deezerId\":\"55\"", stored);
        Assert.Equal(3, NewStore().DislikesOf(userId).Songs.Count);
        service.Store.SetSettings(userId, true, null);
        controller.DeleteListens();
        Assert.Equal(3, Json(controller.GetDislikes()).GetProperty("Songs").GetArrayLength());
        Assert.True(service.DislikeSetOf(userId).BlocksStreamed("66", null));
        Assert.False(service.DislikeSetOf(userId).BlocksStreamed("12", ["Fuera de Casa", "Otra"]));

        // Undone by stremfin:<DeezerId>; one that wasn't there is fine; one not a Deezer id, a 400.
        Assert.IsType<NoContentResult>(controller.RemoveDislike("stremfin:55"));
        Assert.IsType<NoContentResult>(controller.RemoveDislike("stremfin:99"));
        Assert.IsType<BadRequestObjectResult>(controller.RemoveDislike("stremfin:abc"));
        Assert.IsType<BadRequestObjectResult>(controller.RemoveDislike("stremfin:"));
        Assert.IsType<BadRequestObjectResult>(controller.RemoveDislike("55"));
        songs = Json(controller.GetDislikes()).GetProperty("Songs").EnumerateArray().ToList();
        Assert.Equal(2, songs.Count);
        Assert.DoesNotContain(songs, s => s.GetProperty("DeezerId").GetString() == "55");
        Assert.False(service.DislikeSetOf(userId).BlocksStreamed("55", null));
        // The one at home is undone by its id, as ever.
        Assert.IsType<NoContentResult>(controller.RemoveDislike(home.Id.ToString()));
        Assert.Equal("66", Assert.Single(service.Store.DislikesOf(userId).Songs).DeezerId);
        Assert.IsType<NoContentResult>(controller.ClearDislikes());
        Assert.Empty(service.Store.DislikesOf(userId).Songs);

        // The user deleted: their list goes too.
        controller.AddEvent(Body(new { Type = "dislike", Songs = new[] { new { DeezerId = "1" } } }));
        service.Store.DeleteUser(userId);
        Assert.Empty(service.Store.DislikesOf(userId).Songs);
        Assert.False(Directory.Exists(Path.Combine(_root, userId.ToString("N"))));
    }

    [Fact]
    public void DislikesOfSongsNotAtHomeNotAsSaidAreTurnedAway()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        var name = new string('a', KostvMusicController.MaxEventNameLength + 1);

        object[] wrong =
        [
            new { Type = "dislike", Songs = Array.Empty<object>() },
            new { Type = "dislike", Songs = "55" },
            new { Type = "dislike", Songs = new[] { "55" } },
            new { Type = "dislike", Songs = new[] { new { DeezerId = "abc" } } },
            new { Type = "dislike", Songs = new[] { new { DeezerId = 55 } } },
            new { Type = "dislike", Songs = new[] { new { Name = "Sin id" } } },
            new { Type = "dislike", Songs = new[] { new { DeezerId = new string('1', KostvMusicController.MaxDeezerIdLength + 1) } } },
            new { Type = "dislike", Songs = new[] { new { DeezerId = "1", Name = name } } },
            new { Type = "dislike", Songs = new[] { new { DeezerId = "1", Artist = 3 } } },
            new { Type = "dislike", Songs = Enumerable.Range(0, KostvMusicController.MaxEventItems + 1).Select(i => new { DeezerId = i.ToString(System.Globalization.CultureInfo.InvariantCulture) }) },
            new { Type = "dislike", Kind = "artist", Songs = new[] { new { DeezerId = "1" } } },
            // With Songs, ItemIds still as ever.
            new { Type = "dislike", ItemIds = new[] { "no es un id" }, Songs = new[] { new { DeezerId = "1" } } },
            new { Type = "dislike" }
        ];
        foreach (var body in wrong)
        {
            Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(body)));
        }

        Assert.Empty(store.DislikesOf(userId).Songs);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = (string[]?)null, Songs = Enumerable.Range(1, KostvMusicController.MaxEventItems).Select(i => new { DeezerId = i.ToString(System.Globalization.CultureInfo.InvariantCulture) }) })));
        Assert.Equal(KostvMusicController.MaxEventItems, store.DislikesOf(userId).Songs.Count);
    }

    [Fact]
    public void ADislikedSongNotAtHomeWeighsItsArtistDownByName()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var artist = "Artista 0-3";
        Assert.Equal(1, service.DislikeSetOf(userId).ArtistFactor(artist));

        controller.AddEvent(Body(new { Type = "dislike", Songs = new[] { new { DeezerId = "1", Name = "Una", Artist = artist } } }));
        Assert.Equal(KostvTasteWeights.DislikedSongsFactor(1), service.DislikeSetOf(userId).ArtistFactor(artist));
        // Counted with those at home of the same artist: three of them weigh it down much.
        var home = library.Items.OfType<Audio>().First(s => s.Artists[0] == artist);
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { home.Id.ToString() }, Songs = new[] { new { DeezerId = "2", Name = "Otra", Artist = " artista 0-3 " } } }));
        var dislikes = service.DislikeSetOf(userId);
        Assert.Equal(KostvTasteWeights.DislikedSongsFactor(3), dislikes.ArtistFactor(artist));
        // The song itself is out; the artist not.
        Assert.True(dislikes.BlocksStreamed("1", [artist]));
        Assert.False(dislikes.BlocksStreamed("3", [artist]));
        Assert.False(dislikes.BlocksArtist(artist));

        // In the taste, the artist's songs weigh less.
        var tracks = library.Items.OfType<Audio>().Select(s => new KostvMusicTrack(s.Id, s.Artists, s.Genres, library.Data[s.Id].PlayCount, library.Data[s.Id].LastPlayedDate)).ToList();
        var before = KostvMusicEngine.LearnedProfile(tracks, null, _now).Artists.First(a => a.Name == artist).Weight;
        var after = KostvMusicEngine.LearnedProfile(tracks, null, _now, dislikes).Artists.First(a => a.Name == artist).Weight;
        // (and the song at home with it is out, too)
        Assert.InRange(after, 0.01, before * KostvTasteWeights.DislikedSongsFactor(3) + 1e-9);
    }
}
