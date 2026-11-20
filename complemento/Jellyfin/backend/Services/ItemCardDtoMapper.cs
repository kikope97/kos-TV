using System.Reflection;
using MediaBrowser.Controller.Drawing;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Dto;
using MediaBrowser.Model.Entities;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Services;

/// <summary>
/// Maps a BaseItem to the trimmed BaseItemDto shape the browse endpoints hand to clients, using
/// only BaseItem members that are the same across Jellyfin versions.
/// </summary>
public class ItemCardDtoMapper
{
    // Takes the User the endpoints only ever hold as an object, so it's bound the same
    // reflective way the user manager calls are.
    private static readonly MethodInfo? _getUserDataDto = typeof(IUserDataManager)
        .GetMethods()
        .FirstOrDefault(m =>
        {
            if (m.Name != "GetUserDataDto")
            {
                return false;
            }

            var parameters = m.GetParameters();
            return parameters.Length == 2 &&
                parameters[0].ParameterType == typeof(BaseItem) &&
                typeof(UserItemDataDto).IsAssignableFrom(m.ReturnType);
        });

    // Every image a card can ask for. Without Thumb and Banner a row set to either falls back
    // to the backdrop even when the library has the real art.
    private static readonly ImageType[] CardImageTypes = [ImageType.Primary, ImageType.Thumb, ImageType.Banner, ImageType.Logo];

    // Kos TV: the server's own image tag (IImageProcessor.GetImageCacheTag), bound by reflection
    // like the user data, so a server where it differs keeps the tag made here instead.
    private static readonly MethodInfo? _getImageCacheTag = typeof(IImageProcessor)
        .GetMethods()
        .FirstOrDefault(m =>
        {
            if (m.Name != "GetImageCacheTag")
            {
                return false;
            }

            var parameters = m.GetParameters();
            return parameters.Length == 2 &&
                parameters[0].ParameterType == typeof(BaseItem) &&
                parameters[1].ParameterType == typeof(ItemImageInfo) &&
                m.ReturnType == typeof(string);
        });

    private readonly IUserDataManager _userDataManager;
    private readonly IImageProcessor? _imageProcessor;
    private readonly ILogger<ItemCardDtoMapper> _logger;

    public ItemCardDtoMapper(IUserDataManager userDataManager, ILogger<ItemCardDtoMapper> logger, IImageProcessor? imageProcessor = null)
    {
        _userDataManager = userDataManager;
        _imageProcessor = imageProcessor;
        _logger = logger;
    }

    public object Map(BaseItem item, object? user)
    {
        var imageTags = new Dictionary<string, string>();
        foreach (var type in CardImageTypes)
        {
            var info = item.GetImageInfo(type, 0);
            if (info != null)
            {
                imageTags[type.ToString()] = GetTag(item, info);
            }
        }

        var backdropTags = item.GetImages(ImageType.Backdrop).Select(info => GetTag(item, info)).ToList();

        // Kos TV: looked up once (each is a trip to the library).
        var episode = item as Episode;
        var series = Lookup(() => episode?.Series);
        var seriesBackdrops = series?.GetImages(ImageType.Backdrop).Select(info => GetTag(series, info)).ToList();
        var seriesThumb = TagOf(series, ImageType.Thumb);
        var seriesLogo = TagOf(series, ImageType.Logo);
        var album = Lookup(() => (item as Audio)?.AlbumEntity);

