using System.Net.Mime;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Services;

namespace Moonfin.Server.Api;

/// <summary>
/// API controller for Moonfin push notification preferences and device registration.
/// kOS TV: without Seerr, so without its inbound webhook.
/// </summary>
[ApiController]
[Route("Moonfin/Notifications")]
[Produces(MediaTypeNames.Application.Json)]
public class NotificationsController : ControllerBase
{
    private readonly NotificationStore _store;

    public NotificationsController(NotificationStore store)
    {
        _store = store;
    }

    /// <summary>
    /// Saves the caller's notification preferences.
    /// </summary>
    [HttpPost("Prefs")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public IActionResult SavePrefs([FromBody] NotificationPrefsRequest request)
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized(new { error = "User not authenticated" });
        }

        _store.SavePrefs(
            userId.Value,
            request.NotifyOnNewRequests,
            request.NotifyOnLibraryAdded,
            request.NotifyOnIssues,
            request.NotifyOnNewMedia);
        return Ok(new { success = true });
    }

    /// <summary>
    /// Returns the caller's stored notification preferences.
    /// </summary>
    [HttpGet("Prefs")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult GetPrefs()
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized(new { error = "User not authenticated" });
        }

        var prefs = _store.GetPrefs(userId.Value);
        return Ok(new
        {
            notifyOnNewRequests = prefs.NotifyOnNewRequests,
            notifyOnLibraryAdded = prefs.NotifyOnLibraryAdded,
            notifyOnIssues = prefs.NotifyOnIssues,
            notifyOnNewMedia = prefs.NotifyOnNewMedia
        });
    }

    /// <summary>
    /// Registers a push token for the caller so backgrounded clients receive notifications.
    /// </summary>
    [HttpPost("Register")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult RegisterDevice([FromBody] DeviceRegistrationRequest request)
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized(new { error = "User not authenticated" });
        }

        if (string.IsNullOrWhiteSpace(request.Token))
        {
            return BadRequest(new { error = "Token is required" });
        }

        _store.RegisterDevice(userId.Value, request.Token, request.Platform, request.DeviceId);
        return Ok(new { success = true });
    }

    /// <summary>
    /// Removes a registered push token for the caller.
    /// </summary>
    [HttpDelete("Register")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult UnregisterDevice([FromBody] DeviceRegistrationRequest request)
    {
        var userId = this.GetUserIdFromClaims();
        if (userId == null)
        {
            return Unauthorized(new { error = "User not authenticated" });
        }

        _store.UnregisterDevice(userId.Value, request.Token, request.DeviceId);
        return Ok(new { success = true });
    }
}

/// <summary>Request body for saving notification preferences.</summary>
public class NotificationPrefsRequest
{
    public bool NotifyOnNewRequests { get; set; }
    public bool NotifyOnLibraryAdded { get; set; }

    // Nullable so payloads from clients that predate the field keep the stored value.
    public bool? NotifyOnIssues { get; set; }
    public bool? NotifyOnNewMedia { get; set; }
}

/// <summary>Request body for registering or removing a push device.</summary>
public class DeviceRegistrationRequest
{
    public string? Token { get; set; }
    public string? Platform { get; set; }
    public string? DeviceId { get; set; }
}
