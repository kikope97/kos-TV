using System.Reflection;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Model.Entities;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// Pins the trimmed card shape the browse and seasonal endpoints return, without standing up
/// Jellyfin's service graph, the same way GamesControllerArtworkContractTests does.
/// </summary>
public sealed class MoonfinControllerCardContractTests
{
    private static ItemCardDtoMapper Mapper() => new(null!, new NoOpLogger<ItemCardDtoMapper>());

    // Clients read UserData.Played for the watched checkmark and PlaybackPositionTicks for the
    // resume bar, so dropping the key makes every card these endpoints return look unwatched.
    [Fact]
    public void Map_CarriesUserDataSoCardsCanShowPlayedState()
    {
        var dto = Mapper().Map(new Movie { Name = "Seed" }, null);

        var userData = dto.GetType().GetProperty("UserData");
        Assert.NotNull(userData);

        // With no user to resolve the key is still present and simply carries nothing, so a client
        // reads "unknown" rather than a confident "unwatched".
        Assert.Null(userData.GetValue(dto));
    }

    // The seasonal row's owned titles carry the rating the server holds, so a client can apply
    // its own blocked list to them like any library card.
    [Fact]
    public void Map_CarriesTheOfficialRating()
    {
        var dto = Mapper().Map(new Movie { Name = "Seed", OfficialRating = "PG-13" }, null);

        Assert.Equal("PG-13", dto.GetType().GetProperty("OfficialRating")?.GetValue(dto));
    }

    // Kos TV: an episode's card says where it belongs (T1:E6 and its series), or the app's
    // news of favourite series and the hearts on «Episodios nuevos» have nothing to go on.
    [Fact]
    public void Map_CarriesWhereAnEpisodeBelongs()
    {
        var seriesId = Guid.NewGuid();
        var seasonId = Guid.NewGuid();
        var dto = Mapper().Map(
            new MediaBrowser.Controller.Entities.TV.Episode
            {
                Name = "Piloto",
                IndexNumber = 6,
                ParentIndexNumber = 1,
                SeriesId = seriesId,
                SeasonId = seasonId,
                SeriesName = "Serie",
            },
            null);

        object? Field(string name) => dto.GetType().GetProperty(name)?.GetValue(dto);
        Assert.Equal(6, Field("IndexNumber"));
        Assert.Equal(1, Field("ParentIndexNumber"));
        Assert.Equal(seriesId, Field("SeriesId"));
        Assert.Equal(seasonId, Field("SeasonId"));
        Assert.Equal("Serie", Field("SeriesName"));
    }

    [Fact]
    public void Map_CarriesASongsArtists()
    {
        var dto = Mapper().Map(
            new MediaBrowser.Controller.Entities.Audio.Audio
            {
                Name = "Canción",
                Artists = ["Ana"],
                AlbumArtists = ["Ana y Luis"],
            },
            null);

        Assert.Equal("Ana y Luis", dto.GetType().GetProperty("AlbumArtist")?.GetValue(dto));
        Assert.Equal(new[] { "Ana" }, dto.GetType().GetProperty("Artists")?.GetValue(dto) as IEnumerable<string>);
        // A film has none of it.
        var film = Mapper().Map(new Movie { Name = "Seed" }, null);
        Assert.Null(film.GetType().GetProperty("SeriesId")?.GetValue(film));
    }

    // Kos TV: the media bar reads the TMDB id (for the extra ratings) and the trailers from the
    // card, instead of asking for the whole item again.
    [Fact]
    public void Map_CarriesTheProviderIdsAndTrailers()
    {
        var movie = new Movie { Name = "Seed" };
        movie.SetProviderId(MediaBrowser.Model.Entities.MetadataProvider.Tmdb, "550");
        movie.RemoteTrailers = [new MediaBrowser.Model.Entities.MediaUrl { Url = "https://example.com/t", Name = "Tráiler" }];

        var dto = Mapper().Map(movie, null);

        var ids = dto.GetType().GetProperty("ProviderIds")?.GetValue(dto) as IReadOnlyDictionary<string, string>;
        Assert.Equal("550", ids?["Tmdb"]);
        using var trailers = System.Text.Json.JsonDocument.Parse(
            System.Text.Json.JsonSerializer.Serialize(dto.GetType().GetProperty("RemoteTrailers")?.GetValue(dto)));
        var trailer = Assert.Single(trailers.RootElement.EnumerateArray());
        Assert.Equal("https://example.com/t", trailer.GetProperty("Url").GetString());
        Assert.Equal("Tráiler", trailer.GetProperty("Name").GetString());
    }

    // Kos TV: the fields an episode's card takes from its series are there (empty without one).
    [Fact]
    public void Map_HasTheSeriesThumbAndRatingFields()
    {
        var dto = Mapper().Map(new MediaBrowser.Controller.Entities.TV.Episode { Name = "Piloto" }, null);

        foreach (var name in new[] { "ParentThumbItemId", "ParentThumbImageTag", "SeriesOfficialRating" })
        {
            var property = dto.GetType().GetProperty(name);
            Assert.NotNull(property);
            Assert.Null(property.GetValue(dto));
        }
    }

    // Kos TV: with the server's image processor, its own tag; without it, the one made here.
    [Fact]
    public void Map_UsesTheServersImageTag()
    {
        var movie = new Movie { Name = "Seed" };
        movie.SetImage(new MediaBrowser.Controller.Entities.ItemImageInfo { Path = "/p.jpg", Type = MediaBrowser.Model.Entities.ImageType.Primary, DateModified = new DateTime(2024, 1, 1) }, 0);

        var processor = System.Reflection.DispatchProxy.Create<MediaBrowser.Controller.Drawing.IImageProcessor, TagProcessor>();
        var withServer = new ItemCardDtoMapper(null!, new NoOpLogger<ItemCardDtoMapper>(), processor).Map(movie, null);
        var without = Mapper().Map(movie, null);

        string? Primary(object dto) => (dto.GetType().GetProperty("ImageTags")?.GetValue(dto) as IDictionary<string, string>)?["Primary"];
        Assert.Equal("servertag", Primary(withServer));
        Assert.Equal(new DateTime(2024, 1, 1).Ticks.ToString("X"), Primary(without));
    }

    public class TagProcessor : System.Reflection.DispatchProxy
    {
        protected override object? Invoke(MethodInfo? targetMethod, object?[]? args) =>
            targetMethod?.Name == "GetImageCacheTag" ? "servertag" : throw new NotSupportedException();
    }

    [Fact]
    public void ImageTagLookup_BindsAgainstTheReferencedServer()
    {
        var binder = typeof(ItemCardDtoMapper)
            .GetField("_getImageCacheTag", BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new InvalidOperationException("Missing _getImageCacheTag.");

        Assert.NotNull((MethodInfo?)binder.GetValue(null));
    }

    // A rename on the server side would leave the lookup null and quietly send every card without
    // user data, which nothing else here would notice.
    [Fact]
    public void UserDataLookup_BindsAgainstTheReferencedServer()
    {
        var binder = typeof(ItemCardDtoMapper)
            .GetField("_getUserDataDto", BindingFlags.NonPublic | BindingFlags.Static)
            ?? throw new InvalidOperationException("Missing _getUserDataDto.");

        Assert.NotNull((MethodInfo?)binder.GetValue(null));
    }
}
