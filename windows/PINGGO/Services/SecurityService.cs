using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Windows.Security.Credentials.UI;
using PINGGO.Models;

namespace PINGGO.Services
{
    public class SecurityService
    {
        private static readonly Lazy<SecurityService> _instance = new(() => new SecurityService());
        public static SecurityService Shared => _instance.Value;

        public event Action? OnLockStateChanged;

        public bool IsLocked { get; private set; } = false;
        private DateTime _lastActivityTime = DateTime.Now;

        public void RegisterActivity()
        {
            _lastActivityTime = DateTime.Now;
        }

        public void CheckInactivityLock()
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            if (!prefs.AppLockEnabled || IsLocked) return;

            var idle = DateTime.Now - _lastActivityTime;
            if (idle.TotalMinutes >= prefs.AutoLockMinutes)
            {
                LockApp();
            }
        }

        public void LockApp()
        {
            IsLocked = true;
            OnLockStateChanged?.Invoke();
        }

        public async Task<bool> UnlockWithWindowsHelloAsync()
        {
            try
            {
                var availability = await UserConsentVerifier.CheckAvailabilityAsync();
                if (availability == UserConsentVerifierAvailability.Available)
                {
                    var result = await UserConsentVerifier.RequestVerificationAsync("Unlock PINGGO Multi-Space App");
                    if (result == UserConsentVerificationResult.Verified)
                    {
                        IsLocked = false;
                        RegisterActivity();
                        OnLockStateChanged?.Invoke();
                        return true;
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[SecurityService] Windows Hello error: {ex.Message}");
            }
            return false;
        }

        public bool VerifyPin(string pin)
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            if (string.IsNullOrEmpty(prefs.CustomPinHash) || string.IsNullOrEmpty(prefs.CustomPinSalt))
            {
                // Fallback default PIN if not set: 1234
                if (pin == "1234")
                {
                    IsLocked = false;
                    RegisterActivity();
                    OnLockStateChanged?.Invoke();
                    return true;
                }
                return false;
            }

            var hash = HashPin(pin, prefs.CustomPinSalt);
            if (hash == prefs.CustomPinHash)
            {
                IsLocked = false;
                RegisterActivity();
                OnLockStateChanged?.Invoke();
                return true;
            }
            return false;
        }

        public void SetCustomPin(string newPin, string hint = "")
        {
            var salt = Guid.NewGuid().ToString("N");
            var hash = HashPin(newPin, salt);
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            prefs.CustomPinHash = hash;
            prefs.CustomPinSalt = salt;
            prefs.CustomPinHint = hint;
            prefs.AppLockEnabled = true;
            DataStoreService.Shared.Save();
        }

        private static string HashPin(string pin, string salt)
        {
            using var sha256 = SHA256.Create();
            var bytes = Encoding.UTF8.GetBytes(pin + salt);
            var hashBytes = sha256.ComputeHash(bytes);
            return Convert.ToBase64String(hashBytes);
        }
    }
}
