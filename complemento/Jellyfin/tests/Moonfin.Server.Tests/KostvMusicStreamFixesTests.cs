using System.Text.Json;
using System.Text.RegularExpressions;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: what «Toda la música» needed fixing in the plugin once looked over: the taste's artists
/// at home first, the listens not at home not taking the weight off what the server knows, long
/// names cut, a listen linked only once written, a pace no app may go past, «no me gusta» kept as
/// stored and what a person may not see.
/// </summary>
public sealed partial class KostvMusicTests
{
    private static object StreamListenOf(string deezerId, string artist) =>
        new { Type = "stream_listen", DeezerId = deezerId, Title = "Canción de fuera", Artist = artist, Played = 200, Duration = 200, EndedBy = "natural" };

    // ---------------------------------------------------------------- the taste: those at home first

    [Fact]
    public async Task TheTasteGivesItsArtistsAtHomeFirstAndThoseNotAtHomeAfter()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        // Thirty artists not at home, each heard much more than any at home.
        for (var a = 0; a < 30; a++)
        {
            for (var i = 0; i < 15; i++)
            {
                _now = _now.AddSeconds(10);
                controller.AddEvent(Body(StreamListenOf((a * 100 + i).ToString(System.Globalization.CultureInfo.InvariantCulture), $"Fuera {a}")));
            }
        }

        _now = _now.AddDays(1);
        var taste = Json(await controller.GetTaste());
        foreach (var list in new[] { "Artists", "Recent" })
        {
            var artists = taste.GetProperty(list).EnumerateArray().ToList();
            // The 20 at home, with their ids, as an app that leaves out what has none needs them...
            var home = artists.Take(KostvMusicService.TasteArtists).ToList();
            Assert.All(home, a => Assert.Equal(library.Items.OfType<MusicArtist>().First(x => x.Name == a.GetProperty("Name").GetString()).Id, a.GetProperty("Id").GetGuid()));
            // ...and then 20 not at home, by name.
            var away = artists.Skip(KostvMusicService.TasteArtists).ToList();
            Assert.Equal(KostvMusicService.TasteArtists, away.Count);
            Assert.All(away, a => Assert.Equal(JsonValueKind.Null, a.GetProperty("Id").ValueKind));
            Assert.All(away, a => Assert.StartsWith("Fuera ", a.GetProperty("Name").GetString()));
            // Even weighing more than those at home.
            Assert.True(away[0].GetProperty("Score").GetDouble() > home[^1].GetProperty("Score").GetDouble());
        }

