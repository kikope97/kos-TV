using Moonfin.Server.Kostv;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>kOS TV: the list of devices with the app, for the updates tab.</summary>
public class KostvInstallationsTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "kostv-installations-" + Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 11, 22, 10, 0, 0, TimeSpan.Zero);

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private KostvInstallations Store() => new(_root, () => _now, background: false);

    private string FilePath => Path.Combine(_root, KostvInstallations.FileName);

    [Fact]
    public void Record_KeepsWhoWhichDeviceAndVersion()
    {
        var store = Store();
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);

        var entry = Assert.Single(store.List());
        Assert.Equal("u1", entry.UserId);
        Assert.Equal("Mamá", entry.UserName);
        Assert.Equal("dev-1", entry.DeviceId);
        Assert.Equal("Salón", entry.DeviceName);
        Assert.Equal(KostvUpdates.KindTv, entry.Kind);
        Assert.Equal(102100000, entry.VersionCode);
        Assert.Equal(_now, entry.LastSeen);
        Assert.Equal(KostvInstallations.IdOf("dev-1", KostvUpdates.KindTv), entry.Id);

        // Written to disk and read back by a new instance (a server restart).
        Assert.True(File.Exists(FilePath));
        Assert.False(File.Exists(FilePath + ".tmp"));
        var again = Assert.Single(Store().List());
        Assert.Equal("Mamá", again.UserName);
        Assert.Equal(102100000, again.VersionCode);
    }

    [Fact]
    public void Record_IgnoresWhatCannotBeKeyed()
    {
        var store = Store();
        store.Record("u1", "Mamá", null, "Salón", KostvUpdates.KindTv, 1);
        store.Record("u1", "Mamá", "  ", "Salón", KostvUpdates.KindTv, 1);
        store.Record("u1", "Mamá", "dev-1", "Salón", "ios", 1);

        Assert.Empty(store.List());
    }

    [Fact]
    public void Record_OneEntryPerDeviceAndKind_TheLatestProfileWins()
    {
        var store = Store();
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102000000);
        _now = _now.AddHours(7);
        store.Record("u2", "Kiko", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        // The same device id as a phone is another entry (it can't really happen, but keys stay apart).
        store.Record("u2", "Kiko", "dev-1", "Salón", KostvUpdates.KindPhone, 102100000);
        store.Record("u2", "Kiko", "dev-2", "Pixel", KostvUpdates.KindPhone, 102100000);

        var list = store.List();
        Assert.Equal(3, list.Count);
        var tv = Assert.Single(list, e => e.DeviceId == "dev-1" && e.Kind == KostvUpdates.KindTv);
        Assert.Equal("u2", tv.UserId);
        Assert.Equal("Kiko", tv.UserName);
        Assert.Equal(102100000, tv.VersionCode);
        Assert.Equal(_now, tv.LastSeen);

        // An empty device name doesn't wipe the one it had.
        store.Record("u2", "Kiko", "dev-2", null, KostvUpdates.KindPhone, 102100000);
        Assert.Equal("Pixel", Store().List().Single(e => e.DeviceId == "dev-2").DeviceName);
    }

    [Fact]
    public void Record_OnlyTheDateMoving_IsWrittenNowAndThen()
    {
        var store = Store();
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        var first = File.GetLastWriteTimeUtc(FilePath);
        File.SetLastWriteTimeUtc(FilePath, first.AddDays(-1));
        var marked = File.GetLastWriteTimeUtc(FilePath);

        _now = _now.AddMinutes(5);
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        Assert.Equal(marked, File.GetLastWriteTimeUtc(FilePath));
        // In memory it is already the new date.
        Assert.Equal(_now, store.List().Single().LastSeen);

        // A new version is written at once.
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102200000);
        Assert.NotEqual(marked, File.GetLastWriteTimeUtc(FilePath));
        Assert.Equal(102200000, Store().List().Single().VersionCode);

        // And the date alone, once an hour has gone by.
        File.SetLastWriteTimeUtc(FilePath, marked);
        _now = _now.AddHours(2);
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102200000);
        Assert.Equal(_now, Store().List().Single().LastSeen);
    }

    [Fact]
    public void NotSeenFor14Days_IsForgotten_OnReadAndOnWrite()
    {
        var store = Store();
        store.Record("u1", "Mamá", "old-phone", "Móvil viejo", KostvUpdates.KindPhone, 102000000);
        _now = _now.AddDays(10);
        store.Record("u1", "Mamá", "new-phone", "Móvil nuevo", KostvUpdates.KindPhone, 102100000);

        _now = _now.AddDays(4).AddMinutes(1);
        // Read: the old phone went, and the file was written without it.
        var list = store.List();
        Assert.Equal("new-phone", Assert.Single(list).DeviceId);
        Assert.Equal("new-phone", Assert.Single(Store().List()).DeviceId);

        // Write: a record also sweeps what is old.
        _now = _now.AddDays(11);
        store.Record("u2", "Kiko", "tv", "Salón", KostvUpdates.KindTv, 102100000);
        Assert.Equal("tv", Assert.Single(Store().List()).DeviceId);
    }

    [Fact]
    public void Remove_ForgetsOneByHand()
    {
        var store = Store();
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        store.Record("u1", "Mamá", "dev-2", "Pixel", KostvUpdates.KindPhone, 102100000);

        Assert.True(store.Remove(KostvInstallations.IdOf("dev-1", KostvUpdates.KindTv)));
        Assert.False(store.Remove(KostvInstallations.IdOf("dev-1", KostvUpdates.KindTv)));
        Assert.False(store.Remove("nada"));
        Assert.Equal("dev-2", Assert.Single(Store().List()).DeviceId);

        // It comes back if it asks again.
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        Assert.Equal(2, store.List().Count);
    }

    [Fact]
    public void ABrokenFile_StartsEmptyAndRecovers()
    {
        Directory.CreateDirectory(_root);
        File.WriteAllText(FilePath, "{ esto no es json");
        var store = Store();
        Assert.Empty(store.List());
        store.Record("u1", "Mamá", "dev-1", "Salón", KostvUpdates.KindTv, 102100000);
        Assert.Single(Store().List());
    }

    [Fact]
    public void Record_IsSafeFromManyThreads()
    {
        var store = Store();
        Parallel.For(0, 200, i =>
            store.Record("u" + (i % 5), "P" + (i % 5), "dev-" + (i % 20), "Aparato", i % 2 == 0 ? KostvUpdates.KindTv : KostvUpdates.KindPhone, 102100000 + i));
        store.Flush();

        Assert.Equal(20, store.List().Count);
        Assert.Equal(20, Store().List().Count);
    }

    [Fact]
    public void Record_KeepsTheListBounded()
    {
        var store = Store();
        for (var i = 0; i < KostvInstallations.MaxEntries + 20; i++)
        {
            _now = _now.AddSeconds(1);
            store.Record("u", "P", "dev-" + i, "A", KostvUpdates.KindTv, 1);
        }

        var list = store.List();
        Assert.Equal(KostvInstallations.MaxEntries, list.Count);
        Assert.DoesNotContain(list, e => e.DeviceId == "dev-0");
        Assert.Contains(list, e => e.DeviceId == "dev-" + (KostvInstallations.MaxEntries + 19));
    }

    [Theory]
    [InlineData(102100000L, "1.21.0")]
    [InlineData(102100003L, "1.21.0 (prueba 3)")]
    [InlineData(200000000L, "2.0.0")]
    [InlineData(101012500L, "1.10.125")]
    [InlineData(1000000L, "1.0.0")]
    [InlineData(0L, "desconocida")]
    [InlineData(-5L, "desconocida")]
    public void VersionName_IsDecodedFromTheCode(long code, string expected) =>
        Assert.Equal(expected, KostvInstallations.VersionName(code));

    [Fact]
    public void IsUpToDate_ComparesWithTheNewestOnOffer()
    {
        Assert.True(KostvInstallations.IsUpToDate(102100000, 102100000));
        // A test build on top of the newest counts as up to date.
        Assert.True(KostvInstallations.IsUpToDate(102100002, 102100000));
        Assert.False(KostvInstallations.IsUpToDate(102000000, 102100000));
        // The old scheme's 1.0.0 is behind everything new.
        Assert.False(KostvInstallations.IsUpToDate(1000000, 102100000));
        // Nothing on offer: nothing to update to.
        Assert.True(KostvInstallations.IsUpToDate(102000000, null));
    }
}
