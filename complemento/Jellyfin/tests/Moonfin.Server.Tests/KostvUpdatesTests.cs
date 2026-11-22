using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: the update store, its routes and the install links.</summary>
public class KostvUpdatesTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-updates-" + Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 11, 22, 10, 0, 0, TimeSpan.Zero);
    private readonly KostvUpdates _store;

    public KostvUpdatesTests()
    {
        _store = new KostvUpdates(_root, () => _now);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private static byte[] Apk(string kind, long code = KostvApkFixtures.RealVersionCode, string name = "1.20.0", KostvApkFixtures.Key? key = null)
    {
        var manifest = kind == KostvUpdates.KindTv ? KostvApkFixtures.TvManifest : KostvApkFixtures.PhoneManifest;
        if (code != KostvApkFixtures.RealVersionCode)
        {
            manifest = KostvApkFixtures.WithVersion(manifest, code, name);
        }

        return KostvApkFixtures.Sign(KostvApkFixtures.Zip(manifest, 1024 * 1024 + 300), key ?? KostvApkFixtures.TestKey);
    }

    private async Task<KostvUploadCheck> Upload(string kind, byte[] bytes, int chunk = 400 * 1024)
    {
        var upload = _store.StartUpload(kind, bytes.Length);
        for (var at = 0; at < bytes.Length; at += chunk)
        {
            var piece = bytes.AsSpan(at, Math.Min(chunk, bytes.Length - at)).ToArray();
            await _store.AppendAsync(upload.Id, at, new MemoryStream(piece));
        }

        return await _store.FinishUploadAsync(upload.Id);
    }

    private async Task<KostvUpdateVersion> PublishVersion(long code, string name, string notes = "Novedades")
    {
        var tv = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, code, name));
        var phone = await Upload(KostvUpdates.KindPhone, Apk(KostvUpdates.KindPhone, code, name));
        Assert.True(tv.Ok, string.Join(" | ", tv.Errors));
        Assert.True(phone.Ok, string.Join(" | ", phone.Errors));
        _now = _now.AddMinutes(1);
        return _store.Publish(tv.UploadId, phone.UploadId, notes);
    }

    // ------------------------------------------------------------------ uploads

    [Fact]
    public async Task ChunkedUpload_IsAssembledAndChecked()
    {
        var bytes = Apk(KostvUpdates.KindTv);
        var check = await Upload(KostvUpdates.KindTv, bytes);

        Assert.True(check.Ok);
        Assert.Equal(Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(), check.Sha256);
        Assert.Equal(bytes.Length, check.Size);
        Assert.Equal("1.20.0", check.VersionName);
        Assert.Equal(KostvUpdates.KindTv, check.BuildKind);
        Assert.Equal(KostvApkFixtures.TestKey.Sha256, check.SignerSha256);
        // The first version fixes the signer, and the admin is told so.
        Assert.Contains(check.Warnings, w => w.Contains("primera versión"));
    }

    [Fact]
    public async Task Upload_ResumesFromWhatTheServerHas()
    {
        var bytes = Apk(KostvUpdates.KindPhone);
        var upload = _store.StartUpload(KostvUpdates.KindPhone, bytes.Length);
        var half = bytes.Length / 2;
        Assert.Equal(half, await _store.AppendAsync(upload.Id, 0, new MemoryStream(bytes[..half])));

        // A chunk cut off half-way: what it wrote doesn't count, and the page is told where
        // it stands (in Spanish, not a bare 500).
        var cut = await Assert.ThrowsAsync<KostvUpdateException>(() => _store.AppendAsync(upload.Id, half, new BreakingStream(bytes[half..], 1000)));
        Assert.Equal(507, cut.Status);
        Assert.Equal(half, cut.Received);
        Assert.Equal(half, _store.UploadStatus(upload.Id).Received);
        Assert.Equal(half, new FileInfo(Path.Combine(_root, "uploads", upload.Id + ".part")).Length);

        // The page sends from a wrong place: told where to go on from.
        var refused = await Assert.ThrowsAsync<KostvUpdateException>(() => _store.AppendAsync(upload.Id, 0, new MemoryStream(bytes[..10])));
        Assert.Equal(409, refused.Status);
        Assert.Equal(half, refused.Received);

        await _store.AppendAsync(upload.Id, half, new MemoryStream(bytes[half..]));
        var check = await _store.FinishUploadAsync(upload.Id);
        Assert.True(check.Ok, string.Join(" | ", check.Errors));
        Assert.Equal(Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(), check.Sha256);
    }

    [Fact]
    public async Task Upload_LimitsAreKept()
    {
        Assert.Equal(413, Assert.Throws<KostvUpdateException>(() => _store.StartUpload(KostvUpdates.KindTv, KostvUpdates.MaxApkBytes + 1)).Status);
        Assert.Equal(400, Assert.Throws<KostvUpdateException>(() => _store.StartUpload("ios", 10)).Status);
        Assert.Equal(400, Assert.Throws<KostvUpdateException>(() => _store.StartUpload(KostvUpdates.KindTv, 0)).Status);

        var upload = _store.StartUpload(KostvUpdates.KindTv, 100);
        var tooMuch = await Assert.ThrowsAsync<KostvUpdateException>(() => _store.AppendAsync(upload.Id, 0, new MemoryStream(new byte[101])));
        Assert.Equal(413, tooMuch.Status);
        Assert.Equal(0, _store.UploadStatus(upload.Id).Received);

        await _store.AppendAsync(upload.Id, 0, new MemoryStream(new byte[60]));
        Assert.Equal(409, (await Assert.ThrowsAsync<KostvUpdateException>(() => _store.FinishUploadAsync(upload.Id))).Status);

        Assert.Equal(404, Assert.Throws<KostvUpdateException>(() => _store.UploadStatus("../../etc/passwd")).Status);
    }

    [Fact]
    public async Task TestBuild_IsWarnedAbout()
    {
        // A GitHub test build (code 102100003, 1.21.0-prueba.3): allowed, but the admin is told the release
        // 1.21.0 couldn't go on top of it afterwards.
        var test = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, 102100003, "1.21.0"));
        Assert.True(test.Ok, string.Join(" | ", test.Errors));
        Assert.Contains(test.Warnings, w => w.Contains("versión de prueba"));

        var release = await Upload(KostvUpdates.KindPhone, Apk(KostvUpdates.KindPhone, 102100000, "1.21.0"));
        Assert.DoesNotContain(release.Warnings, w => w.Contains("versión de prueba"));
    }

    [Fact]
    public async Task NotAnApk_IsExplained()
    {
        var check = await Upload(KostvUpdates.KindTv, RandomNumberGenerator.GetBytes(5000));
        Assert.False(check.Ok);
        Assert.Contains(check.Errors, e => e.Contains("No es un APK"));
    }

    [Fact]
    public async Task ApkInTheWrongSlot_IsRefused()
    {
        var tvAsPhone = await Upload(KostvUpdates.KindPhone, Apk(KostvUpdates.KindTv));
        var phoneAsTv = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindPhone));

        Assert.Contains("Este APK es el de la tele, no el del móvil.", tvAsPhone.Errors);
        Assert.Contains("Este APK es el del móvil, no el de la tele.", phoneAsTv.Errors);
        var error = Assert.Throws<KostvUpdateException>(() => _store.Publish(phoneAsTv.UploadId, tvAsPhone.UploadId, null));
        Assert.Equal(400, error.Status);
    }

    [Fact]
    public async Task DebugKey_IsRefused()
    {
        var check = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, key: KostvApkFixtures.DebugKey));
        Assert.Contains(check.Errors, e => e.Contains("clave de depuración"));
    }

    [Fact]
    public async Task AnotherKey_IsRefusedOnceTheFirstVersionFixedIt()
    {
        await PublishVersion(KostvApkFixtures.RealVersionCode, "1.20.0");

        var check = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, 102100000, "1.21.0", KostvApkFixtures.OtherKey));

        Assert.False(check.Ok);
        Assert.Contains(check.Errors, e => e.Contains("otra clave") && e.Contains(KostvUpdates.Pretty(KostvApkFixtures.TestKey.Sha256)));
        Assert.Equal(KostvApkFixtures.TestKey.Sha256, _store.Snapshot().SignerSha256);
    }

    [Fact]
    public async Task OlderOrSameVersion_IsRefused()
    {
        await PublishVersion(102100000, "1.21.0");

        var same = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, 102100000, "1.21.0"));
        var older = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv));

        Assert.Contains(same.Errors, e => e.Contains("ya está guardada"));
        Assert.Contains(older.Errors, e => e.Contains("más antigua"));
    }

    [Fact]
    public async Task DifferentVersionsForTvAndPhone_AreRefused()
    {
        var tv = await Upload(KostvUpdates.KindTv, Apk(KostvUpdates.KindTv, 102100000, "1.21.0"));
        var phone = await Upload(KostvUpdates.KindPhone, Apk(KostvUpdates.KindPhone));

        var error = Assert.Throws<KostvUpdateException>(() => _store.Publish(tv.UploadId, phone.UploadId, null));
        Assert.Contains("no son de la misma versión", error.Message);
        Assert.Empty(_store.Snapshot().Versions);
    }

    [Fact]
    public async Task StaleUploads_GoAfterADay()
    {
        var upload = _store.StartUpload(KostvUpdates.KindTv, 100);
        await _store.AppendAsync(upload.Id, 0, new MemoryStream(new byte[50]));

        _now = _now.AddHours(25);
        _store.CleanStaleUploads();

        Assert.Equal(404, Assert.Throws<KostvUpdateException>(() => _store.UploadStatus(upload.Id)).Status);
        Assert.Empty(Directory.GetFiles(Path.Combine(_root, "uploads")));
    }

    // ------------------------------------------------------------------ versions

    [Fact]
    public async Task Published_IsOfferedToOlderDevicesOnly()
    {
        var version = await PublishVersion(102100000, "1.21.0", "  Arreglos del reproductor  ");

        Assert.Equal("Arreglos del reproductor", version.Notes);
        Assert.Null(_store.Latest(KostvUpdates.KindTv, 102100000));
        Assert.Null(_store.Latest(KostvUpdates.KindPhone, 102100001));
        var offered = _store.Latest(KostvUpdates.KindPhone, KostvApkFixtures.RealVersionCode);
        Assert.NotNull(offered);
        Assert.Equal("1.21.0", offered!.VersionName);

        var served = _store.Served(version.Id, KostvUpdates.KindTv);
        Assert.NotNull(served);
        Assert.Equal(version.Tv.Sha256, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(served!.Value.Path))).ToLowerInvariant());
        Assert.Null(_store.Served(version.Id, "desktop"));
        Assert.Null(_store.Served("../" + version.Id, KostvUpdates.KindTv));

        // The uploads were moved, not copied.
        Assert.Empty(Directory.GetFiles(Path.Combine(_root, "uploads")));
        var index = _store.Snapshot();
        Assert.Equal("com.kikope.kostv", index.PackageName);
        Assert.Equal(KostvApkFixtures.TestKey.Sha256, index.SignerSha256);
    }

    [Fact]
    public async Task FarBehindDevice_JumpsToTheNewest()
    {
        await PublishVersion(102100000, "1.21.0");
        await PublishVersion(102200000, "1.22.0");

        Assert.Equal("1.22.0", _store.Latest(KostvUpdates.KindTv, 1000000)!.VersionName);
    }

    [Fact]
    public async Task Retired_IsNeitherOfferedNorServed()
    {
        var first = await PublishVersion(102100000, "1.21.0");
        var bad = await PublishVersion(102200000, "1.22.0");

        _store.SetRetired(bad.Id, true);

        Assert.Equal(first.Id, _store.Latest(KostvUpdates.KindTv, 0)!.Id);
        Assert.Null(_store.Latest(KostvUpdates.KindTv, 102100000));
        Assert.Null(_store.Served(bad.Id, KostvUpdates.KindTv));

        _store.SetRetired(bad.Id, false);
        Assert.Equal(bad.Id, _store.Latest(KostvUpdates.KindTv, 102100000)!.Id);
    }

    [Fact]
    public async Task OnlyTheNewestNAreKept()
    {
        _store.SetKeep(2);
        var oldest = await PublishVersion(102100000, "1.21.0");
        await PublishVersion(102200000, "1.22.0");
        await PublishVersion(102300000, "1.23.0");

        var codes = _store.Snapshot().Versions.Select(v => v.VersionCode).ToList();
        Assert.Equal([102300000L, 102200000L], codes);
        Assert.False(Directory.Exists(Path.Combine(_root, "versions", oldest.Id)));
    }

    [Fact]
    public async Task TheOfferedVersion_IsNeverPruned()
    {
        var good = await PublishVersion(102100000, "1.21.0");
        var bad = await PublishVersion(102200000, "1.22.0");
        _store.SetRetired(bad.Id, true);

        _store.SetKeep(1);

        var ids = _store.Snapshot().Versions.Select(v => v.Id).ToList();
        Assert.Contains(bad.Id, ids); // the newest
        Assert.Contains(good.Id, ids); // the one offered
        Assert.Equal(good.Id, _store.Latest(KostvUpdates.KindTv, 0)!.Id);
    }

    [Fact]
    public async Task Delete_RemovesTheFiles()
    {
        var version = await PublishVersion(102100000, "1.21.0");
        _store.Delete(version.Id);

        Assert.Empty(_store.Snapshot().Versions);
        Assert.Null(_store.Latest(KostvUpdates.KindTv, 0));
        Assert.False(Directory.Exists(Path.Combine(_root, "versions", version.Id)));
        Assert.Equal(404, Assert.Throws<KostvUpdateException>(() => _store.Delete(version.Id)).Status);
    }

    [Fact]
    public async Task Index_SurvivesARestart()
    {
        var version = await PublishVersion(102100000, "1.21.0");
        _store.SetKeep(4);

        var again = new KostvUpdates(_root, () => _now);

        Assert.Equal(4, again.Snapshot().Keep);
        Assert.Equal(version.Id, again.Latest(KostvUpdates.KindPhone, 0)!.Id);
    }

    [Fact]
    public void Settings_AreChecked()
    {
        Assert.Equal(KostvUpdates.DefaultKeep, _store.Snapshot().Keep);
        Assert.Equal(400, Assert.Throws<KostvUpdateException>(() => _store.SetKeep(0)).Status);
        Assert.Equal(400, Assert.Throws<KostvUpdateException>(() => _store.SetSigner("abc")).Status);

        _store.SetSigner(KostvUpdates.Pretty(KostvApkFixtures.RealSignerSha256));
        Assert.Equal(KostvApkFixtures.RealSignerSha256, _store.Snapshot().SignerSha256);
    }

    // ------------------------------------------------------------------ install links

    [Fact]
    public void InstallLink_LastsHalfAnHour()
    {
        var links = new KostvInstallLinks(() => _now);
        var (token, expires) = links.Create();

        Assert.Equal(_now + TimeSpan.FromMinutes(30), expires);
        Assert.Equal(KostvInstallLinks.Result.Ok, links.Use(token, "1.2.3.4"));
        _now = _now.AddMinutes(29);
        Assert.Equal(KostvInstallLinks.Result.Ok, links.Use(token, "1.2.3.4"));
        _now = _now.AddMinutes(2);
        Assert.Equal(KostvInstallLinks.Result.Invalid, links.Use(token, "1.2.3.4"));
    }

    [Fact]
    public void InstallLink_GuessingIsSlowedDown()
    {
        var links = new KostvInstallLinks(() => _now);
        var (token, _) = links.Create();
        for (var i = 0; i < KostvInstallLinks.MaxFailuresPerMinute; i++)
        {
            Assert.Equal(KostvInstallLinks.Result.Invalid, links.Use("guess" + i, "5.6.7.8"));
        }

        Assert.Equal(KostvInstallLinks.Result.TooMany, links.Use(token, "5.6.7.8"));
        Assert.Equal(KostvInstallLinks.Result.Ok, links.Use(token, "1.2.3.4"));
        _now = _now.AddMinutes(1).AddSeconds(1);
        Assert.Equal(KostvInstallLinks.Result.Ok, links.Use(token, "5.6.7.8"));
    }

    [Fact]
    public void InstallLink_HasLimitedUses()
    {
        var links = new KostvInstallLinks(() => _now);
        var (token, _) = links.Create();
        for (var i = 0; i < KostvInstallLinks.MaxUsesPerLink; i++)
        {
            Assert.Equal(KostvInstallLinks.Result.Ok, links.Use(token, "addr" + i));
        }

        Assert.Equal(KostvInstallLinks.Result.Invalid, links.Use(token, "another"));
    }

    // ------------------------------------------------------------------ routes

    private KostvUpdatesController Controller(KostvInstallLinks? links = null) =>
        new(_store, links ?? new KostvInstallLinks(() => _now), new KostvInstallations(_root, () => _now, background: false))
        {
            ControllerContext = new ControllerContext { HttpContext = new Microsoft.AspNetCore.Http.DefaultHttpContext() }
        };

    private static string JsonOf(object? value) => JsonSerializer.Serialize(value);

    [Fact]
    public async Task UpdateRoute_FollowsTheContract()
    {
        var controller = Controller();

        Assert.IsType<BadRequestObjectResult>(controller.Get("ios").Result);
        Assert.IsType<BadRequestObjectResult>(controller.Get(null).Result);

        var none = Assert.IsType<OkObjectResult>(controller.Get("tv", 5).Result);
        Assert.Equal("{\"Available\":false}", JsonOf(none.Value));

        var version = await PublishVersion(102100000, "1.21.0", "Notas");
        var some = Assert.IsType<OkObjectResult>(controller.Get("phone", KostvApkFixtures.RealVersionCode).Result);
        using var json = JsonDocument.Parse(JsonOf(some.Value));
        var root = json.RootElement;
        Assert.True(root.GetProperty("Available").GetBoolean());
        Assert.Equal("1.21.0", root.GetProperty("VersionName").GetString());
        Assert.Equal(102100000, root.GetProperty("VersionCode").GetInt64());
        Assert.Equal("Notas", root.GetProperty("Notes").GetString());
        Assert.Equal("2026-11-22T10:01:00Z", root.GetProperty("Date").GetString());
        Assert.Equal(version.Phone.Size, root.GetProperty("Size").GetInt64());
        Assert.Equal(version.Phone.Sha256, root.GetProperty("Sha256").GetString());
        Assert.Equal("/Moonfin/Kostv/Update/Download/102100000/phone.apk", root.GetProperty("Url").GetString());
    }

    [Fact]
    public async Task DownloadRoute_ServesOnlyWhatIsOffered()
    {
        var controller = Controller();
        var version = await PublishVersion(102100000, "1.21.0");

        var file = Assert.IsType<PhysicalFileResult>(controller.Download(version.Id, "tv"));
        Assert.True(file.EnableRangeProcessing);
        Assert.Equal(KostvUpdatesController.ApkContentType, file.ContentType);
        Assert.Equal("\"" + version.Tv.Sha256 + "\"", file.EntityTag!.Tag.ToString());

        Assert.IsType<NotFoundObjectResult>(controller.Download("999", "tv"));
        Assert.IsType<NotFoundObjectResult>(controller.Download(version.Id, "ios"));
        _store.SetRetired(version.Id, true);
        Assert.IsType<NotFoundObjectResult>(controller.Download(version.Id, "tv"));
    }

    [Fact]
    public async Task InstallRoute_NeedsAGoodLink()
    {
        var links = new KostvInstallLinks(() => _now);
        var controller = Controller(links);
        await PublishVersion(102100000, "1.21.0");
        var (token, _) = links.Create();

        Assert.IsType<NotFoundObjectResult>(controller.Install("nope", "tv"));
        Assert.IsType<NotFoundObjectResult>(controller.Install(token, "ios"));
        var file = Assert.IsType<PhysicalFileResult>(controller.Install(token, "phone"));
        Assert.Equal("KosTV_Android.apk", file.FileDownloadName);
        Assert.True(file.EnableRangeProcessing);

        // The short address the panel shows: «tele» and «movil», and the code in any case.
        var tele = Assert.IsType<PhysicalFileResult>(controller.Install(token.ToLowerInvariant(), "tele"));
        Assert.Equal("KosTV_AndroidTV.apk", tele.FileDownloadName);
        Assert.Equal("KosTV_Android.apk", Assert.IsType<PhysicalFileResult>(controller.Install(token, "movil")).FileDownloadName);
        var link = Assert.IsType<OkObjectResult>(controller.InstallLink()).Value as KostvUpdatesController.InstallLinkDto;
        Assert.Matches("^/KosTV/Instalar/[2-9A-HJKMNP-Z]{8}/tele\\.apk$", link!.TvPath);
        Assert.Matches("^/KosTV/Instalar/[2-9A-HJKMNP-Z]{8}/movil\\.apk$", link.PhonePath);
        Assert.True(link.Available);

        _now = _now.AddMinutes(31);
        Assert.IsType<NotFoundObjectResult>(controller.Install(token, "tv"));
    }

    private static void SignIn(KostvUpdatesController controller, string userId, string name, string? deviceId, string? device, string? header = null)
    {
        var claims = new List<System.Security.Claims.Claim>
        {
            new("Jellyfin-UserId", userId),
            new(System.Security.Claims.ClaimTypes.Name, name)
        };
        if (deviceId != null)
        {
            claims.Add(new("Jellyfin-DeviceId", deviceId));
        }

        if (device != null)
        {
            claims.Add(new("Jellyfin-Device", device));
        }

        var context = new Microsoft.AspNetCore.Http.DefaultHttpContext
        {
            User = new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity(claims, "Custom"))
        };
        if (header != null)
        {
            context.Request.Headers.Authorization = header;
        }

        controller.ControllerContext = new ControllerContext { HttpContext = context };
    }

    [Fact]
    public async Task UpdateRoute_RecordsTheInstallation_AndThePanelListsIt()
    {
        var mother = Guid.NewGuid();
        var son = Guid.NewGuid();
        var controller = Controller();

        // Nothing published yet: everyone counts as up to date.
        SignIn(controller, mother.ToString(), "Mamá", "tv-salon", "Tele del salón");
        Assert.IsType<OkObjectResult>(controller.Get("tv", KostvApkFixtures.RealVersionCode).Result);
        var empty = Assert.IsType<OkObjectResult>(controller.Installations().Result).Value as KostvUpdatesController.InstallationsDto;
        var only = Assert.Single(empty!.Installations);
        Assert.True(only.UpToDate);
        Assert.Null(only.LatestVersionName);

        await PublishVersion(102100000, "1.21.0");
        _now = _now.AddMinutes(1);
        // A device the claims don't name: the authorization header tells it (values URL-encoded).
        SignIn(controller, son.ToString(), "Kiko", null, null,
            "MediaBrowser Client=\"kOS TV\", Device=\"Pixel%208\", DeviceId=\"pixel-1\", Version=\"1.21.0\", Token=\"x\"");
        Assert.IsType<OkObjectResult>(controller.Get("phone", 102100000).Result);
        // The wrong kind is turned down and not recorded.
        Assert.IsType<BadRequestObjectResult>(controller.Get("ios", 102100000).Result);

        var state = Assert.IsType<OkObjectResult>(controller.Installations().Result).Value as KostvUpdatesController.InstallationsDto;
        Assert.Equal(14, state!.Days);
        Assert.Equal(2, state.Total);
        Assert.Equal(1, state.UpToDate);

        var tv = state.Installations.Single(i => i.Kind == "tv");
        Assert.Equal(mother.ToString("N"), tv.UserId);
        Assert.Equal("Mamá", tv.UserName);
        Assert.Equal("Tele del salón", tv.DeviceName);
        Assert.Equal("1.20.0", tv.VersionName);
        Assert.Equal("2026-11-22T10:00:00Z", tv.LastSeen);
        Assert.False(tv.UpToDate);
        Assert.Equal("1.21.0", tv.LatestVersionName);
        Assert.Equal(102100000, tv.LatestVersionCode);

        var phone = state.Installations.Single(i => i.Kind == "phone");
        Assert.Equal("Kiko", phone.UserName);
        Assert.Equal("Pixel 8", phone.DeviceName);
        Assert.True(phone.UpToDate);

        // Retiring the newest compares with the one offered now.
        _store.SetRetired("102100000", true);
        state = Assert.IsType<OkObjectResult>(controller.Installations().Result).Value as KostvUpdatesController.InstallationsDto;
        Assert.Equal(2, state!.UpToDate);

        // «Quitar».
        var removed = Assert.IsType<OkObjectResult>(controller.RemoveInstallation(tv.Id).Result).Value as KostvUpdatesController.InstallationsDto;
        Assert.Equal("phone", Assert.Single(removed!.Installations).Kind);
        Assert.IsType<NotFoundObjectResult>(controller.RemoveInstallation(tv.Id).Result);
    }

    [Fact]
    public void UpdateRoute_AnswersEvenIfTheListCannotBeWritten()
    {
        // The data folder is a file: nothing can be written there.
        Directory.CreateDirectory(Path.GetDirectoryName(_root)!);
        File.WriteAllText(_root, "no soy una carpeta");
        try
        {
            var controller = new KostvUpdatesController(_store, new KostvInstallLinks(() => _now), new KostvInstallations(_root, () => _now, background: false));
            SignIn(controller, Guid.NewGuid().ToString(), "Mamá", "tv-salon", "Tele");
            var answer = Assert.IsType<OkObjectResult>(controller.Get("tv", 5).Result);
            Assert.Equal("{\"Available\":false}", JsonOf(answer.Value));
        }
        finally
        {
            File.Delete(_root);
        }
    }

    [Theory]
    [InlineData("MediaBrowser Client=\"kOS TV\", Device=\"Tele%20sal%C3%B3n\", DeviceId=\"abc\"", "Device", "Tele salón")]
    [InlineData("MediaBrowser Client=\"kOS TV\", Device=\"Tele\", DeviceId=\"abc\"", "DeviceId", "abc")]
    [InlineData("MediaBrowser Token=\"x\"", "DeviceId", null)]
    [InlineData("", "Device", null)]
    public void AuthorizationValue_ReadsTheHeader(string header, string field, string? expected) =>
        Assert.Equal(expected, KostvUpdatesController.AuthorizationValue(header, field));

    [Fact]
    public void Routes_HaveTheRightAuthorization()
    {
        var anonymous = new HashSet<string> { nameof(KostvUpdatesController.Install) };
        var forAnyone = new HashSet<string> { nameof(KostvUpdatesController.Get), nameof(KostvUpdatesController.Download) };
        var actions = typeof(KostvUpdatesController)
            .GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
            .Where(m => m.GetCustomAttributes<Microsoft.AspNetCore.Mvc.Routing.HttpMethodAttribute>().Any())
            .ToList();
        Assert.True(actions.Count >= 12);

        foreach (var action in actions)
        {
            var authorize = action.GetCustomAttribute<AuthorizeAttribute>();
            var allow = action.GetCustomAttribute<AllowAnonymousAttribute>();
            if (anonymous.Contains(action.Name))
            {
                Assert.NotNull(allow);
                Assert.Null(authorize);
            }
            else if (forAnyone.Contains(action.Name))
            {
                Assert.NotNull(authorize);
                Assert.Null(authorize!.Policy);
                Assert.Null(allow);
            }
            else
            {
                Assert.True(authorize?.Policy == "RequiresElevation", action.Name + " must be admin-only");
                Assert.Null(allow);
            }
        }
    }

    [Fact]
    public void ChunkRoute_AcceptsAWholeChunk()
    {
        var limit = typeof(KostvUpdatesController).GetMethod(nameof(KostvUpdatesController.UploadChunk))!
            .GetCustomAttribute<RequestSizeLimitAttribute>();
        Assert.NotNull(limit);
        Assert.True(KostvUpdates.ChunkBytes < KostvUpdates.MaxChunkBytes);
        // Under Kestrel's default 30 MB, so no server setting is needed.
        Assert.True(KostvUpdates.MaxChunkBytes + (1024 * 1024) < 30_000_000);
    }

    /// <summary>A body that breaks after <c>after</c> bytes, like a cut connection.</summary>
    private sealed class BreakingStream : MemoryStream
    {
        private readonly int _after;

        public BreakingStream(byte[] data, int after)
            : base(data)
        {
            _after = after;
        }

        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (Position >= _after)
            {
                throw new IOException("connection reset");
            }

            return await base.ReadAsync(buffer[..Math.Min(buffer.Length, _after - (int)Position)], cancellationToken);
        }
    }
}
