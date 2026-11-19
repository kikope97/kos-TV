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
    public void WhatGoesMissingStaysAWhileAndComesBack()
    {
        var list = NewList();
        var ana = Guid.NewGuid();
        var start = DateTimeOffset.UtcNow;
        list.Add(ana, "a", "movie:1");
        list.Add(ana, "b", "tv:2");

        // A file being replaced: missing now, still on the list.
        Assert.True(list.Sweep(ana, ["a"], ["b"], start));
        Assert.Equal(["b", "a"], list.For(ana).Select(e => e.ItemId));
        Assert.Equal(start, list.For(ana).Single(e => e.ItemId == "a").MissingSince);

        // Still missing a day later: nothing new to write, it stays.
        Assert.False(list.Sweep(ana, ["a"], ["b"], start.AddDays(1)));
        Assert.Equal(start, list.For(ana).Single(e => e.ItemId == "a").MissingSince);

        // Back on the server: no longer missing.
        Assert.True(list.Sweep(ana, [], ["a", "b"], start.AddDays(2)));
        Assert.Null(list.For(ana).Single(e => e.ItemId == "a").MissingSince);
    }

    [Fact]
    public void WhatStaysMissingLeavesAfterTheGrace()
    {
        var list = NewList();
        var ana = Guid.NewGuid();
        var start = DateTimeOffset.UtcNow;
        list.Add(ana, "a", "movie:1");

        list.Sweep(ana, ["a"], [], start);
        Assert.Single(list.For(ana));
        Assert.True(list.Sweep(ana, ["a"], [], start + KostvMyList.MissingGrace));
        Assert.Empty(list.For(ana));
    }

    [Fact]
    public void FoundAgainByItsTitleIsNoLongerMissing()
    {
        var list = NewList();
        var ana = Guid.NewGuid();
        list.Add(ana, "a", "movie:1");
        list.Sweep(ana, ["a"], [], DateTimeOffset.UtcNow);

        Assert.True(list.Repoint(ana, "a", "a2"));
        var entry = list.For(ana).Single();
        Assert.Equal("a2", entry.ItemId);
        Assert.Null(entry.MissingSince);
    }

    [Fact]
    public void TakingOffWhatIsntThereIsNothing()
    {
        var list = NewList();
        Assert.Equal(0, list.Remove(Guid.NewGuid(), ["x"]));
    }
}
