using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace Moonfin.Server.Kostv;

/// <summary>One of the two builds of a version.</summary>
public sealed class KostvUpdateFile
{
    [JsonPropertyName("size")]
    public long Size { get; set; }

    [JsonPropertyName("sha256")]
    public string Sha256 { get; set; } = string.Empty;
}

/// <summary>A version of the app the plugin hands out: its TV and phone APKs.</summary>
public sealed class KostvUpdateVersion
{
    /// <summary>Its versionCode, which also names its folder and goes in the download address.</summary>
    [JsonIgnore]
    public string Id => VersionCode.ToString(System.Globalization.CultureInfo.InvariantCulture);

    [JsonPropertyName("versionName")]
    public string VersionName { get; set; } = string.Empty;

    [JsonPropertyName("versionCode")]
    public long VersionCode { get; set; }

    [JsonPropertyName("notes")]
    public string Notes { get; set; } = string.Empty;

    [JsonPropertyName("date")]
    public DateTimeOffset Date { get; set; }

    /// <summary>Retired versions stay on disk but are never offered nor served.</summary>
    [JsonPropertyName("retired")]
    public bool Retired { get; set; }

    [JsonPropertyName("tv")]
    public KostvUpdateFile Tv { get; set; } = new();

    [JsonPropertyName("phone")]
    public KostvUpdateFile Phone { get; set; } = new();

    public KostvUpdateFile FileOf(string kind) => kind == KostvUpdates.KindTv ? Tv : Phone;
}

/// <summary>Everything the store keeps in its index.</summary>
public sealed class KostvUpdateIndex
{
    /// <summary>How many versions to keep; older ones are deleted after each publish.</summary>
    [JsonPropertyName("keep")]
    public int Keep { get; set; } = KostvUpdates.DefaultKeep;

    /// <summary>
    /// SHA-256 of kOS TV's signing certificate. The first published version fixes it, and from
    /// then on an APK signed with any other key is turned away.
    /// </summary>
    [JsonPropertyName("signerSha256")]
    public string? SignerSha256 { get; set; }

    [JsonPropertyName("signerSubject")]
    public string? SignerSubject { get; set; }

    /// <summary>The app's package, fixed by the first version like the signer.</summary>
    [JsonPropertyName("packageName")]
    public string? PackageName { get; set; }

    [JsonPropertyName("versions")]
    public List<KostvUpdateVersion> Versions { get; set; } = [];
}

/// <summary>What the store read from a finished upload, shown before publishing.</summary>
public sealed class KostvUploadCheck
{
    [JsonPropertyName("UploadId")]
    public string UploadId { get; set; } = string.Empty;

    [JsonPropertyName("Kind")]
    public string Kind { get; set; } = string.Empty;

    [JsonPropertyName("Size")]
    public long Size { get; set; }

    [JsonPropertyName("Sha256")]
    public string Sha256 { get; set; } = string.Empty;

    [JsonPropertyName("PackageName")]
    public string? PackageName { get; set; }

    [JsonPropertyName("VersionName")]
    public string? VersionName { get; set; }

    [JsonPropertyName("VersionCode")]
    public long? VersionCode { get; set; }

    /// <summary>Which build it is: "tv" or "phone"; null when it couldn't be read.</summary>
    [JsonPropertyName("BuildKind")]
    public string? BuildKind { get; set; }

    [JsonPropertyName("SignerSha256")]
    public string? SignerSha256 { get; set; }

    [JsonPropertyName("SignerSubject")]
    public string? SignerSubject { get; set; }

    /// <summary>What stops it from being published, in Spanish.</summary>
    [JsonPropertyName("Errors")]
    public List<string> Errors { get; set; } = [];

    /// <summary>What the admin should know but doesn't stop it, in Spanish.</summary>
    [JsonPropertyName("Warnings")]
    public List<string> Warnings { get; set; } = [];

    [JsonPropertyName("Ok")]
    public bool Ok => Errors.Count == 0;
}

/// <summary>An upload under way, kept next to its data so it can resume after a restart.</summary>
public sealed class KostvUpload
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = string.Empty;

    [JsonPropertyName("size")]
    public long Size { get; set; }

    [JsonPropertyName("received")]
    public long Received { get; set; }

    [JsonPropertyName("created")]
    public DateTimeOffset Created { get; set; }

    [JsonPropertyName("check")]
    public KostvUploadCheck? Check { get; set; }
}

