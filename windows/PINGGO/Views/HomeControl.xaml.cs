using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class HomeControl : UserControl
    {
        public HomeControl()
        {
            this.InitializeComponent();
            this.Loaded += (s, e) =>
            {
                PlatformsGrid.ItemsSource = MainViewModel.Shared.Platforms;
            };
        }

        private void OnPlatformCardClicked(object sender, ItemClickEventArgs e)
        {
            if (e.ClickedItem is SocialPlatform platform)
            {
                MainViewModel.Shared.SelectPlatform(platform.Id);
            }
        }
    }
}
