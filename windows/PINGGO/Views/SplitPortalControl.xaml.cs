using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class SplitPortalControl : UserControl
    {
        private MainViewModel ViewModel => MainViewModel.Shared;

        public SplitPortalControl()
        {
            this.InitializeComponent();
            this.Loaded += (s, e) => RefreshPanes();
            ViewModel.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName is nameof(ViewModel.ActivePlatformId) or nameof(ViewModel.SplitPlatformId)
                    or nameof(ViewModel.ActiveAccountId))
                {
                    RefreshPanes();
                }
            };
        }

        private void RefreshPanes()
        {
            LeftPaneTitle.Text = $"Primary: {ViewModel.ActivePlatformId.ToUpperInvariant()}";
            RightPaneTitle.Text = $"Secondary: {ViewModel.SplitPlatformId.ToUpperInvariant()}";

            LeftPortal.LoadPlatform(ViewModel.ActivePlatformId);
            RightPortal.LoadPlatform(ViewModel.SplitPlatformId);
        }

        private void OnSwapClicked(object sender, RoutedEventArgs e)
        {
            ViewModel.SwapSplitPanes();
            RefreshPanes();
        }

        private void OnCloseSplitClicked(object sender, RoutedEventArgs e)
        {
            ViewModel.ToggleSplitView();
        }

        private void OnRatio12Clicked(object sender, RoutedEventArgs e)
        {
            SetSplitRatio(0.33);
        }

        private void OnRatio11Clicked(object sender, RoutedEventArgs e)
        {
            SetSplitRatio(0.50);
        }

        private void OnRatio21Clicked(object sender, RoutedEventArgs e)
        {
            SetSplitRatio(0.67);
        }

        private void SetSplitRatio(double ratio)
        {
            LeftColumn.Width = new GridLength(ratio, GridUnitType.Star);
            RightColumn.Width = new GridLength(1.0 - ratio, GridUnitType.Star);

            var activeBrush = Application.Current.Resources["AppSidebarBrush"] as Microsoft.UI.Xaml.Media.Brush;
            var transBrush = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
            var activeText = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White);
            var mutedText = Application.Current.Resources["AppTextMutedBrush"] as Microsoft.UI.Xaml.Media.Brush;

            RatioBtn12.Background = Math.Abs(ratio - 0.33) < 0.05 ? activeBrush : transBrush;
            if (RatioBtn12.Content is TextBlock tb12) tb12.Foreground = Math.Abs(ratio - 0.33) < 0.05 ? activeText : mutedText;

            RatioBtn11.Background = Math.Abs(ratio - 0.50) < 0.05 ? activeBrush : transBrush;
            if (RatioBtn11.Content is TextBlock tb11) tb11.Foreground = Math.Abs(ratio - 0.50) < 0.05 ? activeText : mutedText;

            RatioBtn21.Background = Math.Abs(ratio - 0.67) < 0.05 ? activeBrush : transBrush;
            if (RatioBtn21.Content is TextBlock tb21) tb21.Foreground = Math.Abs(ratio - 0.67) < 0.05 ? activeText : mutedText;
        }
    }
}
