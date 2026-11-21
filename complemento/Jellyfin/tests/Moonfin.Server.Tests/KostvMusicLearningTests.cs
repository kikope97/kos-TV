using System.Text.Json;
using Jellyfin.Data.Entities;
using MediaBrowser.Controller.Entities.Audio;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: the music that learns from every signal: what each listen weighs, the taste summed up
/// as listens are noted, «no me gusta», the rules of variety and of not repeating, the taste for
/// the app, the engine chosen and the other one compared, and the seeds rotating each week.
/// </summary>
public sealed partial class KostvMusicTests
{
    private static KostvMusicEvent Heard(Guid item, DateTimeOffset at, int played = 200, int duration = 200, string? endedBy = KostvListenEnd.Natural, string? source = null, bool? shuffle = null)
    {
        var outcome = KostvListenOutcome.Classify(played, duration, endedBy == KostvListenEnd.Natural);
        return new KostvMusicEvent { Item = item.ToString("N"), Outcome = outcome, Played = played, Duration = duration, EndedBy = endedBy, Source = source, Shuffle = shuffle }.Stamp(at, Home);
    }

    private static string ArtistKeyOf(KostvMusicTrack track) => track.PrimaryArtist!.Trim().ToLowerInvariant();

    /// <summary>
    /// The rules of variety: never the same artist closer than three songs (or <paramref name="gap"/>,
    /// where the library can't give more), nor two of one album in a row; and, when asked, at most
    /// three of one artist each 25.
    /// </summary>
    private static void AssertVariety(IReadOnlyList<KostvMusicTrack> items, bool perBlock = false, int gap = KostvMusicEngine.VarietyGap)
    {
        for (var i = 0; i < items.Count; i++)
        {
            for (var j = Math.Max(0, i - gap); j < i; j++)
            {
                Assert.NotEqual(ArtistKeyOf(items[j]), ArtistKeyOf(items[i]));
            }

            if (i > 0 && items[i].Album != null)
            {
                Assert.NotEqual(items[i - 1].Album, items[i].Album);
            }
        }

        if (perBlock)
        {
            foreach (var block in items.Chunk(KostvMusicEngine.VarietyBlock))
            {
                Assert.All(block.GroupBy(ArtistKeyOf), g => Assert.True(g.Count() <= KostvMusicEngine.VarietyPerBlock, $"{g.Key}: {g.Count()} in 25"));
            }
        }
    }

    /// <summary>A library of <paramref name="genres"/> genres with many artists each, two albums per artist.</summary>
    private static List<KostvMusicTrack> WideLibrary(int genres = 2, int artists = 14, int played = 4, int unplayed = 4, int plays = 5)
    {
        var tracks = new List<KostvMusicTrack>();
        for (var g = 0; g < genres; g++)
        {
            for (var a = 0; a < artists; a++)
            {
                var albums = new[] { Guid.NewGuid(), Guid.NewGuid() };
                for (var s = 0; s < played + unplayed; s++)
                {
                    var count = s < played ? plays + a % 3 : 0;
                    tracks.Add(new KostvMusicTrack(Guid.NewGuid(), [$"Artista {g}-{a}"], [$"Género {g}"], count, count > 0 ? new DateTime(2026, 11, 10, 0, 0, 0, DateTimeKind.Utc) : null, Album: albums[s % 2]));
                }
            }
        }

        return tracks;
    }

    // ---------------------------------------------------------------- what a listen weighs

    [Theory]
    // Heard: to the end, faded into the next 12 s before its end, half of it, or 4 minutes.
    [InlineData(200, 200, KostvListenEnd.Natural, null, null, 1.0, true, false)]
    [InlineData(188, 200, KostvListenEnd.Natural, "mix:daily-1", null, 1.0, true, false)]
    [InlineData(188, 200, KostvListenEnd.Next, "mix:daily-1", null, 1.0, true, false)]
    [InlineData(100, 200, KostvListenEnd.Next, null, null, 1.0, true, false)]
    [InlineData(250, 600, KostvListenEnd.Next, null, null, 1.0, true, false)]
    // Chosen on purpose: ×1.5; not with shuffle on.
    [InlineData(200, 200, KostvListenEnd.Natural, "search", null, 1.5, true, false)]
    [InlineData(200, 200, KostvListenEnd.Natural, "album", true, 1.0, true, false)]
    // The app closed, the session ended, it failed late or nothing followed: nothing.
    [InlineData(20, 200, KostvListenEnd.Closed, "album", null, 0.0, false, false)]
    [InlineData(10, 200, KostvListenEnd.Stop, "album", null, 0.0, false, false)]
    [InlineData(60, 200, KostvListenEnd.Error, "album", null, 0.0, false, false)]
    // Skipped before 30 s: by hand, in a mix, from where the app didn't say, with shuffle.
    [InlineData(10, 200, KostvListenEnd.Next, "album", null, -0.5, false, true)]
    [InlineData(10, 200, KostvListenEnd.Next, "playlist", null, -0.5, false, true)]
    [InlineData(10, 200, KostvListenEnd.Next, "mix:daily-2", null, -0.3, false, true)]
    [InlineData(10, 200, KostvListenEnd.Next, "radio", null, -0.3, false, true)]
    [InlineData(10, 200, KostvListenEnd.Next, null, null, -0.3, false, true)]
    [InlineData(10, 200, KostvListenEnd.Next, "album", true, -0.1, false, true)]
    // Skipped between 30 s and half of it.
    [InlineData(60, 200, KostvListenEnd.Next, "album", null, -0.1, false, true)]
    // A line from before endedBy, skipped.
    [InlineData(10, 200, null, null, null, -0.3, false, true)]
    public void EachListenWeighsByHowItEndedAndFromWhere(int played, int duration, string? endedBy, string? source, bool? shuffle, double weight, bool heard, bool skip)
    {
        var e = Heard(Guid.NewGuid(), _now, played, duration, endedBy, source, shuffle);
        var w = KostvMusicEngine.WeighListen(e);
        Assert.Equal(weight, w.Weight, 6);
        Assert.Equal(heard, w.Heard);
        Assert.Equal(skip, w.Skip);
    }

    [Fact]
    public void PlayedAgainOrTakenBackAddsHalfAndAFailureEarlyIsNothing()
    {
        var song = Guid.NewGuid();
        var again = Heard(song, _now);
        again.Replay = true;
        Assert.Equal(1.5, KostvMusicEngine.WeighListen(again).Weight, 6);
        var back = Heard(song, _now, source: "search");
        back.SeekBack = 2;
        Assert.Equal(2.25, KostvMusicEngine.WeighListen(back).Weight, 6);

        var failed = Heard(song, _now, played: 5, endedBy: KostvListenEnd.Error);
        Assert.False(failed.Counts);
        Assert.Equal(KostvListenWeight.Nothing, KostvMusicEngine.WeighListen(failed));
    }

