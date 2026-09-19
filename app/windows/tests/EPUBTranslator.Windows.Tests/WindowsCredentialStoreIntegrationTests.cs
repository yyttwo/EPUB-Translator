using EPUBTranslator.Core;
using EPUBTranslator.Platform.Windows;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Windows.Tests;

[TestClass]
[TestCategory("WindowsOnly")]
[TestCategory("CredentialManagerIntegration")]
public sealed class WindowsCredentialStoreIntegrationTests
{
    private const string EnableVariable = "EPUB_TRANSLATOR_RUN_CREDENTIAL_TESTS";
    private const string FakeQwenSecret = "FAKE_QWEN_SECRET";
    private const string FakeDeepSeekSecret = "FAKE_DEEPSEEK_SECRET";

    [TestMethod]
    public async Task FakeCredentialLifecycle_PersistsAcrossStoreInstances_AndRemainsIsolated()
    {
        if (!OperatingSystem.IsWindows())
        {
            Assert.Inconclusive("WINDOWS_ONLY");
        }

        if (!string.Equals(Environment.GetEnvironmentVariable(EnableVariable), "1", StringComparison.Ordinal))
        {
            Assert.Inconclusive($"Set {EnableVariable}=1 to run the isolated fake-secret integration test.");
        }

        var isolatedTargetPrefix = $"EPUBTranslator.Windows.Stage1B.Tests/{Guid.NewGuid():N}";
        var firstStore = new WindowsCredentialStore(isolatedTargetPrefix);

        try
        {
            await firstStore.SaveAsync(ProviderId.Qwen, FakeQwenSecret);
            await firstStore.SaveAsync(ProviderId.DeepSeek, FakeDeepSeekSecret);

            var restartedStore = new WindowsCredentialStore(isolatedTargetPrefix);
            Assert.AreEqual(FakeQwenSecret, await restartedStore.ReadAsync(ProviderId.Qwen));
            Assert.AreEqual(FakeDeepSeekSecret, await restartedStore.ReadAsync(ProviderId.DeepSeek));

            await restartedStore.ReplaceAsync(ProviderId.Qwen, "FAKE_QWEN_SECRET_REPLACED");
            Assert.AreEqual("FAKE_QWEN_SECRET_REPLACED", await restartedStore.ReadAsync(ProviderId.Qwen));
            Assert.AreEqual(FakeDeepSeekSecret, await restartedStore.ReadAsync(ProviderId.DeepSeek));
        }
        finally
        {
            await firstStore.DeleteAsync(ProviderId.Qwen);
            await firstStore.DeleteAsync(ProviderId.DeepSeek);
        }

        Assert.IsFalse(await firstStore.ExistsAsync(ProviderId.Qwen));
        Assert.IsFalse(await firstStore.ExistsAsync(ProviderId.DeepSeek));
    }
}
