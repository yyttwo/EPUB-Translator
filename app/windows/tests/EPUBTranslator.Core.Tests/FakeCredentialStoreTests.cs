using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Core.Tests;

[TestClass]
public sealed class FakeCredentialStoreTests
{
    private const string FakeQwenSecret = "FAKE_QWEN_SECRET";
    private const string FakeDeepSeekSecret = "FAKE_DEEPSEEK_SECRET";

    [TestMethod]
    public async Task CredentialLifecycle_CreateReadReplaceDelete_Works()
    {
        var store = new FakeCredentialStore();

        await store.SaveAsync(ProviderId.Qwen, FakeQwenSecret);
        Assert.IsTrue(await store.ExistsAsync(ProviderId.Qwen));
        Assert.AreEqual(FakeQwenSecret, await store.ReadAsync(ProviderId.Qwen));

        await store.ReplaceAsync(ProviderId.Qwen, "FAKE_QWEN_SECRET_REPLACED");
        Assert.AreEqual("FAKE_QWEN_SECRET_REPLACED", await store.ReadAsync(ProviderId.Qwen));

        Assert.IsTrue(await store.DeleteAsync(ProviderId.Qwen));
        Assert.IsFalse(await store.ExistsAsync(ProviderId.Qwen));
        Assert.IsNull(await store.ReadAsync(ProviderId.Qwen));
    }

    [TestMethod]
    public async Task Credentials_AreIsolatedByProvider()
    {
        var store = new FakeCredentialStore();
        await store.SaveAsync(ProviderId.Qwen, FakeQwenSecret);
        await store.SaveAsync(ProviderId.DeepSeek, FakeDeepSeekSecret);

        Assert.AreEqual(FakeQwenSecret, await store.ReadAsync(ProviderId.Qwen));
        Assert.AreEqual(FakeDeepSeekSecret, await store.ReadAsync(ProviderId.DeepSeek));
        Assert.AreNotEqual(
            await store.ReadAsync(ProviderId.Qwen),
            await store.ReadAsync(ProviderId.DeepSeek));
    }

    [TestMethod]
    public async Task Save_RefusesToOverwriteExistingCredential()
    {
        var store = new FakeCredentialStore();
        await store.SaveAsync(ProviderId.Qwen, FakeQwenSecret);

        await Assert.ThrowsExactlyAsync<InvalidOperationException>(async () =>
            await store.SaveAsync(ProviderId.Qwen, "FAKE_UNAPPROVED_OVERWRITE"));
        Assert.AreEqual(FakeQwenSecret, await store.ReadAsync(ProviderId.Qwen));
    }

    private sealed class FakeCredentialStore : ICredentialStore
    {
        private readonly Dictionary<ProviderId, string> _credentials = [];

        public ValueTask SaveAsync(
            ProviderId provider,
            string secret,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ArgumentException.ThrowIfNullOrWhiteSpace(secret);
            if (!_credentials.TryAdd(provider, secret))
            {
                throw new InvalidOperationException("A credential already exists.");
            }

            return ValueTask.CompletedTask;
        }

        public ValueTask<string?> ReadAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(_credentials.GetValueOrDefault(provider));
        }

        public ValueTask ReplaceAsync(
            ProviderId provider,
            string secret,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ArgumentException.ThrowIfNullOrWhiteSpace(secret);
            if (!_credentials.ContainsKey(provider))
            {
                throw new InvalidOperationException("No credential exists.");
            }

            _credentials[provider] = secret;
            return ValueTask.CompletedTask;
        }

        public ValueTask<bool> DeleteAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(_credentials.Remove(provider));
        }

        public ValueTask<bool> ExistsAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return ValueTask.FromResult(_credentials.ContainsKey(provider));
        }
    }
}
