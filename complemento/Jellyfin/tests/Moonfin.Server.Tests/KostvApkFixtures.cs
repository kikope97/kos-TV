using System.Buffers.Binary;
using System.IO.Compression;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace Moonfin.Server.Tests;

/// <summary>
/// kOS TV: small APKs for the update store's tests, built here rather than checked in. The
/// manifests in <c>Fixtures/Updates</c> are the compiled AndroidManifest.xml of the real 1.20.0
/// TV and phone builds, and <c>kostv-v2-signer.bin</c> is the v2 signer of those APKs (public:
/// it ships in every APK). The APKs are signed here with throwaway test keys, never kOS TV's.
/// </summary>
internal static class KostvApkFixtures
{
    public const string RealSignerSha256 = "601fd7abd0e5e137ce7c3ecc7bd86d14ae531f8b3b40959088c93c109a40dee7";
    public const long RealVersionCode = 102000000;

    public static string Dir([CallerFilePath] string here = "") =>
        Path.Combine(Path.GetDirectoryName(here)!, "Fixtures", "Updates");

    public static byte[] TvManifest => File.ReadAllBytes(Path.Combine(Dir(), "AndroidManifest-tv.axml"));

    public static byte[] PhoneManifest => File.ReadAllBytes(Path.Combine(Dir(), "AndroidManifest-phone.axml"));

    public static byte[] RealSigner => File.ReadAllBytes(Path.Combine(Dir(), "kostv-v2-signer.bin"));

    /// <summary>A signing key and its self-signed certificate.</summary>
    public sealed class Key
    {
        public required AsymmetricAlgorithm Algorithm { get; init; }

        public required byte[] Certificate { get; init; }

        public string Sha256 => Convert.ToHexString(SHA256.HashData(Certificate)).ToLowerInvariant();
    }

    private static readonly Lazy<Key> _rsa = new(() => MakeRsa("CN=kOS TV Test"));
    private static readonly Lazy<Key> _otherRsa = new(() => MakeRsa("CN=Someone Else"));
    private static readonly Lazy<Key> _debug = new(() => MakeRsa("CN=Android Debug, O=Android, C=US"));

    public static Key TestKey => _rsa.Value;

    public static Key OtherKey => _otherRsa.Value;

    public static Key DebugKey => _debug.Value;

    private static Key MakeRsa(string subject)
    {
        var rsa = RSA.Create(2048);
        var request = new CertificateRequest(subject, rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(30));
        return new Key { Algorithm = rsa, Certificate = cert.RawData };
    }

