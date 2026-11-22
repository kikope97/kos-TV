using System.Globalization;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Net.Http.Headers;

namespace Moonfin.Server.Kostv;

/// <summary>
/// kOS TV: hands out the app's updates to the family's Android TVs and phones, and lets the
/// admin publish them from the plugin page. The contract with the app is in
/// docs/actualizaciones-servidor.md («Contrato app ↔ complemento»).
/// </summary>
[ApiController]
[Route("Moonfin/Kostv/Update")]
[Produces("application/json")]
public class KostvUpdatesController : ControllerBase
{
    public const string ApkContentType = "application/vnd.android.package-archive";

    private readonly KostvUpdates _updates;
    private readonly KostvInstallLinks _links;

    public KostvUpdatesController(KostvUpdates updates, KostvInstallLinks links)
    {
        _updates = updates;
        _links = links;
    }

    public static string DownloadPath(KostvUpdateVersion version, string kind) =>
        $"/Moonfin/Kostv/Update/Download/{version.Id}/{kind}.apk";

    public static string Iso(DateTimeOffset date) =>
        date.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    private ActionResult Refused(KostvUpdateException ex) =>
        StatusCode(ex.Status, new ErrorDto { Error = ex.Message, Received = ex.Received });

    // ------------------------------------------------------------------ the apps

    /// <summary>
    /// The newest version for a <paramref name="kind"/> of device (tv or phone) newer than the
    /// one it has, or <c>{ Available: false }</c>.
    /// </summary>
    [HttpGet]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult<UpdateDto> Get([FromQuery] string? kind, [FromQuery] long versionCode = 0)
    {
        if (!KostvUpdates.IsKind(kind))
        {
            return BadRequest(new ErrorDto { Error = "kind tiene que ser «tv» o «phone»." });
        }

        var version = _updates.Latest(kind!, versionCode);
        if (version == null)
        {
            return Ok(new UpdateDto { Available = false });
        }

        var file = version.FileOf(kind!);
        return Ok(new UpdateDto
        {
            Available = true,
            VersionName = version.VersionName,
            VersionCode = version.VersionCode,
            Notes = version.Notes,
            Date = Iso(version.Date),
            Size = file.Size,
            Sha256 = file.Sha256,
            Url = DownloadPath(version, kind!)
        });
    }

    /// <summary>The APK of a version still offered, resumable with Range.</summary>
    [HttpGet("Download/{id}/{kind}.apk")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status206PartialContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public ActionResult Download([FromRoute] string id, [FromRoute] string kind)
    {
        var served = _updates.Served(id, kind);
        if (served is not { } found)
        {
            return NotFound(new ErrorDto { Error = "Esa versión ya no se ofrece." });
        }

        return PhysicalFile(
            found.Path,
            ApkContentType,
            fileDownloadName: null,
            lastModified: found.Version.Date,
            entityTag: new EntityTagHeaderValue("\"" + found.Version.FileOf(kind).Sha256 + "\""),
            enableRangeProcessing: true);
    }

    /// <summary>
    /// The newest APK for a device without the app (so without a session), through a link the
    /// admin made on the plugin page. Only that file, for 30 minutes.
    /// </summary>
    [HttpGet("Install/{token}/{kind}.apk")]
    [HttpGet("/KosTV/Instalar/{token}/{kind}.apk")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status429TooManyRequests)]
    public ActionResult Install([FromRoute] string token, [FromRoute] string kind)
    {
        // The short address the panel shows says "tele" and "movil", in Spanish.
        kind = kind?.ToLowerInvariant() switch
        {
            "tele" => KostvUpdates.KindTv,
            "movil" => KostvUpdates.KindPhone,
            var other => other ?? string.Empty
        };
        var address = HttpContext?.Connection.RemoteIpAddress?.ToString() ?? "?";
        var result = KostvUpdates.IsKind(kind) ? _links.Use(token, address) : KostvInstallLinks.Result.Invalid;
        if (result == KostvInstallLinks.Result.TooMany)
        {
            return StatusCode(StatusCodes.Status429TooManyRequests, new ErrorDto { Error = "Demasiados intentos. Espera un minuto." });
        }

        var version = result == KostvInstallLinks.Result.Ok ? _updates.Latest(kind, 0) : null;
        if (version == null)
        {
            return NotFound(new ErrorDto { Error = "Este enlace ha caducado o no vale. Pide otro en el panel de Jellyfin." });
        }

        return PhysicalFile(
            _updates.ApkPath(version, kind),
            ApkContentType,
            fileDownloadName: kind == KostvUpdates.KindTv ? "KosTV_AndroidTV.apk" : "KosTV_Android.apk",
            lastModified: version.Date,
            entityTag: new EntityTagHeaderValue("\"" + version.FileOf(kind).Sha256 + "\""),
            enableRangeProcessing: true);
    }

    // ------------------------------------------------------------------ the admin page