    // ---------------------------------------------------------------- the taste summed up

    private List<KostvMusicEvent> SampleHistory(Guid[] songs, int count, int seed)
    {
        var random = new Random(seed);
        var events = new List<KostvMusicEvent>();
        for (var i = 0; i < count; i++)
        {
            var at = _now.AddDays(-random.Next(0, 300)).AddMinutes(-random.Next(0, 1440));
            var song = songs[random.Next(songs.Length)];
            KostvMusicEvent e = random.Next(10) switch
            {
                < 5 => Heard(song, at),
                5 => Heard(song, at, played: 10, endedBy: KostvListenEnd.Next, source: random.Next(2) == 0 ? "album" : "mix:daily-1"),
                6 => Heard(song, at, played: 70, endedBy: KostvListenEnd.Next, shuffle: true),
                7 => Heard(song, at, played: 15, endedBy: KostvListenEnd.Closed),
                8 => new KostvMusicEvent { Type = KostvMusicEvent.PlaylistAddType, Items = [song.ToString("N")] }.Stamp(at, Home),
                _ => new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MixesSurface, Mixes = [new KostvShownMix { Id = "daily-1", Items = [Guid.NewGuid().ToString("N"), song.ToString("N")] }] }.Stamp(at, Home)
            };
            events.Add(e);
        }

