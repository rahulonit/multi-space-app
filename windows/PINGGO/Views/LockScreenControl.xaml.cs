using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Services;

namespace PINGGO.Views
{
    public sealed partial class LockScreenControl : UserControl
    {
        public LockScreenControl()
        {
            this.InitializeComponent();
        }

        private async void OnWindowsHelloClicked(object sender, RoutedEventArgs e)
        {
            ErrorText.Visibility = Visibility.Collapsed;
            var success = await SecurityService.Shared.UnlockWithWindowsHelloAsync();
            if (!success)
            {
                ErrorText.Visibility = Visibility.Visible;
                ErrorText.Text = "Windows Hello verification cancelled or unavailable.";
            }
        }

        private void OnUnlockWithPinClicked(object sender, RoutedEventArgs e)
        {
            TryPinUnlock();
        }

        private void OnPinKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                TryPinUnlock();
            }
        }

        private void TryPinUnlock()
        {
            ErrorText.Visibility = Visibility.Collapsed;
            var pin = PinBox.Password.Trim();
            if (SecurityService.Shared.VerifyPin(pin))
            {
                PinBox.Password = string.Empty;
            }
            else
            {
                ErrorText.Visibility = Visibility.Visible;
                ErrorText.Text = "Incorrect PIN. Please try again.";
            }
        }
    }
}
