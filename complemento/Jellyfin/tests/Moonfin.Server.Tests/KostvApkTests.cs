using System.Security.Cryptography;
using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: reading the version, the kind of build and the signer of an APK.</summary>
public class KostvApkTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "kostv-apk-" + Guid.NewGuid().ToString("N"));

    public KostvApkTests() => Directory.CreateDirectory(_dir);

    public void Dispose() => Directory.Delete(_dir, recursive: true);

    private string Write(byte[] bytes)
    {
        var path = Path.Combine(_dir, Guid.NewGuid().ToString("N") + ".apk");
        File.WriteAllBytes(path, bytes);
        return path;
    }

    [Fact]
    public void TvManifest_IsReadAsTheTvBuild()
    {
        var info = KostvApk.ReadManifest(KostvApkFixtures.TvManifest);

        Assert.Equal("com.kikope.kostv", info.PackageName);
        Assert.Equal("1.20.0", info.VersionName);
        Assert.Equal(KostvApkFixtures.RealVersionCode, info.VersionCode);
        Assert.True(info.IsTv);
    }

    [Fact]
    public void PhoneManifest_IsReadAsThePhoneBuild()
    {
        // The phone build declares leanback as not required, so it isn't the TV one.
        var info = KostvApk.ReadManifest(KostvApkFixtures.PhoneManifest);

        Assert.Equal("com.kikope.kostv", info.PackageName);
        Assert.Equal("1.20.0", info.VersionName);
        Assert.Equal(KostvApkFixtures.RealVersionCode, info.VersionCode);
        Assert.False(info.IsTv);
    }

    [Fact]
    public void PatchedManifest_GivesTheNewVersion()
    {
        var info = KostvApk.ReadManifest(KostvApkFixtures.WithVersion(KostvApkFixtures.TvManifest, 102100000, "1.21.0"));

        Assert.Equal("1.21.0", info.VersionName);
        Assert.Equal(102100000, info.VersionCode);
    }

    [Fact]
    public void GarbageManifest_IsRefused()
    {
        Assert.Throws<KostvApkException>(() => KostvApk.ReadManifest([3, 0, 8, 0, 255, 255, 255, 127, 1, 2]));
        Assert.Throws<KostvApkException>(() => KostvApk.ReadManifest([1, 2, 3]));
        var truncated = KostvApkFixtures.TvManifest[..4000];
        Assert.Throws<KostvApkException>(() => KostvApk.ReadManifest(truncated));
    }

    [Fact]
    public void RealSigner_IsCheckedAndGivesKostvFingerprint()
    {
        // The real 1.20.0 signer: RSA with SHA-512, its signature over the signed data checked.
        var signer = KostvApk.ParseSigner(KostvApkFixtures.RealSigner, 2);

        Assert.Equal(KostvApkFixtures.RealSignerSha256, signer.Info.Sha256);
        Assert.Equal(0x0104, signer.DigestAlgorithm);
        Assert.Equal(64, signer.ExpectedDigest.Length);
        Assert.False(new KostvApkInfo { SignerSubject = signer.Info.Subject }.IsDebugSigned);
    }

    [Fact]
    public void RealSigner_Tampered_IsRefused()
    {
        var bytes = KostvApkFixtures.RealSigner;
        bytes[40] ^= 0x01; // inside the content digest of the signed data
        Assert.Throws<KostvApkException>(() => KostvApk.ParseSigner(bytes, 2));
    }

    [Fact]
    public void SignedApk_IsReadWholly()
    {
        var path = Write(KostvApkFixtures.SignedApk(KostvApkFixtures.TvManifest));

        var info = KostvApk.Read(path);

        Assert.Equal("1.20.0", info.VersionName);
        Assert.True(info.IsTv);
        Assert.Equal(KostvApkFixtures.TestKey.Sha256, info.SignerSha256);
        Assert.Equal(2, info.SchemeVersion);
        Assert.Contains("kOS TV Test", info.SignerSubject);
    }

    [Fact]
    public void V3AndEcSignatures_AreRead()
    {
        var ec = KostvApkFixtures.MakeEc();
        var path = Write(KostvApkFixtures.Sign(KostvApkFixtures.Zip(KostvApkFixtures.PhoneManifest), ec, scheme: 3));

        var info = KostvApk.Read(path);

        Assert.Equal(3, info.SchemeVersion);
        Assert.Equal(ec.Sha256, info.SignerSha256);
        Assert.False(info.IsTv);
    }

    [Fact]
    public void DebugKey_IsSpotted()
    {
        var info = KostvApk.Read(Write(KostvApkFixtures.SignedApk(KostvApkFixtures.TvManifest, KostvApkFixtures.DebugKey)));
        Assert.True(info.IsDebugSigned);
    }

    [Fact]
    public void ApkChangedAfterSigning_IsRefused()
    {
        var bytes = KostvApkFixtures.SignedApk(KostvApkFixtures.TvManifest);
        bytes[bytes.Length / 3] ^= 0x01; // inside the stored filler
        var error = Assert.Throws<KostvApkException>(() => KostvApk.Read(Write(bytes)));
        Assert.Contains("no es válida", error.Message);
    }

    [Fact]
    public void UnsignedZip_IsRefused()
    {
        var error = Assert.Throws<KostvApkException>(() => KostvApk.Read(Write(KostvApkFixtures.Zip(KostvApkFixtures.TvManifest))));
        Assert.Contains("no está firmado", error.Message);
    }

    [Fact]
    public void NotAZip_IsRefused()
    {
        Assert.Throws<KostvApkException>(() => KostvApk.Read(Write(RandomNumberGenerator.GetBytes(4096))));
        Assert.Throws<KostvApkException>(() => KostvApk.Read(Write([1, 2, 3])));
    }

    [Fact]
    public void ZipWithoutManifest_IsRefused()
    {
        var zip = KostvApkFixtures.Sign(KostvApkFixtures.Zip([]), KostvApkFixtures.TestKey);
        Assert.Throws<KostvApkException>(() => KostvApk.Read(Write(zip)));
    }

    /// <summary>
    /// The real 1.20.0 APKs, when KOSTV_REAL_APK_DIR points at a folder with tv.apk and
    /// phone.apk (they are 125 MB each, so they aren't in the repository).
    /// </summary>
    [Fact]
    public void RealApks_WhenAvailable()
    {
        var dir = Environment.GetEnvironmentVariable("KOSTV_REAL_APK_DIR");
        if (string.IsNullOrEmpty(dir) || !File.Exists(Path.Combine(dir, "tv.apk")))
        {
            return;
        }

        var tv = KostvApk.Read(Path.Combine(dir, "tv.apk"));
        var phone = KostvApk.Read(Path.Combine(dir, "phone.apk"));

        Assert.True(tv.IsTv);
        Assert.False(phone.IsTv);
        Assert.Equal(KostvApkFixtures.RealSignerSha256, tv.SignerSha256);
        Assert.Equal(KostvApkFixtures.RealSignerSha256, phone.SignerSha256);
        Assert.Equal(KostvApkFixtures.RealVersionCode, tv.VersionCode);
        Assert.Equal("1.20.0", phone.VersionName);
    }
}
