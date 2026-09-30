using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
using PINGGO.ViewModels;
using System.Collections.Specialized;

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
                UpdatePlatformState();
            };
            MainViewModel.Shared.Platforms.CollectionChanged += OnPlatformsChanged;
        }

        private void OnPlatformsChanged(object? sender, NotifyCollectionChangedEventArgs e) => UpdatePlatformState();

        private void UpdatePlatformState()
        {
            var count = MainViewModel.Shared.Platforms.Count;
            ConnectedPlatformsText.Text = count == 0 ? "No platforms yet" : $"{count} connected service{(count == 1 ? string.Empty : "s")}";
            EmptyPlatformsPanel.Visibility = count == 0 ? Visibility.Visible : Visibility.Collapsed;
            PlatformsGrid.Visibility = count == 0 ? Visibility.Collapsed : Visibility.Visible;
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
