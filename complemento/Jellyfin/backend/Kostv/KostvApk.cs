using System.Buffers.Binary;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace Moonfin.Server.Kostv;

/// <summary>What the update store needs to know about an uploaded APK.</summary>
public sealed class KostvApkInfo
{
    public string PackageName { get; init; } = string.Empty;

    public string VersionName { get; init; } = string.Empty;

    public long VersionCode { get; init; }

    /// <summary>
    /// The TV build: its manifest asks for the leanback feature (required). The phone build
    /// declares it as not required, so it installs on both, which is why the two are never
    /// crossed.
    /// </summary>
    public bool IsTv { get; init; }

    /// <summary>SHA-256 of the signer's certificate, lowercase hex without separators.</summary>
    public string SignerSha256 { get; init; } = string.Empty;

    /// <summary>The signer certificate's subject, to show and to spot the debug key.</summary>
    public string SignerSubject { get; init; } = string.Empty;

    /// <summary>Which APK Signature Scheme the signature was read from (2 or 3).</summary>
    public int SchemeVersion { get; init; }

    public bool IsDebugSigned =>
        SignerSubject.Contains("CN=Android Debug", StringComparison.OrdinalIgnoreCase);
}

/// <summary>Why an APK could not be read, in Spanish for the admin page.</summary>
public sealed class KostvApkException : Exception
{
    public KostvApkException(string message)
        : base(message)
    {
    }
}

/// <summary>
/// kOS TV: reads an APK without any Android tools: the version and the kind of build from its
/// binary AndroidManifest.xml, and the signer from its APK Signature Scheme v2/v3 block, which
/// is checked for real (the signature over the signed data and the digest of the whole file),
/// so a certificate copied into a different APK doesn't pass.
/// </summary>
public static class KostvApk
{
    /// <summary>The largest manifest read; real ones are a few tens of KB.</summary>
    private const int MaxManifestBytes = 8 * 1024 * 1024;

    public static KostvApkInfo Read(string path)
    {
        ManifestInfo manifest;
        try
        {
            using var zip = ZipFile.OpenRead(path);
            var entry = zip.GetEntry("AndroidManifest.xml")
                ?? throw new KostvApkException("No es un APK: le falta el AndroidManifest.xml.");
            if (entry.Length > MaxManifestBytes)
            {
                throw new KostvApkException("No es un APK válido: el AndroidManifest.xml es demasiado grande.");
            }

            using var stream = entry.Open();
            using var buffer = new MemoryStream();
            stream.CopyTo(buffer);
            manifest = ReadManifest(buffer.ToArray());
        }
        catch (InvalidDataException)
        {
            throw new KostvApkException("No es un APK: el archivo no es un ZIP válido.");
        }

        var signer = VerifySignature(path);
        return new KostvApkInfo
        {
            PackageName = manifest.PackageName,
            VersionName = manifest.VersionName,
            VersionCode = manifest.VersionCode,
            IsTv = manifest.IsTv,
            SignerSha256 = signer.Sha256,
            SignerSubject = signer.Subject,
            SchemeVersion = signer.Scheme
        };
    }

    // ---------------------------------------------------------------- manifest (binary XML)

    public sealed record ManifestInfo(string PackageName, string VersionName, long VersionCode, bool IsTv);

    private const uint AttrName = 0x01010003;
    private const uint AttrVersionCode = 0x0101021b;
    private const uint AttrVersionName = 0x0101021c;
    private const uint AttrRequired = 0x0101028e;

    private const byte TypeReference = 0x01;
    private const byte TypeString = 0x03;
    private const byte TypeIntDec = 0x10;
    private const byte TypeIntHex = 0x11;
    private const byte TypeBool = 0x12;

    private readonly record struct Attr(uint ResId, string Name, int RawString, byte Type, uint Data);

