using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Core.Tests;

[TestClass]
public sealed class ProductContractTests
{
    [TestMethod]
    public void TranslationStyles_HaveExactlyFourStableIdsAndFluentDefault()
    {
        Assert.AreEqual(4, TranslationStyles.All.Count);
        CollectionAssert.AreEqual(
            new[] { "literal", "fluent", "concise_interpretive", "formal_commentary" },
            TranslationStyles.All.Select(style => style.StableId).ToArray());
        Assert.AreEqual("fluent", TranslationStyles.Default.StableId);
    }

    [TestMethod]
    public void ProviderCredentialTargets_AreStableAndIsolated()
    {
        Assert.AreEqual("EPUBTranslator.Windows/Qwen", ProviderId.Qwen.CredentialTarget());
        Assert.AreEqual("EPUBTranslator.Windows/DeepSeek", ProviderId.DeepSeek.CredentialTarget());
        Assert.AreNotEqual(ProviderId.Qwen.CredentialTarget(), ProviderId.DeepSeek.CredentialTarget());
    }

    [TestMethod]
    public void ProviderProfiles_UseApprovedHttpsEndpointsAndFrozenModels()
    {
        Assert.AreEqual("qwen3.7-plus", ProviderProfiles.Qwen.Model);
        Assert.AreEqual("dashscope.aliyuncs.com", ProviderProfiles.Qwen.Endpoint.Host);
        Assert.AreEqual(Uri.UriSchemeHttps, ProviderProfiles.Qwen.Endpoint.Scheme);

        Assert.AreEqual("deepseek-v4-flash", ProviderProfiles.DeepSeek.Model);
        Assert.AreEqual("api.deepseek.com", ProviderProfiles.DeepSeek.Endpoint.Host);
        Assert.AreEqual(Uri.UriSchemeHttps, ProviderProfiles.DeepSeek.Endpoint.Scheme);

        Assert.AreEqual(TimeSpan.FromSeconds(15), ProviderProfiles.Qwen.ValidationTimeout);
        Assert.AreEqual(TimeSpan.FromSeconds(45), ProviderProfiles.DeepSeek.TranslationTimeout);
    }

    [TestMethod]
    public void SupportUrl_IsTheApprovedHttpsIssueEndpoint()
    {
        Assert.AreEqual(Uri.UriSchemeHttps, SupportLinks.Feedback.Scheme);
        Assert.AreEqual("github.com", SupportLinks.Feedback.Host);
        Assert.AreEqual(
            "/yyttwo/EPUB-Translator/issues/new",
            SupportLinks.Feedback.AbsolutePath);
        Assert.AreEqual(string.Empty, SupportLinks.Feedback.Query);
    }

    [TestMethod]
    public void ErrorMappings_HaveStableUserFacingFields()
    {
        var errors = new[]
        {
            UserFacingErrors.FileReadFailed(),
            UserFacingErrors.FileSaveFailed(),
            UserFacingErrors.CredentialFailed(),
            UserFacingErrors.ProviderNotConfigured(),
        };

        Assert.IsTrue(errors.All(error => !string.IsNullOrWhiteSpace(error.Title)));
        Assert.IsTrue(errors.All(error => !string.IsNullOrWhiteSpace(error.Message)));
        Assert.IsTrue(errors.All(error => !string.IsNullOrWhiteSpace(error.RecoveryHint)));
        Assert.IsTrue(errors.All(error => error.TechnicalCode.StartsWith("WIN_", StringComparison.Ordinal)));
    }
}
