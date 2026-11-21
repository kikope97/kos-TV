using System.Text.Json;
using Jellyfin.Data.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Model.Entities;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: what the review of the music that learns found, kept from coming back: the taste read
/// while it is brought up to date, a genre of one artist almost alone, small libraries and the
/// days not to repeat, taste.json written now and then, files with lists as null, weeks shown
/// out of order, the daily round, hearts the same day and «no me gusta» checked.
/// </summary>
public sealed partial class KostvMusicTests
{
    private static KostvMusicTrack Track(int i, string artist, string genre, int plays) =>
        new(new Guid(i, 0, 0, new byte[8]), [artist], [genre], plays, plays > 0 ? new DateTime(2026, 11, 1, 0, 0, 0, DateTimeKind.Utc) : null, Album: new Guid(i / 10 + 100000, 0, 0, new byte[8]));

    // ---------------------------------------------------------------- 1. the taste read while it changes

    [Fact]
    public void TheTasteGivenIsACopySoItCanBeReadWhileListensAreNoted()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        store.Append(user, Listen(Guid.NewGuid(), _now));
        var first = store.Taste(user);
        Assert.NotSame(first, store.Taste(user));

        Exception? caught = null;
        var done = false;
        var writer = new Thread(() =>
        {
            for (var i = 0; i < 1500; i++)
            {
                store.Append(user, Listen(Guid.NewGuid(), _now));
            }

            done = true;
        });
        writer.Start();
        try
        {
            while (!Volatile.Read(ref done))
            {
                var summary = store.Taste(user);
                summary.OldListens(_now);
                summary.PlayedSongs().ToList();
                KostvMusicEngine.LearnedProfile([], summary, _now);
            }
        }
        catch (Exception ex)
        {
            caught = ex;
        }

