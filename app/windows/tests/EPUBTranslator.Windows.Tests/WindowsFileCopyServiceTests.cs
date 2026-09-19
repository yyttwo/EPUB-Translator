using EPUBTranslator.Platform.Windows;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Windows.Tests;

[TestClass]
[TestCategory("WindowsOnly")]
public sealed class WindowsFileCopyServiceTests
{
    [TestMethod]
    public async Task CopyAsync_WritesDestinationWithoutChangingSource()
    {
        var root = Path.Combine(Path.GetTempPath(), $"EPUBTranslator-Copy-Test-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        var source = Path.Combine(root, "中文 原书.epub");
        var destination = Path.Combine(root, "中文 原书-测试副本.epub");
        var expected = new byte[] { 0x50, 0x4B, 0x03, 0x04, 0x45, 0x50, 0x55, 0x42 };

        try
        {
            await File.WriteAllBytesAsync(source, expected);
            var service = new WindowsFileCopyService();

            await service.CopyAsync(source, destination, overwrite: false);

            CollectionAssert.AreEqual(expected, await File.ReadAllBytesAsync(source));
            CollectionAssert.AreEqual(expected, await File.ReadAllBytesAsync(destination));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public async Task CopyAsync_RefusesToOverwriteSource()
    {
        var service = new WindowsFileCopyService();
        var source = Path.Combine(Path.GetTempPath(), "same-source.epub");

        await Assert.ThrowsExactlyAsync<IOException>(async () =>
            await service.CopyAsync(source, source, overwrite: true));
    }
}
