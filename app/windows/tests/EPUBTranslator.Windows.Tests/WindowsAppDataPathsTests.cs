using EPUBTranslator.Platform.Windows;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Windows.Tests;

[TestClass]
[TestCategory("WindowsOnly")]
public sealed class WindowsAppDataPathsTests
{
    [TestMethod]
    public void Constructor_CreatesOnlyExpectedDirectories()
    {
        var root = Path.Combine(Path.GetTempPath(), $"EPUBTranslator-AppData-Test-{Guid.NewGuid():N}");
        try
        {
            var paths = new WindowsAppDataPaths(root);

            Assert.AreEqual(Path.GetFullPath(root), paths.RootDirectory);
            Assert.IsTrue(Directory.Exists(paths.StateDirectory));
            Assert.IsTrue(Directory.Exists(paths.CacheDirectory));
            Assert.IsFalse(File.Exists(Path.Combine(paths.RootDirectory, "appsettings.json")));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }
}
