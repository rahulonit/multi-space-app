using System;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
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

        private void OnPlatformRowLoaded(object sender, RoutedEventArgs e)
        {
            if (sender is StackPanel sp && sp.Tag is string platformId)
            {
                RenderAccountChips(sp, platformId);
            }
        }

        private void RenderAccountChips(StackPanel parentRow, string platformId)
        {
            var chipsPanel = parentRow.FindName("AccountChipsPanel") as StackPanel;
            if (chipsPanel == null) return;

            chipsPanel.Children.Clear();
            var accounts = ViewModel.GetAccounts(platformId);
            if (accounts.Count <= 1)
            {
                chipsPanel.Visibility = Visibility.Collapsed;
                return;
            }

            chipsPanel.Visibility = Visibility.Visible;
            var selected = ViewModel.GetSelectedAccount(platformId);

            foreach (var acc in accounts)
            {
                bool isCurrent = acc.Id == selected?.Id;
                var chipBtn = new Button
                {
                    Background = isCurrent 
                        ? (Application.Current.Resources["AppCardBrush"] as Microsoft.UI.Xaml.Media.Brush)
                        : new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent),
                    BorderBrush = isCurrent
                        ? (Application.Current.Resources["AppAccentBrush"] as Microsoft.UI.Xaml.Media.Brush)
                        : (Application.Current.Resources["AppBorderBrush"] as Microsoft.UI.Xaml.Media.Brush),
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(10),
                    Padding = new Thickness(6, 2, 6, 2),
                    Margin = new Thickness(0, 0, 4, 0),
                    Tag = acc.Id
                };

                var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
                var dot = new Microsoft.UI.Xaml.Shapes.Ellipse
                {
                    Width = 6,
                    Height = 6,
                    Fill = isCurrent
                        ? (Application.Current.Resources["AppAccentBrush"] as Microsoft.UI.Xaml.Media.Brush)
                        : (Application.Current.Resources["AppTextMutedBrush"] as Microsoft.UI.Xaml.Media.Brush)
                };
                var tb = new TextBlock
                {
                    Text = acc.AccountName,
                    FontSize = 10,
                    FontWeight = isCurrent ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
                    Foreground = isCurrent 
                        ? new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White)
                        : (Application.Current.Resources["AppTextMutedBrush"] as Microsoft.UI.Xaml.Media.Brush)
                };
                sp.Children.Add(dot);
                sp.Children.Add(tb);
                chipBtn.Content = sp;

                chipBtn.Click += (_, _) =>
                {
                    ViewModel.SelectAccount(acc.Id);
                    RenderAccountChips(parentRow, platformId);
                };

                chipsPanel.Children.Add(chipBtn);
            }
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

        private void OnAccountMenuClicked(object sender, RoutedEventArgs e)
        {
            if (sender is not Button button || button.Tag is not string platformId) return;

            var flyout = new MenuFlyout();
            var accounts = ViewModel.GetAccounts(platformId);
            var selected = ViewModel.GetSelectedAccount(platformId);

            foreach (var account in accounts)
            {
                var accountItem = new MenuFlyoutItem
                {
                    Text = account.AccountName,
                    Icon = account.Id == selected?.Id ? new SymbolIcon(Symbol.Accept) : new SymbolIcon(Symbol.Contact)
                };
                accountItem.Click += (_, _) => ViewModel.SelectAccount(account.Id);
                flyout.Items.Add(accountItem);
            }

            if (accounts.Count > 0) flyout.Items.Add(new MenuFlyoutSeparator());

            var addItem = new MenuFlyoutItem { Text = "Add account…", Icon = new SymbolIcon(Symbol.Add) };
            addItem.Click += async (_, _) => await ShowAddAccountDialogAsync(platformId);
            flyout.Items.Add(addItem);

            var removableAccounts = accounts.Where(ViewModel.CanDeleteAccount).ToList();
            if (removableAccounts.Count > 0)
            {
                var deleteMenu = new MenuFlyoutSubItem { Text = "Delete account…", Icon = new SymbolIcon(Symbol.Delete) };
                foreach (var account in removableAccounts)
                {
                    var deleteItem = new MenuFlyoutItem { Text = account.AccountName };
                    deleteItem.Click += async (_, _) => await ConfirmDeleteAccountAsync(account);
                    deleteMenu.Items.Add(deleteItem);
                }
                flyout.Items.Add(deleteMenu);
            }

            flyout.ShowAt(button);
        }

        private async System.Threading.Tasks.Task ShowAddAccountDialogAsync(string platformId)
        {
            var accountNumber = ViewModel.GetAccounts(platformId).Count + 1;
            var nameBox = new TextBox { PlaceholderText = $"Account {accountNumber}", Text = $"Account {accountNumber}" };
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Add account",
                Content = nameBox,
                PrimaryButtonText = "Add",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                ViewModel.AddAccount(platformId, nameBox.Text);
            }
        }

        private async System.Threading.Tasks.Task ConfirmDeleteAccountAsync(PlatformAccount account)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = $"Delete {account.AccountName}?",
                Content = $"This removes {account.AccountName} from PINGGO and clears its separate website session. Your account on the social platform is not deleted.",
                PrimaryButtonText = "Delete account",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                ViewModel.RemoveAccount(account.Id);
            }
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