        return events;
    }

    [Fact]
    public void TheTasteBroughtUpToDateLineByLineIsTheSameAsWorkedOutInFull()
    {
        var songs = Enumerable.Range(0, 30).Select(_ => Guid.NewGuid()).ToArray();
        var events = SampleHistory(songs, 600, seed: 7);
        var full = KostvMusicEngine.Summarize(events, _now);

        // In the order they are noted, a little out of the order they happened.
        var step = new KostvTasteSummary();
        foreach (var e in events.OrderBy(e => e.At.AddMinutes(-(e.Item.GetHashCode() & 7))))
        {
            step.Apply(e);
        }

        Assert.Equal(full.Listens, step.Listens);
        foreach (var id in songs)
        {
            var a = full.SongOf(id);
            var b = step.SongOf(id);
            if (a == null)
            {
                Assert.Null(b);
                continue;
            }

            Assert.Equal(a.LongAt(_now), b!.LongAt(_now), 9);
            Assert.Equal(a.ShortAt(_now), b.ShortAt(_now), 9);
            Assert.Equal((a.Plays, a.Skips, a.LastHeard, a.Playlist), (b.Plays, b.Skips, b.LastHeard, b.Playlist));
        }

        // The old engine's counts come out of it the same as from reading every listen.
        var old = KostvMusicEngine.Listens(events, _now);
        var fromSummary = full.OldListens(_now);
        Assert.Equal(old.Keys.OrderBy(k => k), fromSummary.Keys.OrderBy(k => k));
        foreach (var (id, stats) in old)
        {
            Assert.Equal((stats.Completed, stats.Skipped, stats.Stopped), (fromSummary[id].Completed, fromSummary[id].Skipped, fromSummary[id].Stopped));
            Assert.Equal(stats.Score, fromSummary[id].Score, 9);
        }
    }

    [Fact]
    public void TheBackgroundTasteHalvesEveryNinetyDaysAndTheTasteOfNowEveryFourteen()
    {
        var song = Guid.NewGuid();
        var summary = KostvMusicEngine.Summarize([Heard(song, _now.AddDays(-90))], _now);
        Assert.Equal(0.5, summary.SongOf(song)!.LongAt(_now), 9);
        Assert.Equal(Math.Pow(0.5, 90 / 14.0), summary.SongOf(song)!.ShortAt(_now), 9);
        Assert.Equal(1, summary.Listens);
    }

    [Fact]
    public void ASongIsOutOfTheMixesWhenSkippedTooOftenWithMarginButNotWithAHeart()
    {
        var tracks = Enumerable.Range(0, 4).Select(i => new KostvMusicTrack(Guid.NewGuid(), [$"A{i}"], ["Pop"], 3, new DateTime(2026, 11, 10, 0, 0, 0, DateTimeKind.Utc), Favorite: i == 3)).ToList();
        KostvMusicEvent Skip(Guid id, int days) => Heard(id, _now.AddDays(-days), played: 8, endedBy: KostvListenEnd.Next);
        var events = new List<KostvMusicEvent>
        {
            // Two skips and one heard: (2+1)/(3+4) = 43 %.
            Skip(tracks[0].Id, 1), Skip(tracks[0].Id, 2), Heard(tracks[0].Id, _now.AddDays(-3)),
            // Three of three: 4/7 = 57 %, still in.
            Skip(tracks[1].Id, 1), Skip(tracks[1].Id, 2), Skip(tracks[1].Id, 3),
            // Four of four: 5/8 = 62 %, out.
            Skip(tracks[2].Id, 1), Skip(tracks[2].Id, 2), Skip(tracks[2].Id, 3), Skip(tracks[2].Id, 4),
            // The same with a heart: in.
            Skip(tracks[3].Id, 1), Skip(tracks[3].Id, 2), Skip(tracks[3].Id, 3), Skip(tracks[3].Id, 4)
        };
        // The app closing on them doesn't count against them.
        events.AddRange(Enumerable.Range(0, 6).Select(i => Heard(tracks[0].Id, _now.AddDays(-i), played: 12, endedBy: KostvListenEnd.Closed)));
        var profile = KostvMusicEngine.LearnedProfile(tracks, KostvMusicEngine.Summarize(events, _now), _now);

        Assert.Equal([tracks[2].Id], profile.Dropped);
        Assert.Contains(tracks[3].Id, profile.Scores.Keys);
        Assert.Contains(tracks[0].Id, profile.Scores.Keys);
        Assert.Equal(3, KostvMusicEngine.Summarize(events, _now).SongOf(tracks[0].Id)!.Plays);
    }

    [Fact]
    public void TheLearnedTasteTakesOverFromTheServersAsListensAddUp()
    {
        var known = new KostvMusicTrack(Guid.NewGuid(), ["Antes"], ["Pop"], 15, new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc));
        var learnedSong = new KostvMusicTrack(Guid.NewGuid(), ["Ahora"], ["Pop"]);
        var tracks = new List<KostvMusicTrack> { known, learnedSong };
        var empty = KostvMusicEngine.LearnedProfile(tracks, new KostvTasteSummary(), _now);
        var jellyfin = Math.Log2(16) * (0.35 + 0.65 * Math.Pow(0.5, 1.0 / 60 * (_now - new DateTimeOffset(2026, 11, 19, 0, 0, 0, TimeSpan.Zero)).TotalDays));
        Assert.Equal(jellyfin, empty.Scores[known.Id], 9);
        Assert.False(empty.Scores.ContainsKey(learnedSong.Id));

        foreach (var (listens, share) in new[] { (150, 0.5), (300, 1.0), (600, 1.0) })
        {
            var events = Enumerable.Range(0, listens).Select(i => Heard(learnedSong.Id, _now.AddMinutes(-i))).ToList();
            var summary = KostvMusicEngine.Summarize(events, _now);
            Assert.Equal(share, summary.Learned, 9);
            var profile = KostvMusicEngine.LearnedProfile(tracks, summary, _now);
            Assert.Equal((1 - share) * jellyfin, profile.Scores.GetValueOrDefault(known.Id), 9);
            Assert.True(profile.Scores[learnedSong.Id] > 0);
        }
    }

    [Fact]
    public void HeartsListsAndAlbumsWithAHeartCountFromTheFirstDay()
    {
        var album = Guid.NewGuid();
        var heart = new KostvMusicTrack(Guid.NewGuid(), ["A"], ["Pop"], Favorite: true);
        var listed = new KostvMusicTrack(Guid.NewGuid(), ["B"], ["Pop"]);
        var ofAlbum = new KostvMusicTrack(Guid.NewGuid(), ["C"], ["Pop"], Album: album);
        var events = new List<KostvMusicEvent>
        {
            new KostvMusicEvent { Type = KostvMusicEvent.PlaylistAddType, Items = [listed.Id.ToString("N")] }.Stamp(_now.AddDays(-400), Home),
            new KostvMusicEvent { Type = KostvMusicEvent.FavoriteType, Kind = KostvMusicEvent.AlbumKind, Item = album.ToString("N"), Favorite = true }.Stamp(_now.AddDays(-2), Home),
            new KostvMusicEvent { Type = KostvMusicEvent.FavoriteType, Kind = KostvMusicEvent.ArtistKind, Item = Guid.NewGuid().ToString("N"), Artists = ["C"], Favorite = true }.Stamp(_now.AddDays(-2), Home),
            new KostvMusicEvent { Type = KostvMusicEvent.RequestType, ArtistName = "B" }.Stamp(_now, Home)
        };
        var profile = KostvMusicEngine.LearnedProfile([heart, listed, ofAlbum], KostvMusicEngine.Summarize(events, _now), _now);

        // Without a single listen, and never fading.
        Assert.Equal(KostvTasteWeights.Heart, profile.Scores[heart.Id], 9);
        Assert.Equal(KostvTasteWeights.Playlist, profile.Scores[listed.Id], 9);
        Assert.Equal(KostvTasteWeights.FavoriteAlbumOrArtist, profile.Scores[ofAlbum.Id], 9);
        // The artist with a heart gets 2 more; the one asked for in Stremfin, 1.
        var artists = profile.Artists.ToDictionary(a => a.Name, a => a.Weight);
        Assert.Equal(Math.Sqrt(2) + 2, artists["C"], 9);
        Assert.Equal(Math.Sqrt(2) + 1, artists["B"], 9);

        // A heart taken off later.
        events.Add(new KostvMusicEvent { Type = KostvMusicEvent.FavoriteType, Kind = KostvMusicEvent.AlbumKind, Item = album.ToString("N"), Favorite = false }.Stamp(_now.AddDays(-1), Home));
        Assert.False(KostvMusicEngine.LearnedProfile([ofAlbum], KostvMusicEngine.Summarize(events, _now), _now).Scores.ContainsKey(ofAlbum.Id));
    }

    [Fact]
    public void ArtistsAndGenresAddUpUnderASquareRootAndTheSecondArtistCountsHalf()
    {
        var day = new DateTime(2026, 11, 20, 0, 0, 0, DateTimeKind.Utc);
        var tracks = new List<KostvMusicTrack>
        {
            new(Guid.NewGuid(), ["Mucho", "Invitada"], ["Rock"], 255, day),
            new(Guid.NewGuid(), ["Poco"], ["Pop"], 3, day),
            new(Guid.NewGuid(), ["Poco"], ["Pop"], 3, day)
        };
        var profile = KostvMusicEngine.LearnedProfile(tracks, null, _now);
        var weights = profile.Artists.ToDictionary(a => a.Name, a => a.Weight);
        var mucho = profile.Scores[tracks[0].Id];
        Assert.Equal(Math.Sqrt(mucho), weights["Mucho"], 9);
        Assert.Equal(Math.Sqrt(mucho / 2), weights["Invitada"], 9);
        Assert.Equal(Math.Sqrt(profile.Scores[tracks[1].Id] * 2), weights["Poco"], 9);
        Assert.Equal(Math.Sqrt(mucho), profile.Genres.Single(g => g.Name == "Rock").Weight, 9);
    }

    [Fact]
    public void ASongShownManyWeeksAndNeverPlayedWeighsLessUpToALimit()
    {
        var song = Guid.NewGuid();
        var events = Enumerable.Range(0, 9)
            .Select(w => new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MixesSurface, Mixes = [new KostvShownMix { Id = "daily-1", Items = [song.ToString("N")] }] }.Stamp(_now.AddDays(-7 * w), Home))
            .ToList();
        // Twice the same week is one week.
        events.Add(new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MomentSurface, Slot = "tarde", Items = [song.ToString("N")] }.Stamp(_now, Home));
        var summary = KostvMusicEngine.Summarize(events.Take(3).Append(events[^1]), _now);
        Assert.Equal(3, summary.SongOf(song)!.ShownWeeks);
        Assert.Equal(0.6, KostvMusicEngine.LearnedProfile([], summary, _now).ShownPenalty![song], 9);
        Assert.Equal(1.0, KostvMusicEngine.LearnedProfile([], KostvMusicEngine.Summarize(events, _now), _now).ShownPenalty![song], 9);

        // Once played, it no longer counts; and one only shown long ago is forgotten.
        events.Add(Heard(song, _now));
        Assert.Empty(KostvMusicEngine.LearnedProfile([], KostvMusicEngine.Summarize(events, _now), _now).ShownPenalty!);
        Assert.Null(KostvMusicEngine.Summarize(events.Take(1), _now.AddDays(100)).SongOf(song));
    }

    // ---------------------------------------------------------------- «no me gusta» in the engine

    private static KostvDislikeSet DislikeSet(IEnumerable<KostvMusicTrack> songs, params string[] artists) =>
        KostvDislikeSet.Of(new KostvDislikes
        {
            Songs = songs.Select(s => new KostvDislikedSong { Id = s.Id.ToString("N"), Artist = s.PrimaryArtist }).ToList(),
            Artists = artists.Select(a => new KostvDislikedArtist { Id = Guid.NewGuid().ToString("N"), Name = a }).ToList()
        });

    [Fact]
    public void WhatIsDislikedIsOutOfEverythingAndASongsArtistWeighsLess()
    {
        var tracks = WideLibrary(genres: 1, artists: 14);
        // A guest on a song of another artist is out with them.
        tracks.Add(new KostvMusicTrack(Guid.NewGuid(), ["Artista 0-5", "Artista 0-0"], ["Género 0"], 50, new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc)));
        var ofOne = tracks.Where(t => t.PrimaryArtist == "Artista 0-1" && t.PlayCount > 0).ToList();
        var noDislikes = KostvMusicEngine.LearnedProfile(tracks, null, _now);
        double WeightOf(KostvMusicProfile p, string name) => p.Artists.Single(a => a.Name == name).Weight;

        foreach (var (count, factor) in new[] { (1, 0.8), (2, 0.6), (3, 0.25) })
        {
            var dislikes = DislikeSet(ofOne.Take(count));
            foreach (var profile in new[] { KostvMusicEngine.LearnedProfile(tracks, null, _now, dislikes), KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now, dislikes) })
            {
                Assert.All(ofOne.Take(count), t => Assert.DoesNotContain(t.Id, profile.Scores.Keys));
                Assert.All(ofOne.Take(count), t => Assert.Contains(t.Id, profile.Dropped));
                // Its other songs weigh less: three songs out, much less, but not out.
                Assert.Equal(noDislikes.Scores[ofOne[^1].Id] * factor, profile.Scores[ofOne[^1].Id], 9);
            }
        }

        var withArtist = DislikeSet([], "artista 0-0");
        var learned = KostvMusicEngine.LearnedProfile(tracks, null, _now, withArtist);
        var rules = new KostvMixRules(new HashSet<Guid>(), withArtist, _now);
        var mixes = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, learned, null, rules);
        Assert.NotEmpty(mixes);
        var byId = tracks.ToDictionary(t => t.Id);
        Assert.All(mixes.SelectMany(m => m.Items), id => Assert.DoesNotContain("Artista 0-0", byId[id].Artists));
        Assert.DoesNotContain(learned.Artists, a => a.Name == "Artista 0-0");
        Assert.DoesNotContain(learned.Background!, a => a.Name == "Artista 0-0");
        Assert.DoesNotContain(learned.Recent!, a => a.Name == "Artista 0-0");
        Assert.DoesNotContain("Artista 0-0", mixes.SelectMany(m => m.Because!));
        Assert.DoesNotContain("Artista 0-0", KostvMusicEngine.Seeds(learned, Guid.NewGuid(), "2026-W47", withArtist));
        // Also when the profile scored it (one worked out before): the seeds leave it out.
        Assert.Contains("Artista 0-0", KostvMusicEngine.Seeds(noDislikes, Guid.NewGuid(), "2026-W47").Concat(noDislikes.Artists.Take(20).Select(a => a.Name)));
        Assert.DoesNotContain("Artista 0-0", KostvMusicEngine.Seeds(noDislikes, Guid.NewGuid(), "2026-W47", withArtist));
        // The mix of the moment, the same.
        var events = SlotListens(tracks.Where(t => t.PlayCount > 0).ToList(), days: 6, perDay: 5, hourUtc: 14);
        var moment = KostvMusicEngine.Moment(Guid.NewGuid(), "2026-11-20", "tarde", events, tracks, learned, _now, Home, rules: rules, learned: true);
        Assert.NotEmpty(moment);
        Assert.All(moment, id => Assert.DoesNotContain("Artista 0-0", byId[id].Artists));
    }

    // ---------------------------------------------------------------- variety and not repeating

    [Fact]
    public void MixesFollowTheRulesOfVarietyAndStartWithTheSafest()
    {
        var tracks = WideLibrary(genres: 2, artists: 14);
        var similar = new Dictionary<string, IReadOnlyList<string>> { ["Artista 0-1"] = ["Artista 0-2"] };
        foreach (var profile in new[] { KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now), KostvMusicEngine.LearnedProfile(tracks, null, _now) })
        {
            var mixes = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, similar, new KostvMixRules(new HashSet<Guid>(), KostvDislikeSet.Empty, _now));
            Assert.Equal(2, mixes.Count);
            var byId = tracks.ToDictionary(t => t.Id);
            foreach (var mix in mixes)
            {
                var items = mix.Items.Select(id => byId[id]).ToList();
                Assert.Equal(KostvMusicEngine.MixSize, items.Count);
                AssertVariety(items, perBlock: true);
                // Three of four known, one new.
                Assert.Equal(38, items.Count(t => t.PlayCount > 0));
                // It starts with the song liked most of the mix.
                Assert.Equal(items.Where(t => t.PlayCount > 0).Max(t => profile.Scores[t.Id]), profile.Scores[items[0].Id]);
                Assert.Equal(3, mix.Because!.Count);
            }
        }
    }

    [Fact]
    public void WhenNothingElseFitsTheRulesGiveWayButNeverTheSameArtistInARow()
    {
        var day = new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc);
        var tracks = Enumerable.Range(0, 30).Select(i => new KostvMusicTrack(Guid.NewGuid(), [i % 2 == 0 ? "Uno" : "Dos"], ["Pop"], 5, day)).ToList();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile));
        var byId = tracks.ToDictionary(t => t.Id);
        Assert.Equal(30, mix.Items.Count);
        Assert.All(mix.Items.Zip(mix.Items.Skip(1)), pair => Assert.NotEqual(byId[pair.First].PrimaryArtist, byId[pair.Second].PrimaryArtist));

        // Two of one album never go one after the other: with one album only, the mix stops.
        var album = Guid.NewGuid();
        var oneAlbum = tracks.Select(t => t with { Album = album }).ToList();
        Assert.Empty(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", oneAlbum, KostvMusicEngine.Profile(oneAlbum, new Dictionary<Guid, KostvTrackListens>(), _now)));
    }

    [Fact]
    public void MixesLeaveOutWhatTheRulesSayAndBringBackForgottenSongs()
    {
        var tracks = WideLibrary(genres: 1, artists: 14, played: 6, unplayed: 4);
        var known = tracks.Where(t => t.PlayCount > 0).ToList();
        var exclude = known.Take(20).Select(t => t.Id).ToHashSet();
        var profile = KostvMusicEngine.Profile(tracks, new Dictionary<Guid, KostvTrackListens>(), _now);
        var mix = Assert.Single(KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, profile, null, new KostvMixRules(exclude, KostvDislikeSet.Empty, _now)));
        Assert.DoesNotContain(mix.Items, exclude.Contains);

        // Liked a lot and unheard for over a month: some of them make it to the first songs.
        var forgotten = known.Where(t => t.PlayCount >= 6).GroupBy(t => t.PrimaryArtist).Select(g => g.First()).ToList();
        var lastHeard = known.ToDictionary(t => t.Id, t => forgotten.Contains(t) ? _now.AddDays(-45) : _now.AddDays(-2));
        var withDates = profile with { LastHeard = lastHeard };
        var first = KostvMusicEngine.Mixes(Guid.NewGuid(), "2026-11-20", tracks, withDates, null, new KostvMixRules(new HashSet<Guid>(), KostvDislikeSet.Empty, _now)).Single().Items.Take(25).ToList();
        Assert.True(first.Count(id => forgotten.Any(t => t.Id == id)) >= 3);
    }

    [Fact]
    public async Task TheDaysMixesDontRepeatTheThreeDaysBeforeNorWhatWasHeardToday()
    {
        var library = MusicLibrary.Made(genres: 2, artists: 12, played: 8, unplayed: 4);
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        var songs = library.Items.OfType<Audio>().Where(s => library.Data[s.Id].Played).Select(s => s.Id).ToList();
        KostvMusicEvent ShownMix(IEnumerable<Guid> ids, DateTimeOffset at) =>
            new KostvMusicEvent { Type = KostvMusicEvent.ShownType, Surface = KostvMusicEvent.MixesSurface, Mixes = [new KostvShownMix { Id = "daily-1", Items = ids.Select(i => i.ToString("N")).ToList() }] }.Stamp(at, Home);
        // Shown two days before, shown five days before, and heard ten hours ago.
        service.Store.Append(userId, ShownMix(songs.Take(15), _now.AddDays(-2)));
        service.Store.Append(userId, ShownMix(songs.Skip(15).Take(15), _now.AddDays(-5)));
        service.Store.Append(userId, Listen(songs[40], _now.AddHours(-10)));

        var items = (await service.MixesAsync(userId, user)).SelectMany(m => m.Items).ToHashSet();
        Assert.DoesNotContain(items, songs.Take(15).Contains);
        Assert.DoesNotContain(songs[40], items);
        Assert.Contains(items, songs.Skip(15).Take(15).Contains);
    }

    // ---------------------------------------------------------------- seeds

    [Fact]
    public void TheSeedsRotateEachWeekAmongTheTwentyLikedMost()
    {
        var day = new DateTime(2026, 11, 19, 0, 0, 0, DateTimeKind.Utc);
        var tracks = Enumerable.Range(0, 30).Select(i => new KostvMusicTrack(Guid.NewGuid(), [$"Artista {i:00}"], ["Pop"], 40 - i, day)).ToList();
        var profile = KostvMusicEngine.LearnedProfile(tracks, null, _now);
        var user = Guid.NewGuid();
        var top = profile.Background!.Take(20).Select(a => a.Name).ToList();
        var weeks = Enumerable.Range(40, 8).Select(w => KostvMusicEngine.Seeds(profile, user, $"2026-W{w}")).ToList();
        Assert.All(weeks, seeds =>
        {
            Assert.Equal(KostvMusicEngine.MaxSeeds, seeds.Count);
            Assert.All(seeds, s => Assert.Contains(s, top));
            // The three liked most, every week.
            Assert.All(top.Take(KostvMusicEngine.FixedSeeds), s => Assert.Contains(s, seeds));
        });
        Assert.True(weeks.Select(s => string.Join(",", s)).Distinct().Count() > 1);
        Assert.True(weeks.SelectMany(s => s).Distinct().Count() > KostvMusicEngine.MaxSeeds);
        // The same all the week.
        Assert.Equal(weeks[0], KostvMusicEngine.Seeds(profile, user, "2026-W40"));
        // Fewer than ten: all of them.
        Assert.Equal(5, KostvMusicEngine.Seeds(KostvMusicEngine.LearnedProfile(tracks.Take(5), null, _now), user, "2026-W40").Count);
    }

    // ---------------------------------------------------------------- a home of four, six months

    private sealed record Person(string Name, int Genre, int ListensPerDay, double Shuffle, double Closes, string? Disliked = null);

    [Fact]
    public void AHomeOfFourOverSixMonthsGetsEachTheirOwnMusic()
    {
        // Six genres, ten artists each with ten songs on two albums.
        var tracks = new List<KostvMusicTrack>();
        for (var g = 0; g < 6; g++)
        {
            for (var a = 0; a < 10; a++)
            {
                var albums = new[] { Guid.NewGuid(), Guid.NewGuid() };
                for (var s = 0; s < 10; s++)
                {
                    tracks.Add(new KostvMusicTrack(Guid.NewGuid(), [$"Artista {g}-{a}"], [$"Género {g}"], Album: albums[s / 5]));
                }
            }
        }

        var people = new[]
        {
            new Person("Ana", 0, 12, 0.1, 0.05, Disliked: "Artista 0-3"),
            new Person("Luis", 1, 20, 0.5, 0.1),
            // A child: a few listens, and the server knowing what they played before.
            new Person("Peque", 2, 1, 0, 0.3),
            new Person("Abuela", 3, 6, 0.8, 0.4)
        };
        var random = new Random(2026);
        foreach (var person in people)
        {
            var userId = Guid.NewGuid();
            var mine = tracks.Where(t => t.Genres[0] == $"Género {person.Genre}").ToList();
            var others = tracks.Where(t => t.Genres[0] != $"Género {person.Genre}").ToList();
            var hated = mine[7];
            // The one they can't stand, skipped as soon as it starts a few times.
            var events = Enumerable.Range(0, 5).Select(i => Heard(hated.Id, _now.AddDays(-170 + i * 30), played: 4, endedBy: KostvListenEnd.Next, source: "radio")).ToList();
            for (var d = 180; d >= 1; d--)
            {
                for (var i = 0; i < person.ListensPerDay; i++)
                {
                    var at = _now.AddDays(-d).AddMinutes(i * 4);
                    var shuffle = random.NextDouble() < person.Shuffle;
                    var ownGenre = random.NextDouble() < 0.8;
                    var song = ownGenre ? mine[(int)(Math.Pow(random.NextDouble(), 2) * mine.Count)] : others[random.Next(others.Count)];
                    if (song == hated || !ownGenre)
                    {
                        // Skipped early: the hated one every time, the rest of genres mostly.
                        events.Add(Heard(song.Id, at, played: random.Next(3, 25), endedBy: KostvListenEnd.Next, source: "mix:daily-1", shuffle: shuffle));
                    }
                    else if (random.NextDouble() < person.Closes)
                    {
                        // The app closed on it, or the session ended: not a skip.
                        events.Add(Heard(song.Id, at, played: random.Next(5, 40), endedBy: KostvListenEnd.Closed, source: "album"));
                    }
                    else
                    {
                        // Heard, half the times faded into the next 12 s before its end.
                        var faded = random.Next(2) == 0;
                        events.Add(Heard(song.Id, at, played: faded ? 188 : 200, endedBy: KostvListenEnd.Natural, source: random.Next(3) == 0 ? "search" : "mix:daily-1", shuffle: shuffle));
                    }
                }

                // The ♥ and the «no me gusta» of one day.
                if (d == 90)
                {
                    events.Add(new KostvMusicEvent { Type = KostvMusicEvent.PlaylistAddType, Items = [mine[1].Id.ToString("N")] }.Stamp(_now.AddDays(-d), Home));
                }
            }

            // What the server counts of their plays (the child played their genre before).
            var library = tracks.Select(t => t.Genres[0] == $"Género {person.Genre}" && person.Name == "Peque" ? t with { PlayCount = 4, LastPlayed = new DateTime(2026, 9, 1, 0, 0, 0, DateTimeKind.Utc) } : t)
                .Select(t => t.Id == mine[2].Id ? t with { Favorite = true } : t)
                .ToList();
            var summary = KostvMusicEngine.Summarize(events, _now);
            var dislikes = person.Disliked != null ? DislikeSet([], person.Disliked) : KostvDislikeSet.Empty;
            var profile = KostvMusicEngine.LearnedProfile(library, summary, _now, dislikes);

            // Their genre first, and how much is learned by how much they listened.
            Assert.Equal($"Género {person.Genre}", profile.Genres[0].Name);
            Assert.Equal(Math.Min(1, events.Count(e => e.Counts) / 300.0), summary.Learned, 9);
            if (person.Name == "Peque")
            {
                Assert.True(summary.Learned < 0.7, $"{summary.Learned}");
            }
            else
            {
                Assert.Equal(1, summary.Learned);
            }

            // The song always skipped is out, unless with a heart; closing the app took nothing.
            Assert.Contains(hated.Id, profile.Dropped);
            Assert.True(profile.Scores[mine[2].Id] >= KostvTasteWeights.Heart);
            Assert.DoesNotContain(profile.Dropped, id => mine.Any(t => t.Id == id) && id != hated.Id && !(person.Disliked != null && library.First(t => t.Id == id).Artists.Contains(person.Disliked)));

            var rules = new KostvMixRules(new HashSet<Guid>(), dislikes, _now);
            var mixes = KostvMusicEngine.Mixes(userId, "2026-11-20", library, profile, null, rules);
            Assert.NotEmpty(mixes);
            Assert.Equal($"Género {person.Genre}", mixes[0].Genre);
            var byId = library.ToDictionary(t => t.Id);
            foreach (var mix in mixes)
            {
                AssertVariety(mix.Items.Select(id => byId[id]).ToList());
                Assert.DoesNotContain(hated.Id, mix.Items);
                if (person.Disliked != null)
                {
                    Assert.All(mix.Items, id => Assert.DoesNotContain(person.Disliked, byId[id].Artists));
                }
            }

            var seeds = KostvMusicEngine.Seeds(profile, userId, "2026-W47", dislikes);
            Assert.All(seeds.Take(3), s => Assert.StartsWith($"Artista {person.Genre}-", s));
            if (person.Disliked != null)
            {
                Assert.DoesNotContain(person.Disliked, seeds);
            }
        }
    }

    // ---------------------------------------------------------------- the store: taste, «no me gusta», comparisons

    [Fact]
    public void TheTasteIsKeptUpToDateAsListensAreNotedAndGoesWithThem()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        var song = Guid.NewGuid();
        store.Append(user, Listen(song, _now.AddDays(-1)));
        var folder = Path.Combine(_root, user.ToString("N"));
        Assert.False(File.Exists(Path.Combine(folder, "taste.json")));

        // Worked out the first time it is asked, then brought up to date as each line is noted.
        Assert.Equal(1, store.Taste(user).Listens);
        Assert.True(File.Exists(Path.Combine(folder, "taste.json")));
        store.Append(user, Listen(song, _now));
        store.Append(user, new KostvMusicEvent { Type = KostvMusicEvent.PlaylistAddType, Items = [song.ToString("N")] }.Stamp(_now, Home));
        // Written when the server stops (or later on), not with each line.
        store.FlushTastes();
        var restarted = NewStore();
        var taste = restarted.Taste(user);
        Assert.Equal(2, taste.Listens);
        Assert.True(taste.SongOf(song)!.Playlist);
        Assert.Equal(KostvMusicEngine.Summarize(restarted.Read(user), _now).SongOf(song)!.LongAt(_now), taste.SongOf(song)!.LongAt(_now), 9);

        // «No me gusta» stays when the listens go; the taste and the comparisons go with them.
        restarted.AddDislikes(user, [new KostvDislikedSong { Id = song.ToString("N"), At = _now }], []);
        File.WriteAllText(Path.Combine(folder, "compare.jsonl"), "{\"day\":\"2026-11-19\",\"hitsOld\":1,\"hitsNew\":2}\n");
        restarted.DeleteListens(user);
        Assert.False(File.Exists(Path.Combine(folder, "taste.json")));
        Assert.False(File.Exists(Path.Combine(folder, "compare.jsonl")));
        Assert.True(File.Exists(Path.Combine(folder, "dislikes.json")));
        Assert.Equal(0, restarted.Taste(user).Listens);
        Assert.Single(NewStore().DislikesOf(user).Songs);

        // Deleting the user: nothing left.
        restarted.DeleteUser(user);
        Assert.False(Directory.Exists(folder));
        Assert.Empty(restarted.DislikesOf(user).Songs);
    }

    [Fact]
    public void TheDailyRoundWorksTheTastesOutAgainAndTrimsTheComparisons()
    {
        var store = NewStore();
        var user = Guid.NewGuid();
        store.Append(user, Listen(Guid.NewGuid(), _now));
        Assert.Equal(1, store.Taste(user).Listens);
        // A line written by hand, say: the summary only knows once worked out again.
        File.AppendAllText(Path.Combine(_root, user.ToString("N"), "2026-11.jsonl"), JsonSerializer.Serialize(Listen(Guid.NewGuid(), _now), KostvMusicStore.LineOptions) + "\n");
        Assert.Equal(1, store.Taste(user).Listens);
        Assert.Equal(1, store.RecomputeTastes());
        Assert.Equal(2, store.Taste(user).Listens);

        // Off: not worked out.
        var off = Guid.NewGuid();
        store.Append(off, Listen(Guid.NewGuid(), _now));
        store.SetLearn(off, false);
        Assert.Equal(1, store.RecomputeTastes());

        // Comparisons past the two years go, as the listens do.
        File.WriteAllText(Path.Combine(_root, user.ToString("N"), "compare.jsonl"), "{\"day\":\"2024-09-30\",\"hitsOld\":1,\"hitsNew\":2}\n{\"day\":\"2026-11-19\",\"hitsOld\":3,\"hitsNew\":4}\n");
        store.Trim(user);
        Assert.Equal(["2026-11-19"], store.Comparisons(user).Select(c => c.Day));
    }

    // ---------------------------------------------------------------- the routes

    private (KostvMusicService Service, KostvMusicController Controller, MusicLibrary Library) Routes(Guid userId, MusicLibrary? library = null)
    {
        library ??= MusicLibrary.Made(genres: 2, artists: 12, played: 6, unplayed: 4);
        var service = NewService(library);
        return (service, Controller(service, userId), library);
    }

    private static JsonElement Json(IActionResult result) => JsonSerializer.SerializeToElement(Assert.IsType<OkObjectResult>(result).Value);

    [Fact]
    public void DislikesAreKeptApartAlsoWithLearnOffAndCanBeUndone()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var songs = library.Items.OfType<Audio>().Take(3).ToList();
        var artist = library.Items.OfType<MusicArtist>().First(a => a.Name == "Artista 1-4");
        service.Store.SetLearn(userId, false);

        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { songs[0].Id.ToString() } })));
        _now = _now.AddMinutes(1);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { songs[1].Id.ToString("N") }, Kind = "song" })));
        _now = _now.AddMinutes(1);
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString() }, Kind = "ARTIST" })));
        Assert.Empty(service.Store.Read(userId));

        var list = Json(controller.GetDislikes());
        var listed = list.GetProperty("Songs").EnumerateArray().ToList();
        // The latest first, with what is needed to show them.
        Assert.Equal([songs[1].Id, songs[0].Id], listed.Select(s => s.GetProperty("Id").GetGuid()));
        Assert.Equal(songs[1].Name, listed[0].GetProperty("Name").GetString());
        Assert.Equal(songs[1].Artists[0], listed[0].GetProperty("Artist").GetString());
        var artistId = library.Items.OfType<MusicArtist>().First(a => a.Name == songs[1].Artists[0]).Id;
        Assert.Equal(artistId, listed[0].GetProperty("ArtistId").GetGuid());
        Assert.Equal(_now.AddMinutes(-1).UtcDateTime, listed[0].GetProperty("At").GetDateTime());
        var artists = list.GetProperty("Artists").EnumerateArray().ToList();
        Assert.Equal(("Artista 1-4", artist.Id), (artists[0].GetProperty("Name").GetString(), artists[0].GetProperty("Id").GetGuid()));

        // Gone from the library: still shown, with the name kept.
        library.Items.Remove(songs[0]);
        Assert.Equal(songs[0].Name, Json(controller.GetDislikes()).GetProperty("Songs")[1].GetProperty("Name").GetString());

        // Deleting the listens leaves them; undoing one, or one that wasn't there, is fine.
        service.Store.SetLearn(userId, true);
        Assert.IsType<NoContentResult>(controller.DeleteListens());
        Assert.Equal(2, Json(controller.GetDislikes()).GetProperty("Songs").GetArrayLength());
        Assert.IsType<NoContentResult>(controller.RemoveDislike(songs[1].Id.ToString()));
        Assert.IsType<NoContentResult>(controller.RemoveDislike(Guid.NewGuid().ToString()));
        Assert.IsType<BadRequestObjectResult>(controller.RemoveDislike("no es un id"));
        Assert.Equal(1, Json(controller.GetDislikes()).GetProperty("Songs").GetArrayLength());
        Assert.IsType<NoContentResult>(controller.RemoveDislike(artist.Id.ToString("N")));
        Assert.Equal(0, Json(controller.GetDislikes()).GetProperty("Artists").GetArrayLength());
        Assert.IsType<NoContentResult>(controller.ClearDislikes());
        Assert.Equal(0, Json(controller.GetDislikes()).GetProperty("Songs").GetArrayLength());
    }

    [Fact]
    public async Task ADislikeIsOutOfTheDaysMusicAtOnce()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId);
        var user = new User("ana", "auth", "reset");
        var mixes = await service.MixesAsync(userId, user);
        var song = mixes[0].Items[0];
        var artistName = library.Items.OfType<Audio>().First(s => s.Id == mixes[0].Items[1]).Artists[0];
        var artist = library.Items.OfType<MusicArtist>().First(a => a.Name == artistName);

        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { song.ToString() } })));
        Assert.IsType<NoContentResult>(controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artist.Id.ToString() }, Kind = "artist" })));
        // What was kept for the day is filtered as it is served.
        var dislikes = service.DislikeSetOf(userId);
        Assert.True(KostvMusicService.Blocks(dislikes, library.Items.First(i => i.Id == song)));
        Assert.True(KostvMusicService.Blocks(dislikes, library.Items.OfType<Audio>().First(s => s.Artists.Contains(artistName))));
        // And the day's music is made again without them.
        var again = (await service.MixesAsync(userId, user)).SelectMany(m => m.Items).ToList();
        Assert.DoesNotContain(song, again);
        Assert.DoesNotContain(again, id => library.Items.OfType<Audio>().First(s => s.Id == id).Artists.Contains(artistName));
        Assert.All(await service.MixesAsync(userId, user), m => Assert.DoesNotContain(artistName, m.Because!));
        Assert.DoesNotContain(artistName, await service.SeedsAsync(userId, user));

        // Undone: back again.
        Assert.IsType<NoContentResult>(controller.RemoveDislike(artist.Id.ToString()));
        Assert.Contains((await service.MixesAsync(userId, user)).SelectMany(m => m.Items), id => library.Items.OfType<Audio>().First(s => s.Id == id).Artists.Contains(artistName));
    }

    [Fact]
    public async Task TheTasteRouteGivesTheTasteWithoutDislikedArtists()
    {
        var userId = Guid.NewGuid();
        var (service, controller, library) = Routes(userId, MusicLibrary.Made(genres: 3, artists: 10, played: 4, unplayed: 2));
        var taste = Json(await controller.GetTaste());
        Assert.Equal(0, taste.GetProperty("Learned").GetDouble());
        var artists = taste.GetProperty("Artists").EnumerateArray().ToList();
        Assert.Equal(KostvMusicService.TasteArtists, artists.Count);
        Assert.All(artists, a => Assert.Equal(library.Items.OfType<MusicArtist>().First(x => x.Name == a.GetProperty("Name").GetString()).Id, a.GetProperty("Id").GetGuid()));
        Assert.True(artists[0].GetProperty("Score").GetDouble() >= artists[^1].GetProperty("Score").GetDouble());
        Assert.Equal(KostvMusicService.TasteArtists, taste.GetProperty("Recent").GetArrayLength());
        Assert.Equal(["Género 0", "Género 1", "Género 2"], taste.GetProperty("Genres").EnumerateArray().Select(g => g.GetProperty("Name").GetString()));

        var top = artists[0].GetProperty("Name").GetString()!;
        controller.AddEvent(Body(new { Type = "dislike", ItemIds = new[] { artists[0].GetProperty("Id").GetGuid() }, Kind = "artist" }));
        taste = Json(await controller.GetTaste());
        Assert.DoesNotContain(top, taste.GetProperty("Artists").EnumerateArray().Select(a => a.GetProperty("Name").GetString()));
        Assert.DoesNotContain(top, taste.GetProperty("Recent").EnumerateArray().Select(a => a.GetProperty("Name").GetString()));

        // With listens, part of it is learned (the next day's taste).
        var song = library.Items.OfType<Audio>().First();
        for (var i = 0; i < 60; i++)
        {
            service.Store.Append(userId, Listen(song.Id, _now.AddMinutes(-i * 5)));
        }

        _now = _now.AddDays(1);
        Assert.Equal(0.2, Json(await controller.GetTaste()).GetProperty("Learned").GetDouble(), 3);
    }

    [Fact]
    public async Task TheNewRoutesNeedTheCallersSession()
    {
        var service = new KostvMusicService(null!, null!, NewStore(), NullLogger<KostvMusicService>.Instance);
        var controller = new KostvMusicController(service, new KostvMusicContext(), null!)
        {
            ControllerContext = new ControllerContext { HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext() }
        };
        Assert.IsType<UnauthorizedObjectResult>(controller.GetDislikes());
        Assert.IsType<UnauthorizedObjectResult>(controller.RemoveDislike(Guid.NewGuid().ToString()));
        Assert.IsType<UnauthorizedObjectResult>(controller.ClearDislikes());
        Assert.IsType<UnauthorizedObjectResult>(await controller.GetTaste());
        foreach (var name in new[] { nameof(KostvMusicController.GetDislikes), nameof(KostvMusicController.RemoveDislike), nameof(KostvMusicController.ClearDislikes), nameof(KostvMusicController.GetTaste) })
        {
            Assert.Contains(typeof(KostvMusicController).GetMethod(name)!.GetCustomAttributes(true), a => a is Microsoft.AspNetCore.Authorization.AuthorizeAttribute);
        }
    }

    // ---------------------------------------------------------------- the engine chosen, and the other compared

    [Fact]
    public void TheEngineIsTheSettingAndTheCurrentOneByDefault()
    {
        var day = new DateOnly(2026, 11, 20);
        Assert.Equal(KostvMusicEngineMode.Current, new PluginConfiguration().KostvMusicEngine);
        Assert.False(KostvMusicEngineMode.UsesNew(null, day));
        Assert.False(KostvMusicEngineMode.UsesNew("cualquiera", day));
        Assert.False(KostvMusicEngineMode.UsesNew("actual", day));
        Assert.True(KostvMusicEngineMode.UsesNew(" Nuevo ", day));
        // One day each, also across the end of a month.
        var alternate = Enumerable.Range(0, 6).Select(i => KostvMusicEngineMode.UsesNew("alterno", new DateOnly(2026, 10, 29).AddDays(i))).ToList();
        Assert.Equal(3, alternate.Count(u => u));
        Assert.All(alternate.Zip(alternate.Skip(1)), pair => Assert.NotEqual(pair.First, pair.Second));
    }

    [Fact]
    public async Task TheOtherEngineIsWorkedOutToCompareWithWhatIsHeardTheNextDay()
    {
        var library = MusicLibrary.Made(genres: 2, artists: 12, played: 6, unplayed: 4);
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        var first = await service.MixesAsync(userId, user);
        var shadowPath = Path.Combine(_root, userId.ToString("N"), "shadow.json");
        var shadow = JsonSerializer.Deserialize<KostvMusicStore.KostvShadow>(File.ReadAllText(shadowPath), KostvMusicStore.LineOptions)!;
        Assert.Equal(("2026-11-20", "actual"), (shadow.Day, shadow.Engine));
        Assert.Equal(KostvMusicEngine.TopCompared, shadow.Old.Count);
        Assert.Equal(KostvMusicEngine.TopCompared, shadow.New.Count);
        // In «actual» the mixes shown are the current engine's.
        Assert.Equal(KostvMusicEngine.Top(first), shadow.Old);

        // That day some of both are heard whole, and some skipped.
        var heard = shadow.Old.Take(4).Concat(shadow.New.Skip(10).Take(3)).Distinct().ToList();
        foreach (var (id, i) in heard.Select((id, i) => (id, i)))
        {
            service.Store.Append(userId, Listen(id, _now.AddMinutes(10 + i * 4)));
        }

        service.Store.Append(userId, Listen(shadow.New[0], _now.AddMinutes(60), KostvListenOutcome.Skipped));
        // Heard the day after: not of that day.
        service.Store.Append(userId, Listen(shadow.New[1], _now.AddDays(1)));
        Assert.Empty(service.Store.Comparisons(userId));

        _now = _now.AddDays(1).AddHours(2);
        service.EngineModeOf = () => "nuevo";
        await service.MixesAsync(userId, user);
        var comparison = Assert.Single(service.Store.Comparisons(userId));
        Assert.Equal(("2026-11-20", "actual"), (comparison.Day, comparison.Engine));
        Assert.Equal(heard.Count(shadow.Old.Contains), comparison.HitsOld);
        Assert.Equal(heard.Count(shadow.New.Contains), comparison.HitsNew);
        shadow = JsonSerializer.Deserialize<KostvMusicStore.KostvShadow>(File.ReadAllText(shadowPath), KostvMusicStore.LineOptions)!;
        Assert.Equal(("2026-11-21", "nuevo"), (shadow.Day, shadow.Engine));

        // Again the same day: compared once.
        service.Forget(userId);
        await service.MixesAsync(userId, user);
        Assert.Single(service.Store.Comparisons(userId));

        // With Learn off, nothing compared.
        var off = Guid.NewGuid();
        service.Store.SetLearn(off, false);
        await service.MixesAsync(off, user);
        Assert.False(File.Exists(Path.Combine(_root, off.ToString("N"), "shadow.json")));
    }

    [Fact]
    public async Task TheMixOfTheMomentSaysWhoItIsMadeOf()
    {
        var library = MusicLibrary.Made();
        var userId = Guid.NewGuid();
        var user = new User("ana", "auth", "reset");
        var service = NewService(library);
        service.EngineModeOf = () => "nuevo";
        var mornings = library.Items.OfType<Audio>().Where(s => s.Genres[0] == "Género 0" && library.Data[s.Id].Played).Take(20).ToList();
        for (var d = 1; d <= 6; d++)
        {
            for (var i = 0; i < 5; i++)
            {
                service.Store.Append(userId, Listen(mornings[(d * 5 + i) % mornings.Count].Id, new DateTimeOffset(2026, 11, 20 - d, 8, i * 4, 0, TimeSpan.Zero)));
            }
        }

        var moment = await service.MomentAsync(userId, user);
        Assert.True(moment.Ready);
        Assert.Equal(3, moment.Because!.Count);
        Assert.All(moment.Because, name => Assert.StartsWith("Artista 0-", name));
        var byId = library.Items.OfType<Audio>().ToDictionary(s => s.Id, s => new KostvMusicTrack(s.Id, s.Artists, s.Genres));
        AssertVariety(moment.Items.Select(id => byId[id]).ToList());
    }
}
