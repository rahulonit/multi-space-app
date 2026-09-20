using System;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using PINGGO.Services;
using PINGGO.ViewModels;
using Windows.System;
using WinRT.Interop;

namespace PINGGO
{
    public sealed partial class MainWindow : Window
    {
        private MainViewModel ViewModel => MainViewModel.Shared;
        private AppWindow? _appWindow;

        public MainWindow()
        {
            this.InitializeComponent();
            SetupAppWindow();

            ViewModel.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName is nameof(ViewModel.CurrentDestination) or nameof(ViewModel.IsSplitView)
                    or nameof(ViewModel.ActivePlatformId) or nameof(ViewModel.ActiveAccountId))
                {
                    UpdateContentVisibility();
                }
                else if (e.PropertyName == nameof(ViewModel.IsCommandPaletteOpen))
                {
                    CommandPaletteOverlay.Visibility = ViewModel.IsCommandPaletteOpen ? Visibility.Visible : Visibility.Collapsed;
                }
                else if (e.PropertyName == nameof(ViewModel.IsAppLocked))
                {
                    LockScreenOverlay.Visibility = ViewModel.IsAppLocked ? Visibility.Visible : Visibility.Collapsed;
                }
                else if (e.PropertyName == nameof(ViewModel.ToastMessage))
                {
                    UpdateToast();
                }
            };

            // Global Key Down for Shortcuts
            if (this.Content is UIElement rootElement)
            {
                rootElement.KeyDown += OnWindowKeyDown;
                rootElement.PointerMoved += (s, e) => SecurityService.Shared.RegisterActivity();
            }

            UpdateContentVisibility();
        }

        private void SetupAppWindow()
        {
            var hWnd = WindowNative.GetWindowHandle(this);
            var windowId = Win32Interop.GetWindowIdFromWindow(hWnd);
            _appWindow = AppWindow.GetFromWindowId(windowId);

            if (_appWindow != null)
            {
                _appWindow.Title = "PINGGO - Multi-Space App";
                _appWindow.Resize(new Windows.Graphics.SizeInt32(1280, 840));

                // Customize titlebar colors
                if (AppWindowTitleBar.IsCustomizationSupported())
                {
                    var titleBar = _appWindow.TitleBar;
                    titleBar.BackgroundColor = ColorHelper.FromArgb(255, 19, 21, 27);
                    titleBar.ButtonBackgroundColor = ColorHelper.FromArgb(255, 19, 21, 27);
                    titleBar.ButtonForegroundColor = Colors.White;
                    titleBar.ButtonHoverBackgroundColor = ColorHelper.FromArgb(255, 34, 38, 52);
                }
            }
        }

        private void UpdateContentVisibility()
        {
            HomeViewHost.Visibility = Visibility.Collapsed;
            PortalViewHost.Visibility = Visibility.Collapsed;
            SplitPortalHost.Visibility = Visibility.Collapsed;
            InboxViewHost.Visibility = Visibility.Collapsed;
            BrowserViewHost.Visibility = Visibility.Collapsed;
            SettingsViewHost.Visibility = Visibility.Collapsed;

            switch (ViewModel.CurrentDestination)
            {
                case NavigationDestination.Overview:
                    HomeViewHost.Visibility = Visibility.Visible;
                    break;
                case NavigationDestination.Platform:
                    if (ViewModel.IsSplitView)
                    {
                        SplitPortalHost.Visibility = Visibility.Visible;
                    }
                    else
                    {
                        PortalViewHost.Visibility = Visibility.Visible;
                        PortalViewHost.LoadPlatform(ViewModel.ActivePlatformId);
                    }
                    break;
                case NavigationDestination.Inbox:
                    InboxViewHost.Visibility = Visibility.Visible;
                    break;
                case NavigationDestination.Browser:
                    BrowserViewHost.Visibility = Visibility.Visible;
                    break;
                case NavigationDestination.Settings:
                    SettingsViewHost.Visibility = Visibility.Visible;
                    break;
            }
        }

        private void UpdateToast()
        {
            if (!string.IsNullOrEmpty(ViewModel.ToastMessage))
            {
                ToastText.Text = ViewModel.ToastMessage;
                ToastContainer.Visibility = Visibility.Visible;
            }
            else
            {
                ToastContainer.Visibility = Visibility.Collapsed;
            }
        }

        private void OnWindowKeyDown(object sender, KeyRoutedEventArgs e)
        {
            SecurityService.Shared.RegisterActivity();

            var isCtrl = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control)
                .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

            if (isCtrl)
            {
                switch (e.Key)
                {
                    case VirtualKey.K:
                        ViewModel.ToggleCommandPalette();
                        e.Handled = true;
                        break;
                    case VirtualKey.T:
                        ViewModel.Navigate(NavigationDestination.Browser);
                        BrowserViewModel.Shared.AddNewTab();
                        e.Handled = true;
                        break;
                    case VirtualKey.L:
                        SecurityService.Shared.LockApp();
                        e.Handled = true;
                        break;
                    case (VirtualKey)220: // Backslash for Split View (Ctrl+\)
                        ViewModel.ToggleSplitView();
                        e.Handled = true;
                        break;
                }
            }
        }
    }
}
