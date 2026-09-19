using EPUBTranslator.Platform.Windows;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Windows.Tests;

[TestClass]
public sealed class WindowsCredentialTargetPolicyTests
{
    [TestMethod]
    public void NormalLaunchUsesProductionTargetPrefix()
    {
        Assert.AreEqual(
            "EPUBTranslator.Windows",
            WindowsCredentialStore.ResolveCredentialTargetPrefix(null, null));
    }

    [TestMethod]
    public void AcceptanceLaunchUsesIsolatedRandomTargetPrefix()
    {
        const string runId = "00112233445566778899aabbccddeeff";

        Assert.AreEqual(
            $"EPUBTranslator.Stage1C.{runId}",
            WindowsCredentialStore.ResolveCredentialTargetPrefix("1", runId));
    }

    [TestMethod]
    public void AcceptanceLaunchRejectsMissingRunId()
    {
        Assert.ThrowsExactly<InvalidOperationException>(() =>
            WindowsCredentialStore.ResolveCredentialTargetPrefix("1", null));
    }

    [TestMethod]
    public void AcceptanceLaunchRejectsMalformedRunId()
    {
        Assert.ThrowsExactly<InvalidOperationException>(() =>
            WindowsCredentialStore.ResolveCredentialTargetPrefix("1", "not-a-guid"));
    }
}
