using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Api;
using Moonfin.Server.Kostv;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: what the plugin keeps on disk stays whole and doesn't grow without end.</summary>
public sealed class KostvStoresTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-stores-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    [Fact]
    public async Task ACollectionsOrderCutShortIsReadFromItsCopy()
    {
        var store = new CollectionOrderService(_root);
        var userId = Guid.NewGuid();
        var collection = Guid.NewGuid().ToString("N");

        await store.SaveAsync(userId, collection, ["a", "b"], CancellationToken.None);
        await store.SaveAsync(userId, collection, ["b", "a", "b", " "], CancellationToken.None);
        Assert.Equal(["b", "a"], await store.GetAsync(userId, collection, CancellationToken.None));

        // A crash left the file half written: the copy from before is read.
        var path = Path.Combine(_root, userId.ToString("N"), collection + ".json");
        await File.WriteAllTextAsync(path, "[\"b\", \"a");
        Assert.Equal(["a", "b"], await store.GetAsync(userId, collection, CancellationToken.None));

        // Emptied: gone, copies too.
        await store.SaveAsync(userId, collection, [], CancellationToken.None);
        Assert.Empty(await store.GetAsync(userId, collection, CancellationToken.None));
        Assert.False(File.Exists(path + ".bak"));
    }

    [Theory]
    [InlineData("---", false)]
    [InlineData("", false)]
    [InlineData("0123456789abcdef0123456789abcdef", true)]
    [InlineData("01234567-89ab-cdef-0123-456789abcdef", true)]
    public void ACollectionIdWithoutLettersOrDigitsIsNotValid(string id, bool valid)
    {
        Assert.Equal(valid, new CollectionOrderService(_root).IsValidId(Guid.NewGuid(), id));
    }

    [Fact]
    public async Task OnlyOrdersOfCollectionsLongGoneAreForgotten()
    {
        var store = new CollectionOrderService(_root);
        var userId = Guid.NewGuid();
        var gone = Guid.NewGuid();
        var goneLately = Guid.NewGuid();
        var there = Guid.NewGuid();
        foreach (var id in new[] { gone, goneLately, there })
        {
            await store.SaveAsync(userId, id.ToString("N"), ["x"], CancellationToken.None);
        }

        var folder = Path.Combine(_root, userId.ToString("N"));
        var old = DateTime.UtcNow - CollectionOrderService.OrphanAfter - TimeSpan.FromDays(1);
        File.SetLastWriteTimeUtc(Path.Combine(folder, gone.ToString("N") + ".json"), old);
        File.SetLastWriteTimeUtc(Path.Combine(folder, there.ToString("N") + ".json"), old);

        var removed = await store.PruneAsync(userId, id => id == there, CancellationToken.None);

        Assert.Equal(1, removed);
        Assert.Empty(await store.GetAsync(userId, gone.ToString("N"), CancellationToken.None));
        Assert.Equal(["x"], await store.GetAsync(userId, goneLately.ToString("N"), CancellationToken.None));
        Assert.Equal(["x"], await store.GetAsync(userId, there.ToString("N"), CancellationToken.None));
    }

    [Fact]
    public void WhatArrivedIsRememberedForTheLatestOnly()
    {
        var list = new KostvMyList(NullLogger<KostvMyList>.Instance);
        var userId = Guid.NewGuid();
        for (var i = 0; i < KostvMyList.MaxArrived + 5; i++)
        {
            list.Add(userId, "i" + i, "movie:" + i, arrived: true);
        }

        // The latest are still remembered: taken off, they don't go back on by themselves.
        var last = KostvMyList.MaxArrived + 4;
        list.Remove(userId, ["i" + last]);
        Assert.False(list.Add(userId, "i" + last, "movie:" + last, arrived: true));
    }

    [Fact]
    public void TheDatesOfFavouritesGoneALongWhileAreForgotten()
    {
        var dates = new KostvFavoriteDates(NullLogger<KostvFavoriteDates>.Instance);
        var userId = Guid.NewGuid();
        var kept = Guid.NewGuid();
        var deleted = Guid.NewGuid();
        var now = DateTimeOffset.UtcNow;
        dates.Mark(userId, kept, true, now);
        dates.Mark(userId, deleted, true, now);
        var deletedId = deleted.ToString("N");

        // Missing at one look and back at the next: kept.
        Assert.True(dates.Sweep(userId, new HashSet<string> { deletedId }, now));
        Assert.True(dates.Sweep(userId, new HashSet<string>(), now + TimeSpan.FromDays(1)));
        Assert.Contains(deletedId, dates.Since(userId).Keys);

        // Missing all along: let go of once the grace is over.
        dates.Sweep(userId, new HashSet<string> { deletedId }, now);
        dates.Sweep(userId, new HashSet<string> { deletedId }, now + TimeSpan.FromDays(5));
        Assert.Contains(deletedId, dates.Since(userId).Keys);
        dates.Sweep(userId, new HashSet<string> { deletedId }, now + KostvFavoriteDates.GoneGrace);
        Assert.Equal([kept.ToString("N")], dates.Since(userId).Keys);
        Assert.Equal([kept.ToString("N")], dates.Noted(userId));
    }

    [Theory]
    [InlineData(null, "es-ES")]
    [InlineData("", "es-ES")]
    [InlineData("en", "en")]
    [InlineData("en-US", "en-US")]
    [InlineData(" es-ES ", "es-ES")]
    [InlineData("español", "es-ES")]
    public void TheNextEpisodeIsAskedInTheAppsLanguageOrSpanish(string? asked, string expected)
    {
        Assert.Equal(expected, TmdbController.NextEpisodeLanguage(asked));
    }
}
