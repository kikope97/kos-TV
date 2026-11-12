using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: each person's list of what they want to watch.</summary>
public sealed class KostvMyListTests
{
    private static KostvMyList NewList() => new(NullLogger<KostvMyList>.Instance);

    [Fact]
    public void EachPersonHasTheirOwnTheNewestFirst()
    {
        var list = NewList();
        var ana = Guid.NewGuid();
        var luis = Guid.NewGuid();

        Assert.True(list.Add(ana, "a", "movie:1"));
        Assert.True(list.Add(ana, "b", "tv:2"));
        Assert.False(list.Add(ana, "a", "movie:1"));
        list.Add(luis, "c", null);

        Assert.Equal(["b", "a"], list.For(ana).Select(e => e.ItemId));
        Assert.Equal(["c"], list.For(luis).Select(e => e.ItemId));
    }

    [Fact]
    public void WhatArrivedGoesOnByItselfOnlyOnce()
    {
        var list = NewList();
        var ana = Guid.NewGuid();

        Assert.True(list.Add(ana, "a", "movie:1", arrived: true));
        Assert.Equal(1, list.Remove(ana, ["a"]));

        // Taken off: arriving again, or another device telling it arrived, doesn't put it back.
        Assert.False(list.Add(ana, "a", "movie:1", arrived: true));
        Assert.Empty(list.For(ana));

        // By hand it goes back on.
        Assert.True(list.Add(ana, "a", "movie:1"));
    }

    [Fact]
    public void TakingOffWhatIsntThereIsNothing()
    {
        var list = NewList();
        Assert.Equal(0, list.Remove(Guid.NewGuid(), ["x"]));
    }
}
