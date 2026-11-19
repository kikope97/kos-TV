using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: which collections hold an item, from their linked children.</summary>
public sealed class KostvCollectionsTests
{
    [Fact]
    public void ACollectionHoldsItsOwnMembersById()
    {
        var film = Guid.NewGuid();
        var other = Guid.NewGuid();
        (Guid?, string?)[] children = [(other, "/films/b.mkv"), (film, "/films/a.mkv")];

        Assert.True(KostvCollectionMembership.Holds(children, film, "/films/a.mkv"));
        Assert.False(KostvCollectionMembership.Holds(children, Guid.NewGuid(), "/films/c.mkv"));
    }

    [Fact]
    public void AChildKnownOnlyByItsFileIsMatchedByPath()
    {
        var film = Guid.NewGuid();
        (Guid?, string?)[] children = [(null, "/Films/A.mkv")];

        Assert.True(KostvCollectionMembership.Holds(children, film, "/films/a.mkv"));
        Assert.False(KostvCollectionMembership.Holds(children, film, null));
    }

    [Fact]
    public void AChildWithAnIdIsNotMatchedByPath()
    {
        // The id says which item it is, so the same path of a replaced file doesn't count.
        var film = Guid.NewGuid();
        (Guid?, string?)[] children = [(Guid.NewGuid(), "/films/a.mkv")];

        Assert.False(KostvCollectionMembership.Holds(children, film, "/films/a.mkv"));
    }

    [Fact]
    public void AnEmptyCollectionHoldsNothing()
    {
        Assert.False(KostvCollectionMembership.Holds([], Guid.NewGuid(), "/films/a.mkv"));
    }
}
