using System.Text.Json;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: what the second look at the music of the plugin found, kept from coming back: the
/// taste's artists a person may not see, looked up only as far as needed, «no me gusta» emptied
/// only once stored, a song not at home without its artist, the engines compared for the settings
/// page and the daily round reading only this month.
/// </summary>
public sealed partial class KostvMusicTests
{
    // ---------------------------------------------------------------- the taste's artists

    [Fact]
    public async Task TheTasteGivesAnArtistThePersonMayNotSeeWithoutItsId()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var hidden = library.Items.OfType<MusicArtist>().First(a => a.Name == "Artista 0-0");
        service.Sees = (item, _) => item.Id != hidden.Id;

        var taste = Json(await controller.GetTaste());
        foreach (var list in new[] { "Artists", "Recent" })
        {
            var artists = taste.GetProperty(list).EnumerateArray().ToList();
            // Never its id...
            Assert.DoesNotContain(artists, a => a.GetProperty("Id").ValueKind == JsonValueKind.String && a.GetProperty("Id").GetGuid() == hidden.Id);
            // ...but by name, as one not at home, after those at home.
            var shown = Assert.Single(artists, a => a.GetProperty("Name").GetString() == hidden.Name);
            Assert.Equal(JsonValueKind.Null, shown.GetProperty("Id").ValueKind);
            var home = artists.TakeWhile(a => a.GetProperty("Id").ValueKind == JsonValueKind.String).Count();
            Assert.True(artists.IndexOf(shown) >= home);
        }
    }

    [Fact]
    public async Task TheTasteLooksUpItsArtistsOnlyUntilThoseAtHomeAreFound()
    {
        var userId = Guid.NewGuid();
        // 160 artists heard at home, none away.
        var (service, controller, library) = Routes(userId, MusicLibrary.Made(genres: 4, artists: 40, played: 2, unplayed: 0));
        var before = library.Queries;
        var taste = Json(await controller.GetTaste());
        var lookedUp = library.Queries - before;
        Assert.All(new[] { "Artists", "Recent" }, list =>
        {
            var artists = taste.GetProperty(list).EnumerateArray().ToList();
            Assert.Equal(KostvMusicService.TasteArtists, artists.Count);
            Assert.All(artists, a => Assert.Equal(JsonValueKind.String, a.GetProperty("Id").ValueKind));
        });
        // Not the 100 names looking for some not at home that never come (each name is a query).
        Assert.True(lookedUp < KostvMusicService.TasteLookedUp, $"{lookedUp} queries");

        // With many artists out by their id, a batch is not made as long as all of them.
        var many = Enumerable.Range(0, 500).Select(i => new KostvDislikedArtist { Id = Guid.NewGuid().ToString("N"), Name = $"Otro {i}", At = _now }).ToList();
        Assert.True(service.Store.AddDislikes(userId, [], many));
        service.Forget(userId);
        before = library.Queries;
        await controller.GetTaste();
        Assert.True(library.Queries - before < KostvMusicService.TasteLookedUp, $"{library.Queries - before} queries");
    }

    // ---------------------------------------------------------------- «no me gusta» emptied

    [Fact]
    public void DislikesEmptiedOnlyOnceStoredAndNotBroughtBackByTheCopyOfBefore()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var song = library.Items.OfType<Audio>().First();
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { song.Id.ToString() } })));
        _now = _now.AddMinutes(1);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { library.Items.OfType<Audio>().Skip(1).First().Id.ToString() } })));

        // Where the empty list is written first there is a folder: it can't be stored.
        var path = Path.Combine(_root, userId.ToString("N"), "dislikes.json");
        Directory.CreateDirectory(path + ".tmp");
        Assert.Equal(500, Assert.IsAssignableFrom<ObjectResult>(controller.ClearDislikes()).StatusCode);
        Assert.Equal(2, service.Store.DislikesOf(userId).Songs.Count);
        Assert.Equal(2, NewStore().DislikesOf(userId).Songs.Count);

        Directory.Delete(path + ".tmp");
        Assert.IsType<NoContentResult>(controller.ClearDislikes());
        Assert.Empty(service.Store.DislikesOf(userId).Songs);
        Assert.Empty(NewStore().DislikesOf(userId).Songs);
        // Even with the file broken, the list of before doesn't come back.
        File.WriteAllText(path, "{roto");
        Assert.Empty(NewStore().DislikesOf(userId).Songs);
    }

    // ---------------------------------------------------------------- a song not at home without its artist

    [Fact]
    public void ASongNotAtHomeWithoutItsArtistCountsButNotForAnArtist()
    {
        var userId = Guid.NewGuid();
        var (service, controller, _) = Routes(userId);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "77", Title = "Sin artista", Genre = "Indie", Played = 200, Duration = 200, EndedBy = "natural" })));
        var taste = service.Store.RecomputeTaste(userId);
        Assert.Equal(1, taste.Listens);
        Assert.NotNull(taste.Songs.GetValueOrDefault(KostvMusicEvent.StreamedItem("77")));
        Assert.Empty(taste.Streamed());
        // Still checked as the rest: no title, a 400.
        Assert.IsType<BadRequestObjectResult>(controller.AddEvent(Body(new { Type = "stream_listen", DeezerId = "78", Played = 200, EndedBy = "natural" })));
    }

    // ---------------------------------------------------------------- the engines compared

    [Fact]
    public void TheEnginesComparedAreSummedUpByPerson()
    {
        Assert.Equal(new KostvMusicStore.KostvComparisonSum(0, null, null, 0, 0), KostvMusicStore.Sum([]));
        var sum = KostvMusicStore.Sum(
        [
            new KostvMusicStore.KostvComparison { Day = "2026-11-19", HitsOld = 3, HitsNew = 5 },
            new KostvMusicStore.KostvComparison { Day = "2026-11-17", HitsOld = 2, HitsNew = 1 },
            // A day told twice counts once, the last.
            new KostvMusicStore.KostvComparison { Day = "2026-11-19", HitsOld = 4, HitsNew = 6 },
            new KostvMusicStore.KostvComparison { Day = string.Empty, HitsOld = 9, HitsNew = 9 }
        ]);
        Assert.Equal(new KostvMusicStore.KostvComparisonSum(2, "2026-11-17", "2026-11-19", 6, 7), sum);
    }

    // ---------------------------------------------------------------- the daily round reads only this month

    private static string TasteJson(KostvTasteSummary summary) => JsonSerializer.Serialize(summary);

    // A day of everything: a listen, the mixes and the moment shown (of songs heard and not), now
    // and then a heart, a list, an album asked for and a song not at home.
    private static void ADayOf(KostvMusicStore store, Guid user, IReadOnlyList<Guid> songs, DateTimeOffset at, Random random)
    {
        string[] outcomes = [KostvListenOutcome.Completed, KostvListenOutcome.Skipped, KostvListenOutcome.Stopped];
        store.Append(user, Listen(songs[random.Next(songs.Count)], at, outcomes[random.Next(3)]));
        var shown = Enumerable.Range(0, 6).Select(_ => random.Next(3) == 0 ? Guid.NewGuid() : songs[random.Next(songs.Count)]).Select(g => g.ToString("N")).ToList();
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MixesSurface, Mixes = [new KostvShownMix { Id = "daily-1", Items = shown }] }.Stamp(at.AddMinutes(1), Home));
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MomentSurface, Slot = "morning", Items = shown.Take(3).ToList() }.Stamp(at.AddMinutes(2), Home));
        var n = random.Next(10);
        if (n == 0)
        {
            store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.HeartType, Item = songs[random.Next(songs.Count)].ToString("N"), Favorite = random.Next(2) == 0 }.Stamp(at.AddMinutes(3), Home));
        }
        else if (n == 1)
        {
            store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.PlaylistAddType, Items = [songs[random.Next(songs.Count)].ToString("N")] }.Stamp(at.AddMinutes(3), Home));
        }
        else if (n == 2)
        {
            store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.RequestType, ArtistName = "Pedido " + random.Next(4) }.Stamp(at.AddMinutes(3), Home));
        }
        else if (n < 6)
        {
            store.Append(user, new KostvMusicEvent { Item = KostvMusicEvent.StreamedItem(random.Next(20).ToString(System.Globalization.CultureInfo.InvariantCulture)), Outcome = outcomes[random.Next(3)], Played = 120, Duration = 200, Artists = ["Fuera " + random.Next(5)], Genres = ["Indie"] }.Stamp(at.AddMinutes(3), Home));
        }
    }

    [Fact]
    public void TheDailyRoundReadsOnlyThisMonthAndWorksOutTheSameTaste()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var random = new Random(7);
        var songs = Enumerable.Range(0, 40).Select(_ => Guid.NewGuid()).ToList();
        // Five months and a bit, a day at a time (also songs shown more than 12 weeks ago).
        var start = _now.AddDays(-160);
        for (var day = 0; day < 160; day++)
        {
            ADayOf(store, user, songs, start.AddDays(day).AddHours(random.Next(10)), random);
        }

        var months = Directory.GetFiles(Path.Combine(_root, user.ToString("N")), "*.jsonl").Length;
        Assert.True(months >= 6);
        KostvTasteSummary Expected() => KostvMusicEngine.Summarize(store.Read(user), _now);
        int ReadFor(Func<KostvTasteSummary> recompute, out KostvTasteSummary summary)
        {
            var before = store.MonthsRead;
            summary = recompute();
            return store.MonthsRead - before;
        }

        // The first time, all of it.
        Assert.Equal(months, ReadFor(() => store.RecomputeTaste(user), out var first));
        Assert.Equal(TasteJson(Expected()), TasteJson(first));

        // The next days, only this month's file, and the same as from all the lines.
        for (var day = 0; day < 3; day++)
        {
            _now = _now.AddDays(1);
            ADayOf(store, user, songs, _now.AddHours(-1), random);
            Assert.Equal(1, ReadFor(() => store.RecomputeTaste(user), out var daily));
            Assert.Equal(TasteJson(Expected()), TasteJson(daily));
        }

        // Into the next month: the one just gone is added, and this one read.
        var local = TimeZoneInfo.ConvertTime(_now, Home);
        _now = new DateTimeOffset(local.Year, local.Month, 1, 12, 0, 0, local.Offset).AddMonths(1).AddDays(2);
        ADayOf(store, user, songs, _now.AddHours(-1), random);
        Assert.Equal(2, ReadFor(() => store.RecomputeTaste(user), out var nextMonth));
        Assert.Equal(TasteJson(Expected()), TasteJson(nextMonth));
        Assert.Equal(1, ReadFor(() => store.RecomputeTaste(user), out _));

        // A line added to a month before (a song not at home heard then): all of it read again.
        store.Append(user, Listen(songs[0], _now.AddDays(-40)));
        Assert.True(ReadFor(() => store.RecomputeTaste(user), out var late) > 2);
        Assert.Equal(TasteJson(Expected()), TasteJson(late));
        Assert.Equal(1, ReadFor(() => store.RecomputeTaste(user), out _));

        // A month gone (trimmed, or by hand): the same.
        File.Delete(Directory.GetFiles(Path.Combine(_root, user.ToString("N")), "*.jsonl").Order(StringComparer.Ordinal).First());
        Assert.True(ReadFor(() => store.RecomputeTaste(user), out var trimmed) > 1);
        Assert.Equal(TasteJson(Expected()), TasteJson(trimmed));

        // A line of a month before dated after one of this month (written by hand): all the lines
        // at once, in their order, as before.
        var lastMonth = TimeZoneInfo.ConvertTime(_now, Home).AddMonths(-1);
        var lastFile = Path.Combine(_root, user.ToString("N"), KostvMusicStore.MonthName(lastMonth.Year, lastMonth.Month));
        File.AppendAllText(lastFile, JsonSerializer.Serialize(Listen(songs[1], _now.AddMinutes(-30))) + "\n");
        Assert.Equal(TasteJson(Expected()), TasteJson(store.RecomputeTaste(user)));
        Assert.Equal(TasteJson(Expected()), TasteJson(store.RecomputeTaste(user)));

        // And the daily round, for everyone, the same.
        _now = _now.AddDays(1);
        ADayOf(store, user, songs, _now.AddHours(-1), random);
        Assert.Equal(1, store.RecomputeTastes());
        Assert.Equal(TasteJson(Expected()), TasteJson(store.Taste(user)));

        // With the listens deleted, nothing of before is kept.
        store.DeleteListens(user);
        Assert.Equal(0, store.RecomputeTaste(user).Listens);
    }
}
