using System;
using System.Linq;
using Windows.Security.Credentials;

namespace PINGGO.Services
{
    public static class AICredentialStore
    {
        private const string Resource = "PINGGO AI Providers";

        public static string Load(string provider)
        {
            try
            {
                var credential = new PasswordVault()
                    .FindAllByResource(Resource)
                    .FirstOrDefault(item => string.Equals(item.UserName, provider, StringComparison.OrdinalIgnoreCase));
                if (credential == null) return string.Empty;
                credential.RetrievePassword();
                return credential.Password ?? string.Empty;
            }
            catch
            {
                return string.Empty;
            }
        }

        public static void Save(string provider, string secret)
        {
            Delete(provider);
            if (!string.IsNullOrWhiteSpace(secret))
            {
                new PasswordVault().Add(new PasswordCredential(Resource, provider, secret.Trim()));
            }
        }

        public static void Delete(string provider)
        {
            try
            {
                var vault = new PasswordVault();
                foreach (var item in vault.FindAllByResource(Resource)
                    .Where(item => string.Equals(item.UserName, provider, StringComparison.OrdinalIgnoreCase)))
                {
                    vault.Remove(item);
                }
            }
            catch
            {
                // FindAllByResource throws when no credentials exist.
            }
        }
    }
}