        return new
        {
            item.Id,
            item.Name,
            Type = item.GetBaseItemKind().ToString(),
            item.ProductionYear,
            item.OfficialRating,
            item.RunTimeTicks,
            item.Genres,
            item.Overview,
            item.CommunityRating,
            item.CriticRating,
            ImageTags = imageTags,
            BackdropImageTags = backdropTags,
            UserData = BuildUserData(item, user),
            // Kos TV: what an episode's or a song's card shows of where it belongs (T1:E6,
            // the series' name and pictures, the album and its artist), as a stock item does.
            item.IndexNumber,
            item.ParentIndexNumber,
            SeriesId = episode != null && episode.SeriesId != Guid.Empty ? episode.SeriesId : (Guid?)null,
            SeriesName = episode?.SeriesName,
            SeasonId = episode != null && episode.SeasonId != Guid.Empty ? episode.SeasonId : (Guid?)null,
            SeriesPrimaryImageTag = TagOf(series, ImageType.Primary),
            ParentBackdropItemId = seriesBackdrops is { Count: > 0 } ? series!.Id : (Guid?)null,
            ParentBackdropImageTags = seriesBackdrops is { Count: > 0 } ? seriesBackdrops : null,
            ParentLogoItemId = seriesLogo != null ? series!.Id : (Guid?)null,
            ParentLogoImageTag = seriesLogo,
            // Kos TV: the series' thumb, for a row set to thumbs, as a stock episode carries it.
            ParentThumbItemId = seriesThumb != null ? series!.Id : (Guid?)null,
            ParentThumbImageTag = seriesThumb,
            // Kos TV: an episode seldom has a rating of its own; the series', apart, so an app
            // can apply its own blocked ratings to it without taking it for the episode's.
            SeriesOfficialRating = series?.OfficialRating,
            // Kos TV: a song's album by name too, as a stock item carries it (null for the rest).
            Album = (item as Audio)?.Album,
            AlbumId = album?.Id,
            AlbumPrimaryImageTag = TagOf(album, ImageType.Primary),
            AlbumArtist = (item as IHasAlbumArtist)?.AlbumArtists?.FirstOrDefault(),
            Artists = (item as IHasArtist)?.Artists,
            // Kos TV: the title's ids elsewhere (TMDB for the extra ratings) and its trailers, as
            // a stock item carries them, so a card needn't be asked for again.
            ProviderIds = item.ProviderIds,
            RemoteTrailers = item.RemoteTrailers?.Select(t => new { t.Url, t.Name }).ToList()
        };
    }

    // A lookup that can't be made (the item outside a library) leaves those fields out
    // instead of failing the whole card.
    private T? Lookup<T>(Func<T?> find)
        where T : class
    {
        try
        {
            return find();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Card lookup failed");
            return null;
        }
    }

    private string? TagOf(BaseItem? owner, ImageType type)
    {
        var info = owner?.GetImageInfo(type, 0);
        return info == null ? null : GetTag(owner!, info);
    }

    /// <summary>
    /// The calling user's played state, built by the server so it matches what a stock item
    /// response carries. Cards read Played for the checkmark, PlaybackPositionTicks for the resume
    /// bar and UnplayedItemCount for the series badge, so leaving it off makes everything these
    /// endpoints return look unwatched.
    /// </summary>
    private UserItemDataDto? BuildUserData(BaseItem item, object? user)
    {
        if (user == null || _getUserDataDto == null)
        {
            return null;
        }

        try
        {
            return _getUserDataDto.Invoke(_userDataManager, [item, user]) as UserItemDataDto;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not read user data for {ItemId}", item.Id);
            return null;
        }
    }

    /// <summary>
    /// The tag for cache-busting image URLs. Kos TV: the one the server itself gives the image,
    /// so a picture shown here and in the stock rows is one URL, fetched and kept once; when it
    /// can't be had, a stable one from the image's date.
    /// </summary>
    private string GetTag(BaseItem owner, ItemImageInfo info)
    {
        if (_imageProcessor != null && _getImageCacheTag != null)
        {
            try
            {
                if (_getImageCacheTag.Invoke(_imageProcessor, [owner, info]) is string { Length: > 0 } tag)
                {
                    return tag;
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug(ex, "Could not read the image tag of {ItemId}", owner.Id);
            }
        }

        return FallbackTag(info);
    }

    /// <summary>A stable tag string from an ItemImageInfo for cache-busting image URLs.</summary>
    private static string FallbackTag(ItemImageInfo info) => info.DateModified.Ticks.ToString("X");
}