/// <summary>A refusal with the status code the route should answer and a Spanish message.</summary>
public sealed class KostvUpdateException : Exception
{
    public KostvUpdateException(int status, string message, long? received = null)
        : base(message)
    {
        Status = status;
        Received = received;
    }

    public int Status { get; }

    /// <summary>For an upload out of step: how much the server has, to resume from there.</summary>
    public long? Received { get; }
}

/// <summary>
/// kOS TV: the app updates the plugin hands out to the family's TVs and phones instead of
/// GitHub. The admin uploads both APKs in chunks; the version, the kind of build and the
/// signer are read from the files themselves; the newest N versions are kept.
/// </summary>
public sealed class KostvUpdates
{
    public const string FolderName = "kostv-updates";
    public const string KindTv = "tv";
    public const string KindPhone = "phone";
    public const int DefaultKeep = 10;
    public const int MaxKeep = 50;
    public const long MaxApkBytes = 300L * 1024 * 1024;

    /// <summary>The chunk size the admin page sends: well under Kestrel's 30 MB and most proxies.</summary>
    public const int ChunkBytes = 8 * 1024 * 1024;

    /// <summary>The largest chunk accepted (the route's request limit is a little above).</summary>
    public const int MaxChunkBytes = 16 * 1024 * 1024;

    public static readonly TimeSpan StaleUpload = TimeSpan.FromHours(24);

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    private readonly string _root;
    private readonly Func<DateTimeOffset> _now;
    private readonly ILogger? _logger;
    private readonly object _lock = new();
    private readonly ConcurrentDictionary<string, SemaphoreSlim> _uploadLocks = new();
    private KostvUpdateIndex? _index;

    public KostvUpdates(string root, Func<DateTimeOffset>? now = null, ILogger? logger = null)
    {
        _root = root;
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _logger = logger;
    }

    public static bool IsKind(string? kind) => kind is KindTv or KindPhone;

    private string IndexPath => Path.Combine(_root, "index.json");

    private string UploadsDir => Path.Combine(_root, "uploads");

    private string VersionDir(long code) =>
        Path.Combine(_root, "versions", code.ToString(System.Globalization.CultureInfo.InvariantCulture));

    public string ApkPath(KostvUpdateVersion version, string kind) =>
        Path.Combine(VersionDir(version.VersionCode), kind + ".apk");

    // ------------------------------------------------------------------ index

    private KostvUpdateIndex IndexLocked()
    {
        if (_index != null)
        {
            return _index;
        }

        try
        {
            _index = File.Exists(IndexPath)
                ? JsonSerializer.Deserialize<KostvUpdateIndex>(File.ReadAllText(IndexPath)) ?? new KostvUpdateIndex()
                : new KostvUpdateIndex();
        }
        catch (Exception ex) when (ex is JsonException or IOException)
        {
            // A broken index must not lose the APKs: keep it aside and start a new one.
            _logger?.LogError(ex, "kOS TV updates: could not read {Path}; starting a new index", IndexPath);
            try
            {
                File.Copy(IndexPath, IndexPath + ".broken", overwrite: true);
            }
            catch (IOException)
            {
            }

            _index = new KostvUpdateIndex();
        }

        _index.Versions.Sort((a, b) => b.VersionCode.CompareTo(a.VersionCode));
        return _index;
    }

