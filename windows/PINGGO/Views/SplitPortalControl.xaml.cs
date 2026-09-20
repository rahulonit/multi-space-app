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
    }
}
