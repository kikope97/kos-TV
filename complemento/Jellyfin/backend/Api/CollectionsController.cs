using MediaBrowser.Controller.Library;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Helpers;
using Moonfin.Server.Services;

namespace Moonfin.Server.Api;

/// <summary>
/// Per-user custom ordering of a collection's items. The Moonfin client uses this to persist a
/// drag-and-drop order that only affects what that one user sees, stored server-side so it
/// follows them across devices.
/// </summary>
[ApiController]
[Route("Moonfin/Collections")]
public class CollectionsController : ControllerBase
{
    private readonly CollectionOrderService _orderService;
    private readonly ILibraryManager _libraryManager;

    public CollectionsController(CollectionOrderService orderService, ILibraryManager libraryManager)
    {
        _orderService = orderService;
        _libraryManager = libraryManager;
    }

    /// <summary>Returns the current user's order for a collection, or an empty array when none is set.</summary>
    [HttpGet("{collectionId}/Order")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ActionResult<List<string>>> GetOrder(
        [FromRoute] string collectionId,
        CancellationToken cancellationToken)
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized();
        }

        var order = await _orderService.GetAsync(userId.Value, collectionId, cancellationToken).ConfigureAwait(false);
        return Ok(order);
    }

    /// <summary>Saves the current user's order for a collection. An empty array clears it.</summary>
    [HttpPost("{collectionId}/Order")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SaveOrder(
        [FromRoute] string collectionId,
        [FromBody] List<string>? itemIds,
        CancellationToken cancellationToken)
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized();
        }

        // Kos TV: an id that can't name an order is a bad request, not a server failure.
        if (!_orderService.IsValidId(userId.Value, collectionId))
        {
            return BadRequest(new { Error = "Invalid collection id." });
        }

        // Kos TV: an order is only kept for an item of the server the person can see, so made-up
        // ids don't fill the folder. Clearing one is always allowed.
        var order = itemIds ?? new List<string>();
        if (order.Any(id => !string.IsNullOrWhiteSpace(id)))
        {
            var user = UserReflection.ResolveUser(HttpContext.RequestServices, userId.Value);
            if (user == null)
            {
                return Unauthorized();
            }

            if (!Guid.TryParse(collectionId, out var id) ||
                _libraryManager.GetItemById(id) is not { } collection ||
                !UserReflection.IsVisibleStandaloneTo(collection, user))
            {
                return NotFound();
            }
        }

        await _orderService.SaveAsync(userId.Value, collectionId, order, cancellationToken).ConfigureAwait(false);
        // Kos TV: and the orders of collections that went long ago are forgotten.
        await _orderService.PruneAsync(userId.Value, id => _libraryManager.GetItemById(id) != null, cancellationToken).ConfigureAwait(false);
        return NoContent();
    }
}
