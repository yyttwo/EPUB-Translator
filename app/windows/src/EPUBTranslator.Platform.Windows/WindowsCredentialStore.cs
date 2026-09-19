using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Security.Cryptography;
using System.Text;
using EPUBTranslator.Core;

namespace EPUBTranslator.Platform.Windows;

public sealed class WindowsCredentialStore : ICredentialStore
{
    internal const string AcceptanceModeVariable = "EPUB_TRANSLATOR_STAGE1C_ACCEPTANCE";
    internal const string AcceptanceRunIdVariable = "EPUB_TRANSLATOR_STAGE1C_RUN_ID";
    private const string ProductionTargetPrefix = "EPUBTranslator.Windows";
    private const uint CredentialTypeGeneric = 1;
    private const uint CredentialPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;
    private const int MaxCredentialBlobBytes = 2_560;
    private readonly string _credentialTargetPrefix;

    public WindowsCredentialStore()
        : this(ResolveCredentialTargetPrefix(
            Environment.GetEnvironmentVariable(AcceptanceModeVariable),
            Environment.GetEnvironmentVariable(AcceptanceRunIdVariable)))
    {
    }

    internal WindowsCredentialStore(string credentialTargetPrefix)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(credentialTargetPrefix);
        _credentialTargetPrefix = credentialTargetPrefix.TrimEnd('/');
    }

    internal static string ResolveCredentialTargetPrefix(string? acceptanceMode, string? runId)
    {
        if (!string.Equals(acceptanceMode, "1", StringComparison.Ordinal))
        {
            return ProductionTargetPrefix;
        }

        if (!Guid.TryParseExact(runId, "N", out var parsedRunId))
        {
            throw new InvalidOperationException("Stage 1C acceptance mode requires a valid isolated run ID.");
        }

        return $"EPUBTranslator.Stage1C.{parsedRunId:N}";
    }

    public ValueTask SaveAsync(
        ProviderId provider,
        string secret,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ValidateSecret(secret);
        if (ExistsCore(provider))
        {
            throw new InvalidOperationException($"{provider.DisplayName()} already has a credential.");
        }

        WriteCore(provider, secret);
        return ValueTask.CompletedTask;
    }

    public ValueTask<string?> ReadAsync(
        ProviderId provider,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(ReadCore(provider));
    }

    public ValueTask ReplaceAsync(
        ProviderId provider,
        string secret,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        ValidateSecret(secret);
        if (!ExistsCore(provider))
        {
            throw new InvalidOperationException($"{provider.DisplayName()} has no credential to replace.");
        }

        WriteCore(provider, secret);
        return ValueTask.CompletedTask;
    }

    public ValueTask<bool> DeleteAsync(
        ProviderId provider,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (CredDelete(CredentialTarget(provider), CredentialTypeGeneric, 0))
        {
            return ValueTask.FromResult(true);
        }

        var error = Marshal.GetLastWin32Error();
        if (error == ErrorNotFound)
        {
            return ValueTask.FromResult(false);
        }

        throw CreateNativeException("delete", error);
    }

    public ValueTask<bool> ExistsAsync(
        ProviderId provider,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return ValueTask.FromResult(ExistsCore(provider));
    }

    private bool ExistsCore(ProviderId provider)
    {
        if (CredRead(CredentialTarget(provider), CredentialTypeGeneric, 0, out var pointer))
        {
            CredFree(pointer);
            return true;
        }

        var error = Marshal.GetLastWin32Error();
        if (error == ErrorNotFound)
        {
            return false;
        }

        throw CreateNativeException("read", error);
    }

    private string? ReadCore(ProviderId provider)
    {
        if (!CredRead(CredentialTarget(provider), CredentialTypeGeneric, 0, out var pointer))
        {
            var error = Marshal.GetLastWin32Error();
            if (error == ErrorNotFound)
            {
                return null;
            }

            throw CreateNativeException("read", error);
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0)
            {
                return string.Empty;
            }

            if (credential.CredentialBlobSize > MaxCredentialBlobBytes ||
                credential.CredentialBlobSize % sizeof(char) != 0)
            {
                throw new InvalidDataException("Credential Manager returned an invalid credential blob.");
            }

            var byteCount = checked((int)credential.CredentialBlobSize);
            var bytes = new byte[byteCount];
            try
            {
                Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
                return Encoding.Unicode.GetString(bytes).TrimEnd('\0');
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
        finally
        {
            CredFree(pointer);
        }
    }

    private void WriteCore(ProviderId provider, string secret)
    {
        var bytes = Encoding.Unicode.GetBytes(secret);
        if (bytes.Length > MaxCredentialBlobBytes)
        {
            CryptographicOperations.ZeroMemory(bytes);
            throw new ArgumentOutOfRangeException(nameof(secret), "The credential is too large for Credential Manager.");
        }

        var blob = Marshal.AllocCoTaskMem(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new NativeCredential
            {
                Type = CredentialTypeGeneric,
                TargetName = CredentialTarget(provider),
                CredentialBlobSize = checked((uint)bytes.Length),
                CredentialBlob = blob,
                Persist = CredentialPersistLocalMachine,
                UserName = provider.DisplayName(),
            };

            if (!CredWrite(ref credential, 0))
            {
                throw CreateNativeException("write", Marshal.GetLastWin32Error());
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(bytes);
            if (blob != IntPtr.Zero)
            {
                var zeroes = new byte[bytes.Length];
                Marshal.Copy(zeroes, 0, blob, zeroes.Length);
                Marshal.FreeCoTaskMem(blob);
            }
        }
    }

    private static void ValidateSecret(string secret)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(secret);
    }

    private string CredentialTarget(ProviderId provider) =>
        $"{_credentialTargetPrefix}/{provider.DisplayName()}";

    private static CredentialStoreException CreateNativeException(string operation, int error) =>
        new(operation, error, new Win32Exception(error).Message);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        [MarshalAs(UnmanagedType.LPWStr)] public string? TargetName;
        [MarshalAs(UnmanagedType.LPWStr)] public string? Comment;
        public FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        [MarshalAs(UnmanagedType.LPWStr)] public string? TargetAlias;
        [MarshalAs(UnmanagedType.LPWStr)] public string? UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite([In] ref NativeCredential credential, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(
        string target,
        uint type,
        uint flags,
        out IntPtr credentialPointer);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll", EntryPoint = "CredFree")]
    private static extern void CredFree([In] IntPtr buffer);
}

public sealed class CredentialStoreException(string operation, int nativeErrorCode, string nativeMessage)
    : Exception($"Credential Manager {operation} failed with Windows error {nativeErrorCode}: {nativeMessage}")
{
    public string Operation { get; } = operation;

    public int NativeErrorCode { get; } = nativeErrorCode;
}
