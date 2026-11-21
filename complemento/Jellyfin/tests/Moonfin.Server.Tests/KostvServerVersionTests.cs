using System.Runtime.CompilerServices;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Library;
using MediaBrowser.Model.Tasks;
using Moonfin.Server.Helpers;
using Moonfin.Server.Kostv;
using Moonfin.Server.Services;
using Xunit;

namespace Moonfin.Server.Tests;

/// <summary>
/// Kos TV: what is bound by name so one build works on Jellyfin 10.10, 10.11 and 12 (the members
/// it binds to changed in 10.11). These run against the 10.10 packages, so they check the 10.10
/// half; the other versions are checked by tools/abi-check against their real assemblies.
/// </summary>
public sealed class KostvServerVersionTests
{
    [Fact]
    public void TheItemListIsTheServersOwnGetItemList()
    {
        var item = new MusicArtist { Id = Guid.NewGuid(), Name = "Rosalía" };
        InternalItemsQuery? asked = null;
        var library = RecordingHostProxy.Create<ILibraryManager>((method, args) =>
        {
            asked = (InternalItemsQuery)args![0]!;
            return method.Name == "GetItemList" ? new List<BaseItem> { item } : throw new NotSupportedException(method.Name);
        });
        var query = new InternalItemsQuery { Limit = 1 };

        Assert.Equal(new BaseItem[] { item }, LibraryQueries.ItemList(library, query));
        Assert.Same(query, asked);
    }

    [Fact]
    public void TheItemIdsAreTheServersOwnGetItemIds()
    {
        var ids = new List<Guid> { Guid.NewGuid(), Guid.NewGuid() };
        var library = RecordingHostProxy.Create<ILibraryManager>((method, _) =>
            method.Name == "GetItemIds" ? ids : throw new NotSupportedException(method.Name));

        Assert.Equal(ids, LibraryQueries.ItemIds(library, new InternalItemsQuery()));
    }

    [Fact]
    public void AFailedReadGivesTheServersOwnError()
    {
        var library = RecordingHostProxy.Create<ILibraryManager>((_, _) => throw new InvalidOperationException("the database is busy"));

        var error = Assert.Throws<InvalidOperationException>(() => LibraryQueries.ItemList(library, new InternalItemsQuery()));
        Assert.Equal("the database is busy", error.Message);
        Assert.Throws<InvalidOperationException>(() => LibraryQueries.ItemIds(library, new InternalItemsQuery()));
    }

    [Fact]
    public void TheSimilarArtistsQueryIsFoundOn1010()
    {
        // Only 10.10 has it; there it is still asked as before.
        Assert.NotNull(LibraryQueries.SimilarToProperty);
    }

    [Fact]
    public void APlaylistEntryIsMovedByItsOwnIdWhereTheServerHasOne()
    {
        var item = Guid.NewGuid();
        var child = new LinkedChild { ItemId = item, Id = "entry1" };

        Assert.Equal("entry1", KostvMusicAway.EntryIdOf(child, item));
    }

    [Fact]
    public void APlaylistEntryWithoutAnIdOfItsOwnIsMovedByItsItem()
    {
        // As 10.11 and 12 move them: their entries have no id of their own.
        var item = Guid.NewGuid();
        var child = new LinkedChild { ItemId = item, Id = string.Empty };

        Assert.Equal(item.ToString("N"), KostvMusicAway.EntryIdOf(child, item));
    }

    [Fact]
    public void TheCustomRowsTaskRunsAtStartupAndDailyAtFour()
    {
        var task = (CustomRowsSyncTask)RuntimeHelpers.GetUninitializedObject(typeof(CustomRowsSyncTask));

        var triggers = task.GetDefaultTriggers().ToList();

        Assert.Equal([TaskTriggerInfo.TriggerStartup, TaskTriggerInfo.TriggerDaily], triggers.Select(t => t.Type));
        Assert.Null(triggers[0].TimeOfDayTicks);
        Assert.Equal(TimeSpan.FromHours(4).Ticks, triggers[1].TimeOfDayTicks);
    }
}
