using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class SidebarControl : UserControl
    {
        public MainViewModel ViewModel => MainViewModel.Shared;

        public SidebarControl()
        {
            this.InitializeComponent();
        }

        private void OnPlatformItemClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string platformId)
            {
                ViewModel.SelectPlatform(platformId);
            }
        }

        private void OnAddPlatformClicked(object sender, RoutedEventArgs e)
        {
            ViewModel.ShowToast("Click any platform in Settings to configure custom URLs");
        }

        private void OnSettingsClicked(object sender, RoutedEventArgs e)
        {
            ViewModel.Navigate(NavigationDestination.Settings);
        }

        private void OnLockClicked(object sender, RoutedEventArgs e)
        {
            SecurityService.Shared.LockApp();
        }
    }
}
