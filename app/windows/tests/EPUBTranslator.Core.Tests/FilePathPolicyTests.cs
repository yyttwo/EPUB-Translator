using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Core.Tests;

[TestClass]
public sealed class FilePathPolicyTests
{
    [TestMethod]
    [DataRow("book.epub")]
    [DataRow("BOOK.EPUB")]
    [DataRow("书名（测试）.epub")]
    public void IsEpub_AcceptsExpectedExtensions(string fileName)
    {
        Assert.IsTrue(FilePathPolicy.IsEpub(fileName));
    }

    [TestMethod]
    [DataRow("book.pdf")]
    [DataRow("book.epub.zip")]
    [DataRow("book")]
    public void IsEpub_RejectsOtherExtensions(string fileName)
    {
        Assert.IsFalse(FilePathPolicy.IsEpub(fileName));
    }

    [TestMethod]
    public void SuggestedSmokeCopyName_PreservesUnicodeAndSeparatesOutput()
    {
        var source = Path.Combine(Path.GetTempPath(), "中文 用户", "书名（测试）.epub");

        Assert.AreEqual("书名（测试）-测试副本.epub", FilePathPolicy.SuggestedSmokeCopyName(source));
    }

    [TestMethod]
    public void ReferToSameWindowsPath_IsCaseInsensitive()
    {
        var root = Path.Combine(Path.GetTempPath(), "EPUBTranslator-Path-Test");
        var lower = Path.Combine(root, "book.epub");
        var upper = Path.Combine(root, "BOOK.EPUB");

        Assert.IsTrue(FilePathPolicy.ReferToSameWindowsPath(lower, upper));
    }

    [TestMethod]
    public void EnsureDistinct_RejectsSourceOverwrite()
    {
        var source = Path.Combine(Path.GetTempPath(), "EPUBTranslator-Path-Test", "book.epub");

        Assert.ThrowsExactly<IOException>(() => FilePathPolicy.EnsureDistinct(source, source));
    }

    [TestMethod]
    public void LongUnicodeName_RemainsValidEpubName()
    {
        var name = $"中文 空格（{new string('长', 120)}）.epub";

        Assert.IsTrue(FilePathPolicy.IsEpub(name));
        StringAssert.EndsWith(FilePathPolicy.SuggestedSmokeCopyName(name), "-测试副本.epub");
    }
}