        writer.Join();
        Assert.Null(caught);
        // The copy given before stays as it was.
        Assert.Equal(1, first.Listens);
        Assert.Equal(1501, store.Taste(user).Listens);
    }

    // ---------------------------------------------------------------- 2. a genre of one artist almost alone

    [Fact]
    public void AGenreOfOneArtistAlmostAloneStillHasItsMix()
    {
        var tracks = new List<KostvMusicTrack>();
        for (var i = 1; i <= 80; i++)
        {
            tracks.Add(Track(i, "Cantajuego", "Infantil", 5));
        }

        for (var i = 200; i <= 205; i++)
        {
            tracks.Add(Track(i, "Otro " + i, "Infantil", 1));
        }

        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, null, new KostvMixRules(new HashSet<Guid>(), KostvDislikeSet.Empty, _now)));
        Assert.True(mix.Items.Count >= KostvMusicEngine.MinMixSize, $"{mix.Items.Count} songs");
        // Only as far as it takes to have one: not filled up to 50 with the same artist.
        Assert.True(mix.Items.Count < KostvMusicEngine.MixSize);
        var byId = tracks.ToDictionary(t => t.Id);
        // Never two of one album in a row, even so.
        Assert.All(mix.Items.Zip(mix.Items.Skip(1)), pair => Assert.NotEqual(byId[pair.First].Album, byId[pair.Second].Album));
        // The others still go in between while there are.
        Assert.Equal(6, mix.Items.Count(id => byId[id].PrimaryArtist != "Cantajuego"));
    }

    [Fact]
    public void TheLastResortGoesOnlyAsFarAsTheLeastAMixIsOfferedWith()
    {
        var known = Enumerable.Range(1, 40).Select(i => Track(i, "Uno", "Pop", 3)).ToList();
        Assert.Single(KostvMusicEngine.Arrange(known, [], 50, 0, _ => 1, new Dictionary<string, IReadOnlyList<string>>()));
        var filled = KostvMusicEngine.Arrange(known, [], 50, 0, _ => 1, new Dictionary<string, IReadOnlyList<string>>(), fillTo: 20);
        Assert.Equal(20, filled.Count);
        Assert.All(filled.Zip(filled.Skip(1)), pair => Assert.NotEqual(pair.First.Album, pair.Second.Album));
    }

    // ---------------------------------------------------------------- 3. small libraries and the days not to repeat

    [Fact]
    public void WithFewSongsKnownTheOldestDayIsGivenBackFirstAndWhatWasHeardLast()
    {
        var tracks = new List<KostvMusicTrack>();
        for (var i = 1; i <= 120; i++)
        {
            tracks.Add(Track(i, "Art " + (i % 12), "Pop", 3));
        }

        for (var i = 1001; i <= 1400; i++)
        {
            tracks.Add(Track(i, "Otro " + (i % 30), "Pop", 0));
        }

        var known = tracks.Where(t => t.PlayCount > 0).Select(t => t.Id).ToHashSet();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var shown = new List<HashSet<Guid>>();
        var heard = new HashSet<Guid>(known.Take(5));
        for (var day = 0; day < 6; day++)
        {
            // The three days before, the oldest first, and what was heard last.
            var tiers = shown.TakeLast(KostvMusicService.NoRepeatDays).Cast<IReadOnlySet<Guid>>().Append(heard).ToList();
            var rules = new KostvMixRules(new HashSet<Guid>(), KostvDislikeSet.Empty, _now.AddDays(day), tiers);
            var items = KostvMusicEngine.Mixes(Guid.NewGuid(), $"2026-11-{20 + day}", tracks, profile, null, rules).SelectMany(m => m.Items).ToList();
            var knownIn = items.Count(known.Contains);
            Assert.True(knownIn >= 30, $"day {day}: {knownIn} known of {items.Count}");
            // What was heard in the last day stays out: there is enough without it.
            Assert.DoesNotContain(items, heard.Contains);
            if (day >= 3)
            {
                // Given back: from the oldest of the three days, not from the day before.
                Assert.Contains(items, tiers[0].Contains);
                Assert.DoesNotContain(items, id => tiers[2].Contains(id) && !tiers[0].Contains(id) && !tiers[1].Contains(id));
            }

            shown.Add(items.ToHashSet());
        }
    }

    [Fact]
    public void WhatWasHeardInTheLastDayIsGivenBackOnlyWhenStillShort()
    {
        var tracks = Enumerable.Range(1, 30).Select(i => Track(i, "Art " + (i % 10), "Pop", 3)).ToList();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var heard = tracks.Take(20).Select(t => t.Id).ToHashSet();
        var rules = new KostvMixRules(new HashSet<Guid>(), KostvDislikeSet.Empty, _now, [new HashSet<Guid>(), heard]);
        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, null, rules));
        // Ten left wouldn't make a mix: those heard come back too.
        Assert.Contains(mix.Items, heard.Contains);
        // And a song left out for good (not for repeating) never does.
        var hard = new KostvMixRules(heard, KostvDislikeSet.Empty, _now, [new HashSet<Guid>()]);
        Assert.All(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, null, hard), m => Assert.DoesNotContain(m.Items, heard.Contains));
    }

    // ---------------------------------------------------------------- 4. taste.json now and then

    [Fact]
    public void TheTasteIsWrittenNowAndThenAndWhenFlushedWithoutOldShownSongs()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var shownOnly = Guid.NewGuid();
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MomentSurface, Items = [shownOnly.ToString("N")] }.Stamp(_now.AddDays(-100), Home));
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(1, store.Taste(user).Listens);
        // Worked out in full: the song only shown long ago isn't kept.
        Assert.Null(store.Taste(user).SongOf(shownOnly));

        int Stored() => NewStore().Taste(user).Listens;
        for (var i = 0; i < KostvMusicStore.TasteSaveAfter - 1; i++)
        {
            store.Append(user, Listen(Guid.NewGuid(), _now));
        }

        // Not written with each line...
        Assert.Equal(1, Stored());
        Assert.Equal(KostvMusicStore.TasteSaveAfter, store.Taste(user).Listens);
        // ...but once enough are added.
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(KostvMusicStore.TasteSaveAfter + 1, Stored());

        // Or once the first not written is old enough.
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(KostvMusicStore.TasteSaveAfter + 1, Stored());
        _now += KostvMusicStore.TasteSaveEvery;
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(KostvMusicStore.TasteSaveAfter + 3, Stored());

        // And when flushed (the server stopping, the daily round), a song only shown long ago
        // goes as it is written.
        var lately = Guid.NewGuid();
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MomentSurface, Items = [lately.ToString("N")] }.Stamp(_now, Home));
        store.FlushTastes();
        Assert.NotNull(NewStore().Taste(user).SongOf(lately));
        _now += KostvTasteWeights.ShownForgottenAfter + TimeSpan.FromDays(1);
        store.Append(user, Listen(Guid.NewGuid(), _now));
        store.FlushTastes();
        var written = NewStore().Taste(user);
        Assert.Equal(KostvMusicStore.TasteSaveAfter + 4, written.Listens);
        Assert.Null(written.SongOf(lately));
    }

    // ---------------------------------------------------------------- 5. files with lists as null

    [Fact]
    public void FilesWithListsAsNullAreReadAsEmpty()
    {
        var user = Guid.NewGuid();
        var folder = Path.Combine(_root, user.ToString("N"));
        Directory.CreateDirectory(folder);
        File.WriteAllText(Path.Combine(folder, "dislikes.json"), "{\"songs\":null,\"artists\":[null,{\"id\":\"\"}]}");
        File.WriteAllText(Path.Combine(folder, "taste.json"), $"{{\"v\":{KostvTasteSummary.CurrentVersion},\"listens\":3,\"songs\":null,\"artists\":{{\"x\":null}},\"albums\":null}}");
        var store = NewStore();

        var dislikes = store.DislikesOf(user);
        Assert.Empty(dislikes.Songs);
        Assert.Empty(dislikes.Artists);
        Assert.True(KostvDislikeSet.Of(dislikes).IsEmpty);
        Assert.True(store.AddDislikes(user, [new KostvDislikedSong { Id = Guid.NewGuid().ToString("N"), Name = "Canción", At = _now }], []));
        Assert.Single(NewStore().DislikesOf(user).Songs);

        var taste = store.Taste(user);
        Assert.Equal(3, taste.Listens);
        Assert.Empty(taste.Songs);
        Assert.Empty(taste.OldListens(_now));
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(4, store.Taste(user).Listens);

        // A shown line with a mix written as null, and an artist's heart without a name.
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MixesSurface, Mixes = [null!] }.Stamp(_now, Home));
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.FavoriteType, Kind = KostvMusicEvent.ArtistKind, Item = Guid.NewGuid().ToString("N"), Favorite = true, Artists = [null!] }.Stamp(_now, Home));
        // Worked out from the lines (the three of the file were made up), without failing.
        Assert.Equal(1, store.RecomputeTaste(user).Listens);
    }

    // ---------------------------------------------------------------- 6. weeks shown out of order

    [Fact]
    public void WeeksShownOutOfOrderCountOnceEach()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var song = Guid.NewGuid();
        store.Append(user, Listen(Guid.NewGuid(), _now.AddDays(-30)));
        store.Taste(user);
        KostvMusicEvent Shown(DateTimeOffset at) =>
            new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MomentSurface, Items = [song.ToString("N")] }.Stamp(at, Home);
        store.Append(user, Shown(_now.AddDays(-1)));
        store.Append(user, Shown(_now.AddDays(-8)));
        store.Append(user, Shown(_now.AddDays(-1)));
        Assert.Equal(2, store.Taste(user).SongOf(song)!.ShownWeeks);
        Assert.Equal(2, store.RecomputeTaste(user).SongOf(song)!.ShownWeeks);

        // An old taste.json (the weeks counted, not kept) is worked out again.
        var folder = Path.Combine(_root, user.ToString("N"));
        File.WriteAllText(Path.Combine(folder, "taste.json"), "{\"v\":1,\"listens\":99}");
        Assert.Equal(1, NewStore().Taste(user).Listens);
    }

    // ---------------------------------------------------------------- 7. the daily round

    [Fact]
    public void TheDailyRoundGoesOnWhenOnePersonsTasteFails()
    {
        var store = NewStore();
        var (ana, luis, anasSong) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        store.Append(ana, Listen(anasSong, _now));
        store.Append(luis, Listen(Guid.NewGuid(), _now));
        var real = store.Summarize;
        // Ana's fails, whatever the order the folders are read in: Luis's is worked out all the same.
        store.Summarize = (events, now) => events.Any(e => e.Item == anasSong.ToString("N"))
            ? throw new InvalidOperationException("roto")
            : real(events, now);
        Assert.Equal(1, store.RecomputeTastes());
        store.Summarize = real;
        Assert.Equal(2, store.RecomputeTastes());
    }

    // ---------------------------------------------------------------- 8. when the round goes, and hearts the same day

    [Theory]
    // 11:00 at home: the next day at 5:01.
    [InlineData("2026-11-20T10:00:00Z", 18 * 60 + 1)]
    // 3:00 at home is still the day before: 5:01 of the same night.
    [InlineData("2026-11-21T02:00:00Z", 2 * 60 + 1)]
    // Just past 5:00: a whole day.
    [InlineData("2026-11-21T04:02:00Z", 23 * 60 + 59)]
    public void TheDailyRoundGoesAsTheMusicDayStartsAtHome(string now, int minutes)
    {
        Assert.Equal(TimeSpan.FromMinutes(minutes), KostvMusicRecorder.NextRoundIn(DateTimeOffset.Parse(now, System.Globalization.CultureInfo.InvariantCulture), Home));
    }

    [Fact]
    public async Task AHeartCountsTheSameDay()
    {
        var library = MusicLibrary.Made(genres: 2, artists: 12, played: 6, unplayed: 4);
        var service = NewService(library);
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        await service.MixesAsync(userId, user);
        var today = Path.Combine(_root, userId.ToString("N"), "today.json");
        Assert.True(File.Exists(today));

        var recorder = new KostvMusicRecorder(null!, null!, library.Manager(), service.Store, new KostvMusicContext(), NullLogger<KostvMusicRecorder>.Instance, music: service);
        var song = library.Items.OfType<Audio>().First();
        recorder.OnUserDataSaved(null, Heart(userId, song, true, UserDataSaveReason.UpdateUserRating));
        await recorder.Settled();
        Assert.False(File.Exists(today));

        // With Learn off it isn't noted, but the server's hearts count all the same.
        await service.MixesAsync(userId, user);
        service.Store.SetSettings(userId, false, null);
        recorder.OnUserDataSaved(null, Heart(userId, song, false, UserDataSaveReason.UpdateUserRating));
        await recorder.Settled();
        Assert.False(File.Exists(today));
    }

    // ---------------------------------------------------------------- 9 and 10. «no me gusta» checked

    [Fact]
    public void ADislikeKeepsOnlyWhatIsAtHomeAndOfItsKind()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var song = library.Items.OfType<Audio>().First();
        var artist = library.Items.OfType<MusicArtist>().First(a => a.Name == song.Artists[0]);

        // An artist as a song, a song not at home: let go of, still a 204.
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString(), Guid.NewGuid().ToString() } })));
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { Guid.NewGuid().ToString() }, Kind = "artist" })));
        var none = service.Store.DislikesOf(userId);
        Assert.Empty(none.Songs);
        Assert.Empty(none.Artists);

        // A song for an artist: its main artist, by its id at home.
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { song.Id.ToString() }, Kind = "artist" })));
        var kept = Assert.Single(service.Store.DislikesOf(userId).Artists);
        Assert.Equal((artist.Id.ToString("N"), artist.Name), (kept.Id, kept.Name));
        Assert.Empty(service.Store.DislikesOf(userId).Songs);
    }

    [Fact]
    public void AnArtistRenamedSinceIsStillOut()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var artist = library.Items.OfType<MusicArtist>().First();
        var songs = library.Items.OfType<Audio>().Where(s => s.Artists[0] == artist.Name).ToList();
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString() }, Kind = "artist" }));

        artist.Name = "Nombre nuevo";
        foreach (var song in songs)
        {
            song.Artists = ["Nombre nuevo"];
        }

        var dislikes = service.DislikeSetOf(userId);
        Assert.True(dislikes.BlocksArtist(artist.Id, "Otro nombre"));
        Assert.All(songs, s => Assert.True(KostvMusicService.Blocks(dislikes, s)));
    }

    [Fact]
    public void ADislikeNotStoredIsA500()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        // Where the list goes there is a folder: it can't be written.
        Directory.CreateDirectory(Path.Combine(_root, userId.ToString("N"), "dislikes.json"));
        var result = controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { library.Items.OfType<Audio>().First().Id.ToString() } }));
        Assert.Equal(500, Assert.IsAssignableFrom<ObjectResult>(result).StatusCode);
    }

    [Fact]
    public void TheArtistsOfTheSongsDislikedAreLookedForAtOnce()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var artist = library.Items.OfType<MusicArtist>().First();
        var songs = library.Items.OfType<Audio>().Where(s => s.Artists[0] == artist.Name).Take(3).ToList();
        var before = library.Queries;
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = songs.Select(s => s.Id.ToString()).ToArray() }));
        Assert.Equal(1, library.Queries - before);
        Assert.All(service.Store.DislikesOf(userId).Songs, s => Assert.Equal(artist.Id.ToString("N"), s.ArtistId));
    }

    [Fact]
    public async Task AnArtistNotAtHomeIsNotLookedForAgainEachTime()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId, MusicLibrary.Made(genres: 2, artists: 6, played: 4, unplayed: 2));
        // Artists whose songs are at home but not themselves (not scanned yet, say).
        library.Items.RemoveAll(i => i is MusicArtist);
        var first = Json(await controller.GetTaste());
        Assert.All(first.GetProperty("Artists").EnumerateArray(), a => Assert.Equal(JsonValueKind.Null, a.GetProperty("Id").ValueKind));
        var before = library.Queries;
        await controller.GetTaste();
        Assert.Equal(before, library.Queries);
    }

    [Fact]
    public void TheEnginesAreNotComparedWithWhatWasWorkedOutBeforeTheListensWereDeleted()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        store.Append(user, Listen(Guid.NewGuid(), _now));
        var shadow = Path.Combine(_root, user.ToString("N"), "shadow.json");
        var today = new KostvMusicStore.KostvShadow { Day = "2026-11-20", Old = [Guid.NewGuid()], New = [Guid.NewGuid()] };
        var started = _now;
        _now = _now.AddSeconds(5);
        store.DeleteListens(user);
        store.NoteShadow(user, today, (_, _) => (0, 0), started);
        Assert.False(File.Exists(shadow));

        // Worked out after: noted.
        store.NoteShadow(user, today, (_, _) => (0, 0), _now);
        Assert.True(File.Exists(shadow));
    }
}
