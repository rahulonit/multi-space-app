using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class GlobalHeaderControl : UserControl
    {
        private MainViewModel ViewModel => MainViewModel.Shared;

        public GlobalHeaderControl()
        {
            this.InitializeComponent();
            ViewModel.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName is nameof(ViewModel.CurrentDestination) or nameof(ViewModel.TotalUnreadCount))
                {
                    UpdateTabHighlight();
                }
            };
            UpdateTabHighlight();
        }

        private void UpdateTabHighlight()
        {
            var activeBg = (SolidColorBrush)Application.Current.Resources["AppAccentBrush"];
            var inactiveBg = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            var whiteText = new SolidColorBrush(Microsoft.UI.Colors.White);
            var mutedText = (SolidColorBrush)Application.Current.Resources["AppTextMutedBrush"];

            PlatformTabBtn.Background = ViewModel.CurrentDestination == NavigationDestination.Platform ? activeBg : inactiveBg;
            PlatformTabBtn.Foreground = ViewModel.CurrentDestination == NavigationDestination.Platform ? whiteText : mutedText;

            OverviewTabBtn.Background = ViewModel.CurrentDestination == NavigationDestination.Overview ? activeBg : inactiveBg;
            OverviewTabBtn.Foreground = ViewModel.CurrentDestination == NavigationDestination.Overview ? whiteText : mutedText;

            InboxTabBtn.Background = ViewModel.CurrentDestination == NavigationDestination.Inbox ? activeBg : inactiveBg;
            InboxTabBtn.Foreground = ViewModel.CurrentDestination == NavigationDestination.Inbox ? whiteText : mutedText;

            BrowserTabBtn.Background = ViewModel.CurrentDestination == NavigationDestination.Browser ? activeBg : inactiveBg;
            BrowserTabBtn.Foreground = ViewModel.CurrentDestination == NavigationDestination.Browser ? whiteText : mutedText;

            if (ViewModel.TotalUnreadCount > 0)
            {
                InboxBadge.Visibility = Visibility.Visible;
                InboxBadgeText.Text = ViewModel.TotalUnreadCount.ToString();
            }
            else
            {
                InboxBadge.Visibility = Visibility.Collapsed;
            }
        }

        private void OnBrandClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Overview);
        private void OnPlatformTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Platform);
        private void OnOverviewTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Overview);
        private void OnInboxTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Inbox);
        private void OnBrowserTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Browser);

        private void OnSearchKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                ViewModel.Navigate(NavigationDestination.Inbox);
            }
        }

        private void OnNotificationClicked(object sender, RoutedEventArgs e) => ViewModel.ShowToast("All notifications up to date");
        private void OnProfileClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Settings);
    }
}
