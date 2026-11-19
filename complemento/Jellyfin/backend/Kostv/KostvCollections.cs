using Jellyfin.Data.Enums;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moonfin.Server.Api;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: which collections hold an item. The server has no way to ask it, so the apps used
/// to read every collection's members, one request per collection, for every detail page.
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Collections")]
[Produces("application/json")]
public class KostvCollectionsController : ControllerBase
{
    private readonly ILibraryManager _libraryManager;
    private readonly ItemCardDtoMapper _cards;
    private readonly ILogger<KostvCollectionsController> _logger;

    public KostvCollectionsController(
        ILibraryManager libraryManager,
        ItemCardDtoMapper cards,
        ILogger<KostvCollectionsController> logger)
    {
        _libraryManager = libraryManager;
        _cards = cards;
        _logger = logger;
    }

    /// <summary>
    /// The collections the caller can see that hold <paramref name="itemId"/> itself (not through
    /// its series or season), by name, as the server's own item lists.
    /// </summary>
    [HttpGet]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult Get([FromQuery] Guid itemId)
    {
        var userId = this.GetUserIdFromClaims();
        var user = userId.HasValue ? UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value) : null;
        if (userId == null || user == null)
        {
            return Unauthorized(new { Error = "User not authenticated" });
        }

        // What the person can't see says nothing about where it is.
        var item = itemId == Guid.Empty ? null : _libraryManager.GetItemById(itemId);
        if (item == null || !UserReflection.IsVisibleStandaloneTo(item, user))
        {
            return Ok(new { Items = Array.Empty<object>(), TotalRecordCount = 0 });
        }

        var query = new InternalItemsQuery
        {
            IncludeItemTypes = [BaseItemKind.BoxSet],
            Recursive = true,
            EnableTotalRecordCount = false
        };

        // Without the person's limits applied nothing is read, rather than everything.
        if (!UserReflection.ApplyUser(query, user))
        {
            return Ok(new { Items = Array.Empty<object>(), TotalRecordCount = 0 });
        }

        List<BaseItem> boxSets;
        try
        {
            // A collection's members are its linked children, which come with it, so this is one
            // read of the collections and no read of their members.
            boxSets = _libraryManager.GetItemList(query);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "kOS TV collections: reading the collections failed");
            return Ok(new { Items = Array.Empty<object>(), TotalRecordCount = 0 });
        }

        var holding = boxSets
            .OfType<Folder>()
            .Where(boxSet => KostvCollectionMembership.Holds(
                boxSet.LinkedChildren.Select(c => (c.ItemId, (string?)c.Path)),
                item.Id,
                item.Path))
            .Where(boxSet => UserReflection.IsVisibleStandaloneTo(boxSet, user))
            .OrderBy(boxSet => boxSet.SortName ?? boxSet.Name, StringComparer.OrdinalIgnoreCase)
            .Select(boxSet => _cards.Map(boxSet, user))
            .ToList();
        return Ok(new { Items = holding, TotalRecordCount = holding.Count });
    }
}

/// <summary>kOS TV: whether a collection holds an item, from its linked children.</summary>
public static class KostvCollectionMembership
{
    /// <summary>
    /// Whether one of <paramref name="children"/> is the item <paramref name="itemId"/>: by id,
    /// or by path for a child the server only knows by its file.
    /// </summary>
    public static bool Holds(IEnumerable<(Guid? ItemId, string? Path)> children, Guid itemId, string? path)
    {
        foreach (var (childId, childPath) in children)
        {
            if (childId is { } id && id != Guid.Empty)
            {
                if (id == itemId)
                {
                    return true;
                }

                continue;
            }

            if (!string.IsNullOrEmpty(path) && !string.IsNullOrEmpty(childPath) &&
                string.Equals(childPath, path, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
