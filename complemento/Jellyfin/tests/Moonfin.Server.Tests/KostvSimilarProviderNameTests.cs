using MediaBrowser.Controller.Library;
using Microsoft.Extensions.Logging.Abstractions;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// Kos TV: the similar items provider's dashboard name, and the move of libraries saved under the
/// old one. The library half only runs on Jellyfin 12; these run against 10.10, so its options
/// are stood in for by a class with the same two properties.
/// </summary>
public sealed class KostvSimilarProviderNameTests
{
    private const string Old = "Moonfin Recommends";

    [Fact]
    public void TheDashboardNameIsKosTv()
    {
        Assert.Equal("kOS TV", KostvSimilarProviderName.Current);
        Assert.DoesNotContain("Moonfin", KostvSimilarProviderName.Current, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheOldNameIsSwappedInTheSamePlace()
    {
        Assert.Equal(
            new[] { "TheMovieDb", "kOS TV", "Jellyfin" },
            KostvSimilarProviderName.Renamed(["TheMovieDb", Old, "Jellyfin"]));
        Assert.Equal(new[] { "kOS TV" }, KostvSimilarProviderName.Renamed(["moonfin recommends"]));
    }

    [Fact]
    public void NothingToRenameGivesNull()
    {
        Assert.Null(KostvSimilarProviderName.Renamed(null));
        Assert.Null(KostvSimilarProviderName.Renamed([]));
        Assert.Null(KostvSimilarProviderName.Renamed(["kOS TV", "TheMovieDb"]));
    }

    [Fact]
    public void WithBothNamesTheOldOneIsDropped()
    {
        Assert.Equal(
            new[] { "kOS TV", "TheMovieDb" },
            KostvSimilarProviderName.Renamed(["kOS TV", Old, "TheMovieDb"]));
        // The new name keeps the place it was given.
        Assert.Equal(
            new[] { "TheMovieDb", "kOS TV" },
            KostvSimilarProviderName.Renamed([Old, "TheMovieDb", "kOS TV", Old]));
    }

    [Fact]
    public void BothListsOfATypeAreRenamedAndOnlyOnce()
    {
        var options = new TypeOptions12
        {
            SimilarItemProviders = [Old, "TheMovieDb"],
            SimilarItemProviderOrder = ["TheMovieDb", Old],
        };

        Assert.True(KostvSimilarProviderName.RenameIn(options));
        Assert.Equal(new[] { "kOS TV", "TheMovieDb" }, options.SimilarItemProviders);
        Assert.Equal(new[] { "TheMovieDb", "kOS TV" }, options.SimilarItemProviderOrder);

        // Every start runs it again; once moved it leaves the options alone.
        Assert.False(KostvSimilarProviderName.RenameIn(options));
        Assert.Equal(new[] { "TheMovieDb", "kOS TV" }, options.SimilarItemProviderOrder);
    }

    [Fact]
    public void AnEmptyOrderIsLeftEmpty()
    {
        var options = new TypeOptions12 { SimilarItemProviders = [Old], SimilarItemProviderOrder = [] };

        Assert.True(KostvSimilarProviderName.RenameIn(options));
        Assert.Equal(new[] { "kOS TV" }, options.SimilarItemProviders);
        Assert.Empty(options.SimilarItemProviderOrder);
    }

    [Fact]
    public void OptionsWithoutTheListsAreLeftAlone()
    {
        Assert.False(KostvSimilarProviderName.RenameIn(null));
        Assert.False(KostvSimilarProviderName.RenameIn(new MediaBrowser.Model.Configuration.TypeOptions()));
        Assert.False(KostvSimilarProviderName.RenameIn(new { SimilarItemProviders = new[] { Old } }));
    }

    [Fact]
    public void BeforeJellyfin12TheLibrariesAreNotEvenRead()
    {
        var library = RecordingHostProxy.Create<ILibraryManager>((method, _) => throw new NotSupportedException(method.Name));

        Assert.Equal(0, KostvSimilarProviderName.RenameInLibraries(library, NullLogger.Instance));
    }

    private sealed class TypeOptions12
    {
        public string[] SimilarItemProviders { get; set; } = [];

        public string[] SimilarItemProviderOrder { get; set; } = [];
    }
}