    /// <summary>The stored versions and the settings.</summary>
    [HttpGet("Admin")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult<AdminDto> Admin() => Ok(ToAdmin(_updates.Snapshot()));

    private static AdminDto ToAdmin(KostvUpdateIndex index)
    {
        var offered = index.Versions.FirstOrDefault(v => !v.Retired);
        return new AdminDto
        {
            Keep = index.Keep,
            SignerSha256 = index.SignerSha256,
            SignerFingerprint = KostvUpdates.Pretty(index.SignerSha256),
            SignerSubject = index.SignerSubject,
            PackageName = index.PackageName,
            ChunkSize = KostvUpdates.ChunkBytes,
            MaxSize = KostvUpdates.MaxApkBytes,
            Versions = index.Versions.Select(v => new AdminVersionDto
            {
                Id = v.Id,
                VersionName = v.VersionName,
                VersionCode = v.VersionCode,
                Notes = v.Notes,
                Date = Iso(v.Date),
                Retired = v.Retired,
                Offered = v == offered,
                TvSize = v.Tv.Size,
                TvSha256 = v.Tv.Sha256,
                PhoneSize = v.Phone.Size,
                PhoneSha256 = v.Phone.Sha256
            }).ToList()
        };
    }

    /// <summary>Starts a chunked upload of one APK.</summary>
    [HttpPost("Admin/Uploads")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult StartUpload([FromBody] StartUploadDto body)
    {
        try
        {
            var upload = _updates.StartUpload(body.Kind ?? string.Empty, body.Size);
            return Ok(new UploadDto { UploadId = upload.Id, Size = upload.Size, Received = 0, ChunkSize = KostvUpdates.ChunkBytes });
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>How much of an upload the server has, to resume it.</summary>
    [HttpGet("Admin/Uploads/{id}")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult UploadStatus([FromRoute] string id)
    {
        try
        {
            var upload = _updates.UploadStatus(id);
            return Ok(new UploadDto { UploadId = upload.Id, Size = upload.Size, Received = upload.Received, ChunkSize = KostvUpdates.ChunkBytes });
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>
    /// One chunk, as the raw request body, at <paramref name="offset"/> (what the server has
    /// so far; a 409 says where to go on from).
    /// </summary>
    [HttpPut("Admin/Uploads/{id}")]
    [Authorize(Policy = "RequiresElevation")]
    [RequestSizeLimit(KostvUpdates.MaxChunkBytes + (1024 * 1024))]
    public async Task<ActionResult> UploadChunk([FromRoute] string id, [FromQuery] long offset)
    {
        try
        {
            var received = await _updates.AppendAsync(id, offset, Request.Body, HttpContext.RequestAborted).ConfigureAwait(false);
            return Ok(new UploadDto { UploadId = id, Received = received, ChunkSize = KostvUpdates.ChunkBytes });
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>Ends an upload and says what the APK is and whether it can be published.</summary>
    [HttpPost("Admin/Uploads/{id}/Finish")]
    [Authorize(Policy = "RequiresElevation")]
    public async Task<ActionResult> FinishUpload([FromRoute] string id)
    {
        try
        {
            return Ok(await _updates.FinishUploadAsync(id, HttpContext.RequestAborted).ConfigureAwait(false));
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    [HttpDelete("Admin/Uploads/{id}")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult CancelUpload([FromRoute] string id)
    {
        _updates.CancelUpload(id);
        return NoContent();
    }

    /// <summary>Publishes a version from the two finished uploads.</summary>
    [HttpPost("Admin/Versions")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult Publish([FromBody] PublishDto body)
    {
        try
        {
            _updates.Publish(body.TvUploadId ?? string.Empty, body.PhoneUploadId ?? string.Empty, body.Notes);
            return Ok(ToAdmin(_updates.Snapshot()));
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>Retires a version (no longer offered) or offers it again.</summary>
    [HttpPost("Admin/Versions/{id}/Retire")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult Retire([FromRoute] string id, [FromBody] RetireDto body)
    {
        try
        {
            _updates.SetRetired(id, body.Retired);
            return Ok(ToAdmin(_updates.Snapshot()));
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    [HttpDelete("Admin/Versions/{id}")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult Delete([FromRoute] string id)
    {
        try
        {
            _updates.Delete(id);
            return Ok(ToAdmin(_updates.Snapshot()));
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>How many versions to keep and, to fix a wrong first upload, the fingerprint.</summary>
    [HttpPost("Admin/Settings")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult Settings([FromBody] SettingsDto body)
    {
        try
        {
            if (body.Keep is { } keep)
            {
                _updates.SetKeep(keep);
            }

            if (!string.IsNullOrWhiteSpace(body.SignerSha256))
            {
                _updates.SetSigner(body.SignerSha256);
            }

            return Ok(ToAdmin(_updates.Snapshot()));
        }
        catch (KostvUpdateException ex)
        {
            return Refused(ex);
        }
    }

    /// <summary>A 30-minute link to install the app on a new device.</summary>
    [HttpPost("Admin/InstallLink")]
    [Authorize(Policy = "RequiresElevation")]
    public ActionResult InstallLink()
    {
        var (token, expires) = _links.Create();
        return Ok(new InstallLinkDto
        {
            Expires = Iso(expires),
            // The short form of Install, easier to type on a TV and without the internal name.
            TvPath = $"/KosTV/Instalar/{token}/tele.apk",
            PhonePath = $"/KosTV/Instalar/{token}/movil.apk",
            Available = _updates.Latest(KostvUpdates.KindTv, 0) != null
        });
    }

    // ------------------------------------------------------------------ shapes

    public sealed class UpdateDto
    {
        [JsonPropertyName("Available")]
        public bool Available { get; set; }

        [JsonPropertyName("VersionName")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? VersionName { get; set; }

        [JsonPropertyName("VersionCode")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public long? VersionCode { get; set; }

        [JsonPropertyName("Notes")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Notes { get; set; }

        [JsonPropertyName("Date")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Date { get; set; }

        [JsonPropertyName("Size")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public long? Size { get; set; }

        [JsonPropertyName("Sha256")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Sha256 { get; set; }

        [JsonPropertyName("Url")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Url { get; set; }
    }

    public sealed class ErrorDto
    {
        [JsonPropertyName("Error")]
        public string Error { get; set; } = string.Empty;

        [JsonPropertyName("Received")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public long? Received { get; set; }
    }

    public sealed class AdminDto
    {
        [JsonPropertyName("Keep")]
        public int Keep { get; set; }

        [JsonPropertyName("SignerSha256")]
        public string? SignerSha256 { get; set; }

        [JsonPropertyName("SignerFingerprint")]
        public string? SignerFingerprint { get; set; }

        [JsonPropertyName("SignerSubject")]
        public string? SignerSubject { get; set; }

        [JsonPropertyName("PackageName")]
        public string? PackageName { get; set; }

        [JsonPropertyName("ChunkSize")]
        public int ChunkSize { get; set; }

        [JsonPropertyName("MaxSize")]
        public long MaxSize { get; set; }

        [JsonPropertyName("Versions")]
        public List<AdminVersionDto> Versions { get; set; } = [];
    }

    public sealed class AdminVersionDto
    {
        [JsonPropertyName("Id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("VersionName")]
        public string VersionName { get; set; } = string.Empty;

        [JsonPropertyName("VersionCode")]
        public long VersionCode { get; set; }

        [JsonPropertyName("Notes")]
        public string Notes { get; set; } = string.Empty;

        [JsonPropertyName("Date")]
        public string Date { get; set; } = string.Empty;

        [JsonPropertyName("Retired")]
        public bool Retired { get; set; }

        /// <summary>The one the apps are being offered now.</summary>
        [JsonPropertyName("Offered")]
        public bool Offered { get; set; }

        [JsonPropertyName("TvSize")]
        public long TvSize { get; set; }

        [JsonPropertyName("TvSha256")]
        public string TvSha256 { get; set; } = string.Empty;

        [JsonPropertyName("PhoneSize")]
        public long PhoneSize { get; set; }

        [JsonPropertyName("PhoneSha256")]
        public string PhoneSha256 { get; set; } = string.Empty;
    }

    public sealed class UploadDto
    {
        [JsonPropertyName("UploadId")]
        public string UploadId { get; set; } = string.Empty;

        [JsonPropertyName("Size")]
        public long Size { get; set; }

        [JsonPropertyName("Received")]
        public long Received { get; set; }

        [JsonPropertyName("ChunkSize")]
        public int ChunkSize { get; set; }
    }

    public sealed class StartUploadDto
    {
        [JsonPropertyName("Kind")]
        public string? Kind { get; set; }

        [JsonPropertyName("Size")]
        public long Size { get; set; }
    }

    public sealed class PublishDto
    {
        [JsonPropertyName("TvUploadId")]
        public string? TvUploadId { get; set; }

        [JsonPropertyName("PhoneUploadId")]
        public string? PhoneUploadId { get; set; }

        [JsonPropertyName("Notes")]
        public string? Notes { get; set; }
    }

    public sealed class RetireDto
    {
        [JsonPropertyName("Retired")]
        public bool Retired { get; set; } = true;
    }

    public sealed class SettingsDto
    {
        [JsonPropertyName("Keep")]
        public int? Keep { get; set; }

        [JsonPropertyName("SignerSha256")]
        public string? SignerSha256 { get; set; }
    }

    public sealed class InstallLinkDto
    {
        [JsonPropertyName("Expires")]
        public string Expires { get; set; } = string.Empty;

        [JsonPropertyName("TvPath")]
        public string TvPath { get; set; } = string.Empty;

        [JsonPropertyName("PhonePath")]
        public string PhonePath { get; set; } = string.Empty;

        /// <summary>False while there is no version to install yet.</summary>
        [JsonPropertyName("Available")]
        public bool Available { get; set; }
    }
}
