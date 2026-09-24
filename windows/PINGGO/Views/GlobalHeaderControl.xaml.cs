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

        private void OnHeaderSizeChanged(object sender, SizeChangedEventArgs e)
        {
            var compact = e.NewSize.Width < 1100;
            BrandColumn.Width = new GridLength(compact ? 56 : 230);
            BrandNameText.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
            SecurityPill.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;

            if (e.NewSize.Width < 980)
            {
                SearchBox.Visibility = Visibility.Collapsed;
            }
            else
            {
                SearchBox.Visibility = Visibility.Visible;
                SearchBox.Width = e.NewSize.Width < 1200 ? 170 : 240;
            }
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

            BrowserTabBtn.Background = ViewModel.CurrentDestination == NavigationDestination.Browser ? activeBg : inactiveBg;
            BrowserTabBtn.Foreground = ViewModel.CurrentDestination == NavigationDestination.Browser ? whiteText : mutedText;
        }

        private void OnBrandClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Overview);
        private void OnPlatformTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Platform);
        private void OnOverviewTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Overview);
        private void OnBrowserTabClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Browser);

        private void OnSearchKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                ViewModel.IsCommandPaletteOpen = true;
            }
        }

        private void OnNotificationClicked(object sender, RoutedEventArgs e) => ViewModel.ShowToast("All notifications up to date");
        private void OnProfileClicked(object sender, RoutedEventArgs e) => ViewModel.Navigate(NavigationDestination.Settings);
    }
}
