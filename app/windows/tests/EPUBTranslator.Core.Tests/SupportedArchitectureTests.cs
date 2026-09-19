using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Core.Tests;

[TestClass]
public sealed class SupportedArchitectureTests
{
    [TestMethod]
    public void SupportedArchitecturesContainOnlyNativeX64AndArm64Targets()
    {
        CollectionAssert.AreEqual(
            new[] { SupportedArchitecture.X64, SupportedArchitecture.Arm64 },
            SupportedArchitectures.All.ToArray());
    }

    [TestMethod]
    public void RuntimeIdentifiersAndPlatformsAreStable()
    {
        Assert.AreEqual("win-x64", SupportedArchitecture.X64.RuntimeIdentifier());
        Assert.AreEqual("x64", SupportedArchitecture.X64.MsBuildPlatform());
        Assert.AreEqual("win-arm64", SupportedArchitecture.Arm64.RuntimeIdentifier());
        Assert.AreEqual("ARM64", SupportedArchitecture.Arm64.MsBuildPlatform());
    }
}