        // An artist not at home with «no me gusta» (by a song of theirs) is not left out, but
        // one at home is, and the next at home takes its place.
        var top = taste.GetProperty("Artists")[0];
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { top.GetProperty("Id").GetGuid() }, Kind = "artist" }));
        var names = Json(await controller.GetTaste()).GetProperty("Artists").EnumerateArray().ToList();
        Assert.DoesNotContain(names, a => a.GetProperty("Name").GetString() == top.GetProperty("Name").GetString());
        Assert.All(names.Take(KostvMusicService.TasteArtists), a => Assert.Equal(JsonValueKind.String, a.GetProperty("Id").ValueKind));
    }

    // ---------------------------------------------------------------- the taste: what is learned at home

    [Fact]
    public void ListensNotAtHomeDontTakeTheWeightOffWhatTheServerKnows()
    {
        var tracks = WideLibrary(genres: 1, artists: 6);
        var away = new KostvTasteSummary();
        for (var i = 0; i < 400; i++)
        {
            away.Apply(new KostvMusicEvent { Item = "stremfin:" + (i % 40), Artists = ["Fuera"], Outcome = KostvListenOutcome.Completed, Played = 200, Duration = 200, EndedBy = KostvListenEnd.Natural }.Stamp(_now.AddMinutes(-i * 4), Home));
        }

        // Counted, but not as learned of what is at home.
        Assert.Equal((400, 0, 0.0), (away.Listens, away.HomeListens, away.Learned));
        var none = KostvMusicEngine.LearnedProfile(tracks, new KostvTasteSummary(), _now);
        var withAway = KostvMusicEngine.LearnedProfile(tracks, away, _now);
        // The songs at home score as with nothing learned: all of it the server's plays.
        Assert.Equal(none.Scores.Count, withAway.Scores.Count);
        Assert.All(none.Scores, s => Assert.Equal(s.Value, withAway.Scores[s.Key], 9));
        // And the artist not at home still counts in the taste.
        Assert.Contains(withAway.Artists, a => a.Name == "Fuera");

        // Those at home do, as ever, also mixed with those not at home.
        var home = away.Copy();
        for (var i = 0; i < 60; i++)
        {
            home.Apply(Listen(tracks[0].Id, _now.AddMinutes(-i * 4 - 1)));
        }

        Assert.Equal((460, 60), (home.Listens, home.HomeListens));
        Assert.Equal(0.2, home.Learned, 9);
        Assert.Equal(0.2, KostvMusicEngine.Summarize(Enumerable.Range(0, 60).Select(i => Listen(tracks[0].Id, _now.AddMinutes(-i))).ToList(), _now).Learned, 9);
    }

    [Fact]
    public void ATasteOfBeforeTheListensAtHomeWereCountedApartIsWorkedOutAgain()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        store.Append(user, Listen(Guid.NewGuid(), _now));
        store.Append(user, Listen(Guid.NewGuid(), _now.AddMinutes(4)));
        var streamed = new KostvMusicEvent { Item = "stremfin:5", Artists = ["Fuera"], Outcome = KostvListenOutcome.Completed, Played = 200, Duration = 200 }.Stamp(_now.AddMinutes(8), Home);
        store.Append(user, streamed);
        Assert.Equal((3, 2), (store.Taste(user).Listens, store.Taste(user).HomeListens));
        store.FlushTastes();

        // As a summary of before wrote it: no count of those at home.
        var file = Path.Combine(_root, user.ToString("N"), "taste.json");
        var text = File.ReadAllText(file);
        Assert.Contains($"\"v\":{KostvTasteSummary.CurrentVersion}", text);
        text = Regex.Replace(text, "\"v\":\\d+", "\"v\":2");
        text = Regex.Replace(text, ",?\"home\":\\d+", string.Empty);
        File.WriteAllText(file, text);
        File.Delete(file + ".bak");

        var taste = NewStore().Taste(user);
        Assert.Equal((KostvTasteSummary.CurrentVersion, 3, 2), (taste.Version, taste.Listens, taste.HomeListens));
    }

    // ---------------------------------------------------------------- long names

    [Fact]
    public void ALongTitleArtistOrAlbumOfASongNotAtHomeIsCutNotTurnedAway()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        var max = KostvMusicController.MaxEventNameLength;
        // A character outside the basic plane right at the end isn't cut in half.
        var title = new string('a', max - 1) + "\U0001F3B5" + "b";
        var artist = new string('b', max + 50);
        var album = "Symphony No. 9 " + new string('c', max * 3);

        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "1", Title = title, Artist = artist, Album = album, Played = 200, Duration = 200, EndedBy = "natural" })));
        var listen = Assert.Single(store.Read(userId));
        Assert.Equal(new string('a', max - 1), listen.Title);
        Assert.Equal([new string('b', max)], listen.Artists!);
        Assert.Equal(album[..max], listen.AlbumName);

        // A Genre or a Source too long, or a text not a text, is still turned away.
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "2", Title = "T", Artist = "A", Genre = new string('g', max + 1), Played = 200, EndedBy = "natural" })));
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "2", Title = 5, Artist = "A", Played = 200, EndedBy = "natural" })));
        // And so is a long name of a request (there, as ever).
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(new { Type = "request", Album = new string('d', max + 1) })));
        Assert.Single(store.Read(userId));
    }

    // ---------------------------------------------------------------- linked once written

    [Fact]
    public void AListenNotAtHomeNotWrittenIsNotTheOneBeforeTheNext()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var controller = Controller(service, userId);
        controller.AddEvent(Body(StreamListenOf("1", "Fuera")));
        var first = Assert.Single(store.Read(userId));

        // On its way as Learn was turned off: not written, and so not linked to.
        _now = _now.AddSeconds(200);
        store.SetSettings(userId, false, null);
        Assert.False(store.LinkAndAppend(userId, new KostvMusicEvent { Item = "stremfin:2", Outcome = KostvListenOutcome.Completed, Played = 200 }.Stamp(_now.AddSeconds(-200), Home), _now));
        store.SetSettings(userId, true, null);
        Assert.Single(store.Read(userId));

        // The next is linked to the one written before it.
        _now = _now.AddSeconds(205);
        controller.AddEvent(Body(StreamListenOf("3", "Fuera")));
        var next = store.Read(userId)[^1];
        Assert.Equal(("stremfin:1", first.Session), (next.Prev, next.Session));

        // Written: linked to, in the same session.
        _now = _now.AddSeconds(205);
        Assert.True(store.LinkAndAppend(userId, new KostvMusicEvent { Item = "stremfin:4", Outcome = KostvListenOutcome.Completed, Played = 200 }.Stamp(_now.AddSeconds(-200), Home), _now));
        var last = store.Read(userId)[^1];
        Assert.Equal(("stremfin:3", first.Session), (last.Prev, last.Session));
    }

    // ---------------------------------------------------------------- the pace

    [Fact]
    public void NoAppMayNoteListensNotAtHomeFasterThanAnyoneListens()
    {
        var store = NewStore();
        var service = new KostvMusicService(null!, null!, store, NullLogger<KostvMusicService>.Instance);
        var userId = Guid.NewGuid();
        var other = Guid.NewGuid();
        var controller = Controller(service, userId);

        // Skipping a song a second for a minute is fine...
        for (var i = 0; i < KostvMusicStore.MaxStreamListensPerMinute; i++)
        {
            Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenOf(i.ToString(System.Globalization.CultureInfo.InvariantCulture), "Fuera"))));
        }

        Assert.Equal(KostvMusicStore.MaxStreamListensPerMinute, store.Read(userId).Count);
        // ...past it, let go of (still a 204), and only for that person.
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenOf("999", "Fuera"))));
        Assert.Equal(KostvMusicStore.MaxStreamListensPerMinute, store.Read(userId).Count);
        Assert.True(store.TakeStreamListen(other));
        // Not as said is still a 400.
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(StreamListenOf("no", "Fuera"))));

        // A minute after, again.
        _now = _now.AddMinutes(1);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(StreamListenOf("1000", "Fuera"))));
        Assert.Equal(KostvMusicStore.MaxStreamListensPerMinute + 1, store.Read(userId).Count);

        // And no more than the day's.
        var taken = 1 + KostvMusicStore.MaxStreamListensPerMinute;
        while (taken < KostvMusicStore.MaxStreamListensPerDay)
        {
            _now = _now.AddMinutes(1);
            for (var i = 0; i < KostvMusicStore.MaxStreamListensPerMinute && taken < KostvMusicStore.MaxStreamListensPerDay; i++, taken++)
            {
                Assert.True(store.TakeStreamListen(userId));
            }
        }

        _now = _now.AddMinutes(1);
        Assert.False(store.TakeStreamListen(userId));
        _now = _now.AddDays(1);
        Assert.True(store.TakeStreamListen(userId));
    }

    [Fact]
    public void NormalListeningIsFarFromThePace()
    {
        // The shortest songs heard one after another for a whole day: under a minute's and a day's.
        var store = NewStore();
        var userId = Guid.NewGuid();
        for (var i = 0; i < 24 * 60 * 60 / 30; i++)
        {
            _now = _now.AddSeconds(30);
            Assert.True(store.TakeStreamListen(userId));
        }
    }

    // ---------------------------------------------------------------- «no me gusta» as stored

    [Fact]
    public void ADislikeNotStoredIsNotUsedEither()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var songs = library.Items.OfType<Audio>().Take(2).ToList();
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { songs[0].Id.ToString() } })));

        // The disk fails: where it is written first there is a folder.
        var tmp = Path.Combine(_root, userId.ToString("N"), "dislikes.json.tmp");
        Directory.CreateDirectory(tmp);
        var result = controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { songs[1].Id.ToString() }, Songs = new[] { new { DeezerId = "7" } } }));
        Assert.Equal(500, Assert.IsAssignableFrom<ObjectResult>(result).StatusCode);
        // Not added, here either: the mixes don't leave it out.
        Assert.Equal([songs[0].Id.ToString("N")], service.Store.DislikesOf(userId).Songs.Select(s => s.Id));
        Assert.False(KostvMusicService.Blocks(service.DislikeSetOf(userId), songs[1]));
        Assert.False(service.DislikeSetOf(userId).BlocksStreamed("7", null));

        // Nor taken off: a 500, and it stays out (here and after a restart).
        result = controller.RemoveDislike(songs[0].Id.ToString());
        Assert.Equal(500, Assert.IsAssignableFrom<ObjectResult>(result).StatusCode);
        Assert.True(KostvMusicService.Blocks(service.DislikeSetOf(userId), songs[0]));
        Assert.Equal(KostvDislikeRemoval.NotStored, service.Store.RemoveDislike(userId, songs[0].Id));
        // One that wasn't there is still a 204.
        Assert.IsType<NoContentResult>(controller.RemoveDislike(Guid.NewGuid().ToString()));

        // The disk back: as ever.
        Directory.Delete(tmp);
        Assert.IsType<NoContentResult>(controller.RemoveDislike(songs[0].Id.ToString()));
        Assert.Empty(service.Store.DislikesOf(userId).Songs);
        Assert.Empty(NewStore().DislikesOf(userId).Songs);
        Assert.Equal(KostvDislikeRemoval.NotThere, service.Store.RemoveDislike(userId, songs[0].Id));
    }

    [Fact]
    public void EmptyingTheListEmptiesItAllAlsoWhatAnOldAppDoesntShow()
    {
        // 1.18.0 doesn't show the songs not at home in its list, but «Borrar todo» there means the
        // list empty everywhere: on every device, the same list.
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { library.Items.OfType<Audio>().First().Id.ToString() }, Songs = new[] { new { DeezerId = "7", Name = "De fuera" } } }));
        Assert.Equal(2, service.Store.DislikesOf(userId).Songs.Count);

        Assert.IsType<NoContentResult>(controller.ClearDislikes());
        var list = Json(controller.GetDislikes());
        Assert.Equal(0, list.GetProperty("Songs").GetArrayLength());
        Assert.False(service.DislikeSetOf(userId).BlocksStreamed("7", null));
    }

    // ---------------------------------------------------------------- what a person may not see

    [Fact]
    public void ADislikeOfASongThePersonMayNotSeeIsLetGoOfAndItsNameNotGiven()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var songs = library.Items.OfType<Audio>().Take(2).ToList();
        var hidden = songs[1];
        service.Sees = (item, _) => item.Id != hidden.Id;

        // A song they may not see (by its id, sent by hand): let go of, a 204 as for one not at home.
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { songs[0].Id.ToString(), hidden.Id.ToString() } })));
        var list = Json(controller.GetDislikes());
        Assert.Equal([songs[0].Id], list.GetProperty("Songs").EnumerateArray().Select(s => s.GetProperty("Id").GetGuid()));
        // An artist, as ever.
        var artist = library.Items.OfType<MusicArtist>().First();
        service.Sees = (_, _) => false;
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString() }, Kind = "artist" })));
        Assert.Equal(1, Json(controller.GetDislikes()).GetProperty("Artists").GetArrayLength());

        // One kept while it could be seen, and no longer: the name kept, not the one at home now.
        service.Sees = (_, _) => true;
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { hidden.Id.ToString() } }));
        hidden.Name = "Nombre de ahora";
        service.Sees = (item, _) => item.Id != hidden.Id;
        var shown = Json(controller.GetDislikes()).GetProperty("Songs").EnumerateArray().First(s => s.GetProperty("Id").GetGuid() == hidden.Id);
        Assert.Equal("Canción 1", shown.GetProperty("Name").GetString());
        service.Sees = (_, _) => true;
        shown = Json(controller.GetDislikes()).GetProperty("Songs").EnumerateArray().First(s => s.GetProperty("Id").GetGuid() == hidden.Id);
        Assert.Equal("Nombre de ahora", shown.GetProperty("Name").GetString());
    }

    [Fact]
    public void TheServersRulesDecideWhatAPersonSees()
    {
        // Not told otherwise, the server's own check: for what isn't one of its users, nothing.
        var service = new KostvMusicService(null!, null!, NewStore(), NullLogger<KostvMusicService>.Instance);
        Assert.False(service.Sees(new Audio { Id = Guid.NewGuid() }, new object()));
    }
}