    /// <summary>Reads the bits of the compiled AndroidManifest.xml the store needs.</summary>
    public static ManifestInfo ReadManifest(byte[] axml)
    {
        static KostvApkException Bad() => new("No es un APK válido: no se entiende su AndroidManifest.xml.");
        if (axml.Length < 8 || BinaryPrimitives.ReadUInt16LittleEndian(axml) != 0x0003)
        {
            throw Bad();
        }

        string[] strings = [];
        uint[] resIds = [];
        var path = new List<string>();
        string? package = null;
        string? versionName = null;
        long? versionCode = null;
        var tv = false;

        try
        {
            int p = BinaryPrimitives.ReadUInt16LittleEndian(axml.AsSpan(2));
            while (p + 8 <= axml.Length)
            {
                var type = BinaryPrimitives.ReadUInt16LittleEndian(axml.AsSpan(p));
                var headerSize = BinaryPrimitives.ReadUInt16LittleEndian(axml.AsSpan(p + 2));
                var size = (int)BinaryPrimitives.ReadUInt32LittleEndian(axml.AsSpan(p + 4));
                if (size < 8 || p + size > axml.Length)
                {
                    throw Bad();
                }

                var chunk = axml.AsSpan(p, size);
                switch (type)
                {
                    case 0x0001:
                        strings = ReadStringPool(chunk);
                        break;
                    case 0x0180:
                        resIds = new uint[(size - headerSize) / 4];
                        for (var i = 0; i < resIds.Length; i++)
                        {
                            resIds[i] = BinaryPrimitives.ReadUInt32LittleEndian(chunk[(headerSize + (i * 4))..]);
                        }

                        break;
                    case 0x0102:
                        {
                            var name = StringAt(strings, BinaryPrimitives.ReadInt32LittleEndian(chunk[20..]));
                            path.Add(name);
                            var attrStart = BinaryPrimitives.ReadUInt16LittleEndian(chunk[24..]);
                            var attrSize = BinaryPrimitives.ReadUInt16LittleEndian(chunk[26..]);
                            var attrCount = BinaryPrimitives.ReadUInt16LittleEndian(chunk[28..]);
                            var attrs = new List<Attr>(attrCount);
                            for (var i = 0; i < attrCount; i++)
                            {
                                var a = chunk[(16 + attrStart + (i * attrSize))..];
                                var nameIndex = BinaryPrimitives.ReadInt32LittleEndian(a[4..]);
                                attrs.Add(new Attr(
                                    nameIndex >= 0 && nameIndex < resIds.Length ? resIds[nameIndex] : 0,
                                    StringAt(strings, nameIndex),
                                    BinaryPrimitives.ReadInt32LittleEndian(a[8..]),
                                    a[15],
                                    BinaryPrimitives.ReadUInt32LittleEndian(a[16..])));
                            }

                            if (path.Count == 1 && name == "manifest")
                            {
                                package = TextOf(attrs, 0, "package", strings);
                                versionName = TextOf(attrs, AttrVersionName, "versionName", strings);
                                var code = Find(attrs, AttrVersionCode, "versionCode");
                                if (code is { } c && c.Type is TypeIntDec or TypeIntHex)
                                {
                                    versionCode = c.Data;
                                }
                            }
                            else if (path.Count == 2 && path[0] == "manifest" && name == "uses-feature"
                                && TextOf(attrs, AttrName, "name", strings) == "android.software.leanback")
                            {
                                // android:required defaults to true when it isn't written.
                                var required = Find(attrs, AttrRequired, "required");
                                tv |= required is not { } r || r.Type != TypeBool || r.Data != 0;
                            }

                            break;
                        }

                    case 0x0103:
                        if (path.Count > 0)
                        {
                            path.RemoveAt(path.Count - 1);
                        }

                        break;
                }

                p += size;
            }
        }
        catch (ArgumentOutOfRangeException)
        {
            throw Bad();
        }

        if (string.IsNullOrWhiteSpace(package))
        {
            throw Bad();
        }

        if (versionCode is null || versionCode <= 0 || string.IsNullOrWhiteSpace(versionName))
        {
            throw new KostvApkException("No se ha podido leer el número de versión del APK.");
        }

        return new ManifestInfo(package, versionName, versionCode.Value, tv);
    }