    private void SaveLocked()
    {
        Directory.CreateDirectory(_root);
        var temp = IndexPath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(_index, Json));
        File.Move(temp, IndexPath, overwrite: true);
    }

    /// <summary>A copy of the index, newest version first.</summary>
    public KostvUpdateIndex Snapshot()
    {
        lock (_lock)
        {
            return JsonSerializer.Deserialize<KostvUpdateIndex>(JsonSerializer.Serialize(IndexLocked(), Json))!;
        }
    }

    // ------------------------------------------------------------------ for the apps

    /// <summary>
    /// The newest version that isn't retired and is newer than <paramref name="versionCode"/>,
    /// or null. A device far behind jumps straight to the newest.
    /// </summary>
    public KostvUpdateVersion? Latest(string kind, long versionCode)
    {
        lock (_lock)
        {
            var latest = IndexLocked().Versions.FirstOrDefault(v => !v.Retired);
            return latest != null && latest.VersionCode > versionCode && File.Exists(ApkPath(latest, kind))
                ? latest
                : null;
        }
    }

    /// <summary>The APK of a version that is still offered, or null (retired, deleted, unknown).</summary>
    public (KostvUpdateVersion Version, string Path)? Served(string id, string kind)
    {
        if (!IsKind(kind))
        {
            return null;
        }

        lock (_lock)
        {
            var version = IndexLocked().Versions.FirstOrDefault(v => v.Id == id && !v.Retired);
            if (version == null)
            {
                return null;
            }

            var path = ApkPath(version, kind);
            return File.Exists(path) ? (version, path) : null;
        }
    }

    // ------------------------------------------------------------------ uploads

    private static string NewId() => Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();

    private static bool IsId(string id) => id.Length == 32 && id.All(Uri.IsHexDigit);

    private string PartPath(string id) => Path.Combine(UploadsDir, id + ".part");

    private string MetaPath(string id) => Path.Combine(UploadsDir, id + ".json");

    private KostvUpload LoadUpload(string id)
    {
        if (!IsId(id) || !File.Exists(MetaPath(id)))
        {
            throw new KostvUpdateException(404, "Esa subida ya no existe: vuelve a elegir el archivo.");
        }

        return JsonSerializer.Deserialize<KostvUpload>(File.ReadAllText(MetaPath(id)))
            ?? throw new KostvUpdateException(404, "Esa subida ya no existe: vuelve a elegir el archivo.");
    }

    private void SaveUpload(KostvUpload upload)
    {
        var temp = MetaPath(upload.Id) + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(upload, Json));
        File.Move(temp, MetaPath(upload.Id), overwrite: true);
    }

    /// <summary>Starts an upload of a <paramref name="kind"/> APK of <paramref name="size"/> bytes.</summary>
    public KostvUpload StartUpload(string kind, long size)
    {
        if (!IsKind(kind))
        {
            throw new KostvUpdateException(400, "Falta decir si el APK es el de la tele o el del móvil.");
        }

        if (size <= 0)
        {
            throw new KostvUpdateException(400, "El archivo está vacío.");
        }

        if (size > MaxApkBytes)
        {
            throw new KostvUpdateException(413, "El APK es demasiado grande (como mucho, 300 MB).");
        }

        CleanStaleUploads();
        Directory.CreateDirectory(UploadsDir);
        var upload = new KostvUpload { Id = NewId(), Kind = kind, Size = size, Created = _now() };
        File.WriteAllBytes(PartPath(upload.Id), []);
        SaveUpload(upload);
        return upload;
    }

    public KostvUpload UploadStatus(string id) => LoadUpload(id);

    /// <summary>
    /// Writes a chunk at <paramref name="offset"/>, which must be what the server already has
    /// (so a cut-off chunk is simply sent again). Returns the bytes received so far.
    /// </summary>
    public async Task<long> AppendAsync(string id, long offset, Stream body, CancellationToken cancellationToken = default)
    {
        var gate = _uploadLocks.GetOrAdd(id, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var upload = LoadUpload(id);
            if (upload.Check != null)
            {
                throw new KostvUpdateException(409, "Esa subida ya está terminada.", upload.Received);
            }

            if (offset != upload.Received)
            {
                throw new KostvUpdateException(409, "La subida no va por ahí: sigue desde lo que ya tiene el servidor.", upload.Received);
            }

            await using (var file = new FileStream(PartPath(id), FileMode.Open, FileAccess.Write, FileShare.None))
            {
                // Anything a cut-off chunk left past the last good offset goes.
                file.SetLength(upload.Received);
                file.Position = upload.Received;
                var buffer = new byte[81920];
                long written = 0;
                int read;
                try
                {
                    while ((read = await body.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
                    {
                        written += read;
                        if (written > MaxChunkBytes || upload.Received + written > upload.Size)
                        {
                            file.SetLength(upload.Received);
                            throw new KostvUpdateException(413, "Ese trozo es más grande de lo que falta por subir.", upload.Received);
                        }

                        await file.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
                    }

                    await file.FlushAsync(cancellationToken).ConfigureAwait(false);
                }
                catch (IOException ex)
                {
                    // kOS TV: a chunk cut off on the way (the page closed, the proxy gave up) or
                    // a disk with no room left: none of it counts, and the page is told where
                    // it stands, in Spanish, instead of a bare 500.
                    _logger?.LogWarning(ex, "kOS TV updates: chunk of upload {Id} at {Offset} not kept", id, offset);
                    TryTruncate(file, upload.Received);
                    throw new KostvUpdateException(
                        507,
                        "No se ha podido guardar ese trozo en el servidor. Si se repite, mira si queda espacio en su disco.",
                        upload.Received);
                }

                upload.Received += written;
            }

            SaveUpload(upload);
            return upload.Received;
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Ends an upload: reads the APK and checks it against the store (kind, package, signer,
    /// version). The result is kept with the upload, and an APK with errors can't be published.
    /// </summary>
    public async Task<KostvUploadCheck> FinishUploadAsync(string id, CancellationToken cancellationToken = default)
    {
        var gate = _uploadLocks.GetOrAdd(id, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var upload = LoadUpload(id);
            if (upload.Check != null)
            {
                return upload.Check;
            }

            if (upload.Received != upload.Size)
            {
                throw new KostvUpdateException(409, "Aún no ha llegado todo el archivo.", upload.Received);
            }

            var path = PartPath(id);
            string sha;
            await using (var file = File.OpenRead(path))
            {
                sha = Convert.ToHexString(await SHA256.HashDataAsync(file, cancellationToken).ConfigureAwait(false)).ToLowerInvariant();
            }

            var check = new KostvUploadCheck { UploadId = id, Kind = upload.Kind, Size = upload.Size, Sha256 = sha };
            try
            {
                var apk = KostvApk.Read(path);
                check.PackageName = apk.PackageName;
                check.VersionName = apk.VersionName;
                check.VersionCode = apk.VersionCode;
                check.BuildKind = apk.IsTv ? KindTv : KindPhone;
                check.SignerSha256 = apk.SignerSha256;
                check.SignerSubject = apk.SignerSubject;
                lock (_lock)
                {
                    Validate(check, apk, IndexLocked());
                }
            }
            catch (KostvApkException ex)
            {
                check.Errors.Add(ex.Message);
            }

            upload.Check = check;
            SaveUpload(upload);
            return check;
        }
        finally
        {
            gate.Release();
        }
    }

    private static void Validate(KostvUploadCheck check, KostvApkInfo apk, KostvUpdateIndex index)
    {
        if (apk.IsTv && check.Kind == KindPhone)
        {
            check.Errors.Add("Este APK es el de la tele, no el del móvil.");
        }
        else if (!apk.IsTv && check.Kind == KindTv)
        {
            check.Errors.Add("Este APK es el del móvil, no el de la tele.");
        }

        if (index.PackageName != null && apk.PackageName != index.PackageName)
        {
            check.Errors.Add($"Este APK no es de kOS TV: es «{apk.PackageName}» y las versiones guardadas son «{index.PackageName}».");
        }

        if (apk.IsDebugSigned)
        {
            check.Errors.Add("Este APK está firmado con la clave de depuración de Android: las apps instaladas no lo aceptarían.");
        }
        else if (index.SignerSha256 == null)
        {
            check.Warnings.Add($"Es la primera versión: su firma (huella {Pretty(apk.SignerSha256)}) queda como la de kOS TV, y desde ahora solo se aceptarán APK firmados con ella.");
        }
        else if (!string.Equals(apk.SignerSha256, index.SignerSha256, StringComparison.OrdinalIgnoreCase))
        {
            check.Errors.Add($"Este APK está firmado con otra clave (huella {Pretty(apk.SignerSha256)}). Las apps instaladas solo aceptan la de kOS TV ({Pretty(index.SignerSha256)}), así que no se puede publicar.");
        }

        // kOS TV: a test build (1.21.0-prueba.3, code 102100003) is a code above its
        // release's, so once published the release itself (102100000) couldn't follow it.
        if (apk.VersionCode % 100 != 0 || apk.VersionName.Contains("prueba", StringComparison.OrdinalIgnoreCase))
        {
            check.Warnings.Add($"Es una versión de prueba ({apk.VersionName}, código {apk.VersionCode}). Si la publicas, la versión normal en la que se basa ya no se podrá publicar encima: tendrá que ser la siguiente.");
        }

        var newest = index.Versions.FirstOrDefault();
        if (index.Versions.Any(v => v.VersionCode == apk.VersionCode))
        {
            check.Errors.Add($"La versión {apk.VersionName} (código {apk.VersionCode}) ya está guardada.");
        }
        else if (newest != null && apk.VersionCode < newest.VersionCode)
        {
            check.Errors.Add($"Esta versión ({apk.VersionName}, código {apk.VersionCode}) es más antigua que la última guardada ({newest.VersionName}, código {newest.VersionCode}): ninguna tele ni móvil la instalaría.");
        }
    }

    /// <summary>A fingerprint in the usual AA:BB:… form.</summary>
    public static string Pretty(string? hex) =>
        string.IsNullOrEmpty(hex)
            ? string.Empty
            : string.Join(':', Enumerable.Range(0, hex.Length / 2).Select(i => hex.Substring(i * 2, 2).ToUpperInvariant()));

    public void CancelUpload(string id)
    {
        if (!IsId(id))
        {
            return;
        }

        TryDelete(PartPath(id));
        TryDelete(MetaPath(id));
        _uploadLocks.TryRemove(id, out _);
    }

    /// <summary>Uploads left half-way (a closed page) are deleted after a day.</summary>
    public void CleanStaleUploads()
    {
        if (!Directory.Exists(UploadsDir))
        {
            return;
        }

        var cutoff = _now() - StaleUpload;
        foreach (var meta in Directory.GetFiles(UploadsDir, "*.json"))
        {
            var id = Path.GetFileNameWithoutExtension(meta);
            try
            {
                var upload = JsonSerializer.Deserialize<KostvUpload>(File.ReadAllText(meta));
                if (upload == null || upload.Created < cutoff)
                {
                    CancelUpload(id);
                }
            }
            catch (Exception ex) when (ex is JsonException or IOException)
            {
                CancelUpload(id);
            }
        }

        // Parts whose description went missing.
        foreach (var part in Directory.GetFiles(UploadsDir, "*.part"))
        {
            if (!File.Exists(Path.ChangeExtension(part, ".json")))
            {
                TryDelete(part);
            }
        }
    }

    private static void TryTruncate(FileStream file, long length)
    {
        try
        {
            file.SetLength(length);
        }
        catch (IOException)
        {
            // The next chunk truncates it again before writing.
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    // ------------------------------------------------------------------ versions

    /// <summary>
    /// Publishes a version from two checked uploads (the TV and the phone APK of the same
    /// version), then deletes the oldest beyond the number to keep.
    /// </summary>
    public KostvUpdateVersion Publish(string tvUploadId, string phoneUploadId, string? notes)
    {
        var tv = LoadUpload(tvUploadId);
        var phone = LoadUpload(phoneUploadId);
        if (tv.Check == null || phone.Check == null)
        {
            throw new KostvUpdateException(409, "Aún no se han terminado de subir los dos APK.");
        }

        if (tv.Kind != KindTv || phone.Kind != KindPhone)
        {
            throw new KostvUpdateException(400, "Hace falta el APK de la tele y el del móvil, cada uno en su sitio.");
        }

        var errors = tv.Check.Errors.Select(e => "Tele: " + e).Concat(phone.Check.Errors.Select(e => "Móvil: " + e)).ToList();
        if (errors.Count > 0)
        {
            throw new KostvUpdateException(400, string.Join("\n", errors));
        }

        if (tv.Check.VersionCode != phone.Check.VersionCode || tv.Check.VersionName != phone.Check.VersionName)
        {
            throw new KostvUpdateException(400, $"El APK de la tele ({tv.Check.VersionName}, código {tv.Check.VersionCode}) y el del móvil ({phone.Check.VersionName}, código {phone.Check.VersionCode}) no son de la misma versión.");
        }

        if (tv.Check.SignerSha256 != phone.Check.SignerSha256)
        {
            throw new KostvUpdateException(400, "El APK de la tele y el del móvil están firmados con claves distintas.");
        }

        if (tv.Check.PackageName != phone.Check.PackageName)
        {
            throw new KostvUpdateException(400, "El APK de la tele y el del móvil son de aplicaciones distintas.");
        }

        lock (_lock)
        {
            var index = IndexLocked();

            // The store may have changed since the uploads were checked.
            var recheck = new KostvUploadCheck { Kind = KindTv };
            Validate(recheck, new KostvApkInfo
            {
                PackageName = tv.Check.PackageName!,
                VersionName = tv.Check.VersionName!,
                VersionCode = tv.Check.VersionCode!.Value,
                IsTv = true,
                SignerSha256 = tv.Check.SignerSha256!,
                SignerSubject = tv.Check.SignerSubject ?? string.Empty
            }, index);
            if (recheck.Errors.Count > 0)
            {
                throw new KostvUpdateException(409, string.Join("\n", recheck.Errors));
            }

            var version = new KostvUpdateVersion
            {
                VersionName = tv.Check.VersionName!,
                VersionCode = tv.Check.VersionCode!.Value,
                Notes = (notes ?? string.Empty).Trim(),
                Date = _now(),
                Tv = new KostvUpdateFile { Size = tv.Check.Size, Sha256 = tv.Check.Sha256 },
                Phone = new KostvUpdateFile { Size = phone.Check.Size, Sha256 = phone.Check.Sha256 }
            };

            // Files first, into a folder of their own, then the index: a crash in between
            // leaves at most an unlisted folder, never a listed version without its files.
            var dir = VersionDir(version.VersionCode);
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }

            var staging = dir + ".new";
            if (Directory.Exists(staging))
            {
                Directory.Delete(staging, recursive: true);
            }

            Directory.CreateDirectory(staging);
            try
            {
                File.Move(PartPath(tv.Id), Path.Combine(staging, KindTv + ".apk"));
                File.Move(PartPath(phone.Id), Path.Combine(staging, KindPhone + ".apk"));
            }
            catch (FileNotFoundException)
            {
                // Published a moment ago from another tab, or cancelled.
                Directory.Delete(staging, recursive: true);
                throw new KostvUpdateException(409, "Esos APK ya no están: vuelve a elegirlos.");
            }

            Directory.Move(staging, dir);

            index.Versions.Insert(0, version);
            index.Versions.Sort((a, b) => b.VersionCode.CompareTo(a.VersionCode));
            index.SignerSha256 ??= tv.Check.SignerSha256;
            index.SignerSubject ??= tv.Check.SignerSubject;
            index.PackageName ??= tv.Check.PackageName;
            PruneLocked(index);
            SaveLocked();

            CancelUpload(tv.Id);
            CancelUpload(phone.Id);
            return version;
        }
    }

    /// <summary>Keeps the newest <c>Keep</c> versions, and always the one being offered.</summary>
    private void PruneLocked(KostvUpdateIndex index)
    {
        var offered = index.Versions.FirstOrDefault(v => !v.Retired);
        var keep = Math.Clamp(index.Keep, 1, MaxKeep);
        var drop = index.Versions.Skip(keep).Where(v => v != offered).ToList();
        foreach (var version in drop)
        {
            index.Versions.Remove(version);
            DeleteFolder(version.VersionCode);
        }
    }

    private void DeleteFolder(long code)
    {
        try
        {
            var dir = VersionDir(code);
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A download in progress on Windows; it goes with the next clean-up.
            _logger?.LogWarning(ex, "kOS TV updates: could not delete version {Code}", code);
        }
    }

    private KostvUpdateVersion Find(KostvUpdateIndex index, string id) =>
        index.Versions.FirstOrDefault(v => v.Id == id)
        ?? throw new KostvUpdateException(404, "Esa versión ya no está guardada.");

    /// <summary>Retires a version (no longer offered nor served) or offers it again.</summary>
    public KostvUpdateVersion SetRetired(string id, bool retired)
    {
        lock (_lock)
        {
            var index = IndexLocked();
            var version = Find(index, id);
            version.Retired = retired;
            SaveLocked();
            return version;
        }
    }

    public void Delete(string id)
    {
        lock (_lock)
        {
            var index = IndexLocked();
            var version = Find(index, id);
            index.Versions.Remove(version);
            SaveLocked();
            DeleteFolder(version.VersionCode);
        }
    }

    /// <summary>How many versions to keep (1 to 50); the extra ones go now.</summary>
    public KostvUpdateIndex SetKeep(int keep)
    {
        if (keep < 1 || keep > MaxKeep)
        {
            throw new KostvUpdateException(400, $"Hay que guardar entre 1 y {MaxKeep} versiones.");
        }

        lock (_lock)
        {
            var index = IndexLocked();
            index.Keep = keep;
            PruneLocked(index);
            SaveLocked();
        }

        return Snapshot();
    }

    /// <summary>
    /// Changes the accepted signing fingerprint by hand (64 hex characters, colons allowed).
    /// Installed apps can't update to an APK signed with another key, so this is only for
    /// fixing a wrong first upload.
    /// </summary>
    public KostvUpdateIndex SetSigner(string fingerprint)
    {
        var hex = new string((fingerprint ?? string.Empty).Where(c => c != ':' && !char.IsWhiteSpace(c)).ToArray()).ToLowerInvariant();
        if (hex.Length != 64 || !hex.All(Uri.IsHexDigit))
        {
            throw new KostvUpdateException(400, "La huella tiene que ser un SHA-256: 64 caracteres hexadecimales (se pueden separar con «:»).");
        }

        lock (_lock)
        {
            var index = IndexLocked();
            if (index.SignerSha256 != hex)
            {
                index.SignerSha256 = hex;
                index.SignerSubject = null;
            }

            SaveLocked();
        }

        return Snapshot();
    }
}

/// <summary>
/// kOS TV: short-lived links that download the newest APK without signing in, for a TV or
/// phone that doesn't have the app yet. Kept in memory: a restart simply ends them.
/// </summary>
public sealed class KostvInstallLinks
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromMinutes(30);

    /// <summary>Requests per link (a download may come in several ranges).</summary>
    public const int MaxUsesPerLink = 30;

    /// <summary>Wrong links per address and minute before it has to wait.</summary>
    public const int MaxFailuresPerMinute = 10;

    private readonly Func<DateTimeOffset> _now;
    private readonly object _lock = new();
    private readonly Dictionary<string, (DateTimeOffset Expires, int Uses)> _links = new();
    private readonly Dictionary<string, List<DateTimeOffset>> _failures = new();

    public KostvInstallLinks(Func<DateTimeOffset>? now = null)
    {
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    /// <summary>Letters and digits that can't be mistaken for one another (no 0/O, 1/I/L).</summary>
    public const string Alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

    /// <summary>
    /// Short enough to type with a TV remote; 31^8 codes, with guessing slowed per address and
    /// each code gone in 30 minutes.
    /// </summary>
    public const int TokenLength = 8;

    public (string Token, DateTimeOffset Expires) Create()
    {
        var token = string.Concat(Enumerable.Range(0, TokenLength).Select(_ => Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)]));
        var expires = _now() + Lifetime;
        lock (_lock)
        {
            Sweep();
            _links[token] = (expires, 0);
        }

        return (token, expires);
    }

    public enum Result
    {
        Ok,
        Invalid,
        TooMany
    }

    /// <summary>Checks a link from <paramref name="address"/>, counting one use when it's good.</summary>
    public Result Use(string token, string address)
    {
        var now = _now();
        lock (_lock)
        {
            Sweep();
            if (_failures.TryGetValue(address, out var failures)
                && failures.Count(t => t > now - TimeSpan.FromMinutes(1)) >= MaxFailuresPerMinute)
            {
                return Result.TooMany;
            }

            token = (token ?? string.Empty).ToUpperInvariant();
            if (_links.TryGetValue(token, out var link) && link.Expires > now && link.Uses < MaxUsesPerLink)
            {
                _links[token] = (link.Expires, link.Uses + 1);
                return Result.Ok;
            }

            if (!_failures.TryGetValue(address, out failures))
            {
                failures = [];
                _failures[address] = failures;
            }

            failures.Add(now);
            return Result.Invalid;
        }
    }

    private void Sweep()
    {
        var now = _now();
        foreach (var expired in _links.Where(l => l.Value.Expires <= now).Select(l => l.Key).ToList())
        {
            _links.Remove(expired);
        }

        foreach (var (address, list) in _failures.ToList())
        {
            list.RemoveAll(t => t <= now - TimeSpan.FromMinutes(1));
            if (list.Count == 0)
            {
                _failures.Remove(address);
            }
        }
    }
}