    public static Key MakeEc()
    {
        var ec = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var request = new CertificateRequest("CN=kOS TV EC Test", ec, HashAlgorithmName.SHA256);
        using var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(30));
        return new Key { Algorithm = ec, Certificate = cert.RawData };
    }

    /// <summary>A plain (unsigned) ZIP with the manifest and a little filler.</summary>
    public static byte[] Zip(byte[] manifest, int fillerBytes = 3 * 1024 * 1024)
    {
        using var buffer = new MemoryStream();
        using (var zip = new ZipArchive(buffer, ZipArchiveMode.Create, leaveOpen: true))
        {
            using (var entry = zip.CreateEntry("AndroidManifest.xml", CompressionLevel.Optimal).Open())
            {
                entry.Write(manifest);
            }

            // Stored, and over 1 MB, so the digest goes over several chunks.
            var filler = new byte[fillerBytes];
            new Random(7).NextBytes(filler);
            using (var entry = zip.CreateEntry("assets/filler.bin", CompressionLevel.NoCompression).Open())
            {
                entry.Write(filler);
            }
        }

        return buffer.ToArray();
    }

    /// <summary>
    /// <paramref name="zip"/> signed with APK Signature Scheme v2 (or v3) by <paramref name="key"/>,
    /// written from the published format independently of the code under test.
    /// </summary>
    public static byte[] Sign(byte[] zip, Key key, int scheme = 2)
    {
        var eocdAt = LastIndexOf(zip, [0x50, 0x4b, 0x05, 0x06]);
        var cdSize = (int)BinaryPrimitives.ReadUInt32LittleEndian(zip.AsSpan(eocdAt + 12));
        var cdOffset = (int)BinaryPrimitives.ReadUInt32LittleEndian(zip.AsSpan(eocdAt + 16));
        var entries = zip[..cdOffset];
        var cd = zip[cdOffset..(cdOffset + cdSize)];
        var eocd = zip[eocdAt..];

        var rsa = key.Algorithm is RSA;
        var algorithm = rsa ? 0x0103 : 0x0201;

        // Content digest (SHA-256 chunks); the end record points at where the block will start.
        var digestEocd = (byte[])eocd.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(digestEocd.AsSpan(16), (uint)cdOffset);
        var chunks = new List<byte[]>();
        foreach (var section in new[] { entries, cd, digestEocd })
        {
            for (var at = 0; at < section.Length; at += 1024 * 1024)
            {
                var piece = section.AsSpan(at, Math.Min(1024 * 1024, section.Length - at));
                chunks.Add(SHA256.HashData([0xa5, .. U32(piece.Length), .. piece]));
            }
        }

        var digest = SHA256.HashData([0x5a, .. U32(chunks.Count), .. chunks.SelectMany(c => c)]);

        byte[] signedData = [
            .. Lp(Lp([.. U32(algorithm), .. Lp(digest)])),
            .. Lp(Lp(key.Certificate)),
            .. (scheme == 3 ? [.. U32(24), .. U32(int.MaxValue)] : Array.Empty<byte>()),
            .. Lp([])];
        var signature = rsa
            ? ((RSA)key.Algorithm).SignData(signedData, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)
            : ((ECDsa)key.Algorithm).SignData(signedData, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        var publicKey = key.Algorithm is RSA r ? r.ExportSubjectPublicKeyInfo() : ((ECDsa)key.Algorithm).ExportSubjectPublicKeyInfo();
        byte[] signer = [
            .. Lp(signedData),
            .. (scheme == 3 ? [.. U32(24), .. U32(int.MaxValue)] : Array.Empty<byte>()),
            .. Lp(Lp([.. U32(algorithm), .. Lp(signature)])),
            .. Lp(publicKey)];
        var value = Lp(Lp(signer));
        var id = scheme == 3 ? 0xf05368c0u : 0x7109871au;
        byte[] pair = [.. U64(value.Length + 4), .. U32((int)id), .. value];
        var size = pair.Length + 8 + 16;
        byte[] block = [.. U64(size), .. pair, .. U64(size), .. "APK Sig Block 42"u8];

        var newEocd = (byte[])eocd.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(newEocd.AsSpan(16), (uint)(cdOffset + block.Length));
        return [.. entries, .. block, .. cd, .. newEocd];
    }

    public static byte[] SignedApk(byte[] manifest, Key? key = null) => Sign(Zip(manifest), key ?? TestKey);

    /// <summary>A copy of the TV or phone manifest with another versionCode and versionName.</summary>
    public static byte[] WithVersion(byte[] manifest, long code, string name)
    {
        // The real manifests carry versionName "1.20.0" in the string pool and the code as a
        // typed int; both are patched in place (the new name must keep the length).
        if (name.Length != "1.20.0".Length)
        {
            throw new ArgumentException("Keep the name 6 characters long", nameof(name));
        }

        var copy = (byte[])manifest.Clone();
        var codeBytes = U32((int)RealVersionCode);
        var at = IndexOf(copy, codeBytes);
        BinaryPrimitives.WriteUInt32LittleEndian(copy.AsSpan(at), (uint)code);
        var oldName = System.Text.Encoding.UTF8.GetBytes("1.20.0");
        var nameAt = IndexOf(copy, oldName);
        if (nameAt < 0)
        {
            oldName = System.Text.Encoding.Unicode.GetBytes("1.20.0");
            nameAt = IndexOf(copy, oldName);
            System.Text.Encoding.Unicode.GetBytes(name).CopyTo(copy, nameAt);
        }
        else
        {
            System.Text.Encoding.UTF8.GetBytes(name).CopyTo(copy, nameAt);
        }

        return copy;
    }

    private static byte[] U32(int value)
    {
        var bytes = new byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, (uint)value);
        return bytes;
    }

    private static byte[] U64(long value)
    {
        var bytes = new byte[8];
        BinaryPrimitives.WriteUInt64LittleEndian(bytes, (ulong)value);
        return bytes;
    }

    private static byte[] Lp(byte[] data) => [.. U32(data.Length), .. data];

    private static int IndexOf(byte[] data, byte[] needle) => data.AsSpan().IndexOf(needle);

    private static int LastIndexOf(byte[] data, byte[] needle) => data.AsSpan().LastIndexOf(needle);
}