    private static Attr? Find(List<Attr> attrs, uint resId, string name)
    {
        foreach (var a in attrs)
        {
            if (resId != 0 && a.ResId == resId)
            {
                return a;
            }
        }

        // Without a resource id (package) or with stripped ids, by name.
        foreach (var a in attrs)
        {
            if ((resId == 0 || a.ResId == 0) && a.Name == name)
            {
                return a;
            }
        }

        return null;
    }

    private static string? TextOf(List<Attr> attrs, uint resId, string name, string[] strings)
    {
        if (Find(attrs, resId, name) is not { } a)
        {
            return null;
        }

        if (a.RawString >= 0)
        {
            return StringAt(strings, a.RawString);
        }

        return a.Type == TypeString ? StringAt(strings, (int)a.Data) : null;
    }

    private static string StringAt(string[] strings, int index) =>
        index >= 0 && index < strings.Length ? strings[index] : string.Empty;

    private static string[] ReadStringPool(ReadOnlySpan<byte> chunk)
    {
        var headerSize = BinaryPrimitives.ReadUInt16LittleEndian(chunk[2..]);
        var count = (int)BinaryPrimitives.ReadUInt32LittleEndian(chunk[8..]);
        var flags = BinaryPrimitives.ReadUInt32LittleEndian(chunk[16..]);
        var stringsStart = (int)BinaryPrimitives.ReadUInt32LittleEndian(chunk[20..]);
        var utf8 = (flags & 0x100) != 0;
        if (count < 0 || count > 1_000_000)
        {
            throw new ArgumentOutOfRangeException(nameof(chunk));
        }

        var result = new string[count];
        for (var i = 0; i < count; i++)
        {
            var p = stringsStart + (int)BinaryPrimitives.ReadUInt32LittleEndian(chunk[(headerSize + (i * 4))..]);
            if (utf8)
            {
                // UTF-16 length first, then the UTF-8 byte length, each one or two bytes.
                p += (chunk[p] & 0x80) != 0 ? 2 : 1;
                int length = chunk[p];
                if ((length & 0x80) != 0)
                {
                    length = ((length & 0x7f) << 8) | chunk[p + 1];
                    p += 2;
                }
                else
                {
                    p += 1;
                }

                result[i] = Encoding.UTF8.GetString(chunk.Slice(p, length));
            }
            else
            {
                int length = BinaryPrimitives.ReadUInt16LittleEndian(chunk[p..]);
                p += 2;
                if ((length & 0x8000) != 0)
                {
                    length = ((length & 0x7fff) << 16) | BinaryPrimitives.ReadUInt16LittleEndian(chunk[p..]);
                    p += 2;
                }

                result[i] = Encoding.Unicode.GetString(chunk.Slice(p, length * 2));
            }
        }

        return result;
    }

    // ---------------------------------------------------------------- signature (v2 / v3)

    public sealed record SignerInfo(string Sha256, string Subject, int Scheme);

    public const uint BlockIdV2 = 0x7109871a;
    public const uint BlockIdV3 = 0xf05368c0;
    public const uint BlockIdV31 = 0x1b93ad61;

    private static readonly byte[] BlockMagic = "APK Sig Block 42"u8.ToArray();
    private const int ChunkSize = 1024 * 1024;

    private static KostvApkException Unsigned() =>
        new("El APK no está firmado con el esquema de firma v2 o v3 de Android.");

    private static KostvApkException BadSignature() =>
        new("La firma del APK no es válida: el archivo está dañado o se modificó después de firmarlo.");

    /// <summary>Checks the APK's v3 (or else v2) signature and returns its signer.</summary>
    public static SignerInfo VerifySignature(string path)
    {
        using var file = File.OpenRead(path);
        var layout = FindLayout(file);
        var pairs = ReadPairs(layout.Block);

        // The newest scheme the APK carries; a v3.1 block only adds signers for newer Androids.
        foreach (var (id, scheme) in new[] { (BlockIdV3, 3), (BlockIdV2, 2) })
        {
            if (pairs.TryGetValue(id, out var value))
            {
                var signer = ParseSigner(value, scheme);
                var digest = ContentDigest(file, layout, signer.DigestAlgorithm);
                if (!CryptographicOperations.FixedTimeEquals(digest, signer.ExpectedDigest))
                {
                    throw BadSignature();
                }

                return signer.Info;
            }
        }

        throw Unsigned();
    }

    /// <summary>Where the signing block, the central directory and its end record are.</summary>
    public sealed record Layout(long BlockStart, byte[] Block, long CdOffset, long CdSize, long EocdOffset, byte[] Eocd);

    public static Layout FindLayout(Stream file)
    {
        var length = file.Length;
        if (length < 22)
        {
            throw new KostvApkException("No es un APK: el archivo es demasiado pequeño.");
        }

        var tailLength = (int)Math.Min(length, 22 + 65535);
        var tail = new byte[tailLength];
        file.Position = length - tailLength;
        file.ReadExactly(tail);
        var eocdAt = -1;
        for (var i = tailLength - 22; i >= 0; i--)
        {
            if (BinaryPrimitives.ReadUInt32LittleEndian(tail.AsSpan(i)) == 0x06054b50
                && BinaryPrimitives.ReadUInt16LittleEndian(tail.AsSpan(i + 20)) == tailLength - i - 22)
            {
                eocdAt = i;
                break;
            }
        }

        if (eocdAt < 0)
        {
            throw new KostvApkException("No es un APK: el archivo no es un ZIP válido.");
        }

        var eocd = tail[eocdAt..];
        var eocdOffset = length - tailLength + eocdAt;
        long cdSize = BinaryPrimitives.ReadUInt32LittleEndian(eocd.AsSpan(12));
        long cdOffset = BinaryPrimitives.ReadUInt32LittleEndian(eocd.AsSpan(16));
        if (cdOffset + cdSize != eocdOffset || cdOffset < 32)
        {
            throw Unsigned();
        }

        var footer = new byte[24];
        file.Position = cdOffset - 24;
        file.ReadExactly(footer);
        if (!footer.AsSpan(8).SequenceEqual(BlockMagic))
        {
            throw Unsigned();
        }

        var blockSize = BinaryPrimitives.ReadUInt64LittleEndian(footer);
        var blockStart = cdOffset - (long)blockSize - 8;
        if (blockSize < 24 || blockSize > 64 * 1024 * 1024 || blockStart < 0)
        {
            throw Unsigned();
        }

        var block = new byte[blockSize + 8];
        file.Position = blockStart;
        file.ReadExactly(block);
        if (BinaryPrimitives.ReadUInt64LittleEndian(block) != blockSize)
        {
            throw Unsigned();
        }

        return new Layout(blockStart, block, cdOffset, cdSize, eocdOffset, eocd);
    }

    /// <summary>The ID-value pairs of a whole signing block (with its size fields).</summary>
    public static Dictionary<uint, byte[]> ReadPairs(byte[] block)
    {
        var pairs = new Dictionary<uint, byte[]>();
        var p = 8;
        var end = block.Length - 24;
        while (p < end)
        {
            if (p + 12 > end)
            {
                throw Unsigned();
            }

            var length = BinaryPrimitives.ReadUInt64LittleEndian(block.AsSpan(p));
            if (length < 4 || length > (ulong)(end - p - 8))
            {
                throw Unsigned();
            }

            var id = BinaryPrimitives.ReadUInt32LittleEndian(block.AsSpan(p + 8));
            pairs.TryAdd(id, block.AsSpan(p + 12, (int)length - 4).ToArray());
            p += 8 + (int)length;
        }

        return pairs;
    }

    public sealed record ParsedSigner(SignerInfo Info, int DigestAlgorithm, byte[] ExpectedDigest);

    /// <summary>
    /// Reads the only signer of a v2/v3 block value, checks its signature over the signed data
    /// with its public key and that the certificate is that key's, and returns the content
    /// digest the signed data promises.
    /// </summary>
    public static ParsedSigner ParseSigner(byte[] value, int scheme)
    {
        try
        {
            var signers = new Reader(value).LengthPrefixed();
            var signerBytes = signers.LengthPrefixed();
            if (signers.Remaining > 0)
            {
                throw new KostvApkException("El APK tiene más de un firmante, y kOS TV solo usa uno.");
            }

            var signer = signerBytes;
            var signedData = signer.LengthPrefixed();
            var signedDataBytes = signedData.Copy();
            if (scheme == 3)
            {
                signer.UInt32();
                signer.UInt32();
            }

            var signatures = signer.LengthPrefixed();
            var publicKey = signer.LengthPrefixed().Rest();

            // The strongest signature we can check.
            int? algorithm = null;
            byte[]? signature = null;
            while (signatures.Remaining > 0)
            {
                var entry = signatures.LengthPrefixed();
                var id = (int)entry.UInt32();
                var bytes = entry.LengthPrefixed().Rest();
                if (Rank(id) > Rank(algorithm ?? 0))
                {
                    algorithm = id;
                    signature = bytes;
                }
            }

            if (algorithm is null || signature is null)
            {
                throw new KostvApkException("La firma del APK usa un algoritmo que el complemento no sabe comprobar.");
            }

            if (!VerifySignedData(algorithm.Value, publicKey, signedDataBytes, signature))
            {
                throw BadSignature();
            }

            var digests = signedData.LengthPrefixed();
            byte[]? expected = null;
            while (digests.Remaining > 0)
            {
                var entry = digests.LengthPrefixed();
                var id = (int)entry.UInt32();
                var digest = entry.LengthPrefixed().Rest();
                if (id == algorithm)
                {
                    expected = digest;
                }
            }

            var certificates = signedData.LengthPrefixed();
            var certBytes = certificates.LengthPrefixed().Rest();
            if (expected is null || certBytes.Length == 0)
            {
                throw BadSignature();
            }

            using var cert = LoadCertificate(certBytes);
            if (!cert.PublicKey.ExportSubjectPublicKeyInfo().AsSpan().SequenceEqual(publicKey))
            {
                throw BadSignature();
            }

            return new ParsedSigner(
                new SignerInfo(Convert.ToHexString(SHA256.HashData(certBytes)).ToLowerInvariant(), cert.Subject, scheme),
                algorithm.Value,
                expected);
        }
        catch (Exception ex) when (ex is ArgumentOutOfRangeException or IndexOutOfRangeException or CryptographicException or FormatException)
        {
            throw BadSignature();
        }
    }

    private static X509Certificate2 LoadCertificate(byte[] der)
    {
#if NET9_0_OR_GREATER
        return X509CertificateLoader.LoadCertificate(der);
#else
        return new X509Certificate2(der);
#endif
    }

    /// <summary>Higher is preferred; 0 is one we can't check.</summary>
    private static int Rank(int algorithm) => algorithm switch
    {
        0x0104 => 6, // RSASSA-PKCS1-v1_5 with SHA2-512
        0x0102 => 5, // RSASSA-PSS with SHA2-512
        0x0202 => 4, // ECDSA with SHA2-512
        0x0103 => 3, // RSASSA-PKCS1-v1_5 with SHA2-256
        0x0101 => 2, // RSASSA-PSS with SHA2-256
        0x0201 => 1, // ECDSA with SHA2-256
        _ => 0
    };

    private static bool UsesSha512(int algorithm) => algorithm is 0x0102 or 0x0104 or 0x0202;

    public static bool VerifySignedData(int algorithm, byte[] publicKey, ReadOnlySpan<byte> data, byte[] signature)
    {
        var hash = UsesSha512(algorithm) ? HashAlgorithmName.SHA512 : HashAlgorithmName.SHA256;
        switch (algorithm)
        {
            case 0x0101 or 0x0102 or 0x0103 or 0x0104:
                {
                    using var rsa = RSA.Create();
                    rsa.ImportSubjectPublicKeyInfo(publicKey, out _);
                    var padding = algorithm is 0x0101 or 0x0102 ? RSASignaturePadding.Pss : RSASignaturePadding.Pkcs1;
                    return rsa.VerifyData(data, signature, hash, padding);
                }

            case 0x0201 or 0x0202:
                {
                    using var ec = ECDsa.Create();
                    ec.ImportSubjectPublicKeyInfo(publicKey, out _);
                    return ec.VerifyData(data, signature, hash, DSASignatureFormat.Rfc3279DerSequence);
                }

            default:
                return false;
        }
    }

    /// <summary>
    /// The v2/v3 digest of the whole APK: the entries, the central directory and its end record
    /// (pointing at the signing block), in 1 MB chunks.
    /// </summary>
    public static byte[] ContentDigest(Stream file, Layout layout, int algorithm)
    {
        var sha512 = UsesSha512(algorithm);
        var eocd = (byte[])layout.Eocd.Clone();
        BinaryPrimitives.WriteUInt32LittleEndian(eocd.AsSpan(16), (uint)layout.BlockStart);

        var chunkDigests = new MemoryStream();
        var buffer = new byte[ChunkSize + 5];
        var count = 0;

        void Chunk(int length)
        {
            buffer[0] = 0xa5;
            BinaryPrimitives.WriteUInt32LittleEndian(buffer.AsSpan(1), (uint)length);
            var span = buffer.AsSpan(0, length + 5);
            chunkDigests.Write(sha512 ? SHA512.HashData(span) : SHA256.HashData(span));
            count++;
        }

        void Section(long start, long length)
        {
            file.Position = start;
            while (length > 0)
            {
                var take = (int)Math.Min(ChunkSize, length);
                file.ReadExactly(buffer, 5, take);
                Chunk(take);
                length -= take;
            }
        }

        Section(0, layout.BlockStart);
        Section(layout.CdOffset, layout.CdSize);
        for (var at = 0; at < eocd.Length; at += ChunkSize)
        {
            var take = Math.Min(ChunkSize, eocd.Length - at);
            eocd.AsSpan(at, take).CopyTo(buffer.AsSpan(5));
            Chunk(take);
        }

        var top = new byte[5 + chunkDigests.Length];
        top[0] = 0x5a;
        BinaryPrimitives.WriteUInt32LittleEndian(top.AsSpan(1), (uint)count);
        chunkDigests.ToArray().CopyTo(top, 5);
        return sha512 ? SHA512.HashData(top) : SHA256.HashData(top);
    }

    /// <summary>Little-endian, uint32-length-prefixed reader over the signing block.</summary>
    private sealed class Reader
    {
        private readonly byte[] _data;
        private readonly int _end;

        public Reader(byte[] data)
            : this(data, 0, data.Length)
        {
        }

        private Reader(byte[] data, int start, int length)
        {
            _data = data;
            Position = start;
            _end = start + length;
        }

        private int Position { get; set; }

        public int Remaining => _end - Position;

        public uint UInt32()
        {
            if (Remaining < 4)
            {
                throw new ArgumentOutOfRangeException(nameof(UInt32));
            }

            var value = BinaryPrimitives.ReadUInt32LittleEndian(_data.AsSpan(Position));
            Position += 4;
            return value;
        }

        public Reader LengthPrefixed()
        {
            var length = UInt32();
            if (length > Remaining)
            {
                throw new ArgumentOutOfRangeException(nameof(LengthPrefixed));
            }

            var inner = new Reader(_data, Position, (int)length);
            Position += (int)length;
            return inner;
        }

        public byte[] Rest()
        {
            var bytes = _data.AsSpan(Position, Remaining).ToArray();
            Position = _end;
            return bytes;
        }

        /// <summary>What is left, without moving on.</summary>
        public byte[] Copy() => _data.AsSpan(Position, Remaining).ToArray();
    }
}
