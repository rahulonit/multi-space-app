using System;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using PINGGO.Services;
using PINGGO.ViewModels;
using Windows.Foundation;
using Windows.Storage;
using Windows.System;
using Windows.UI.Core;

namespace PINGGO.Views
{
    public sealed partial class SplitPortalControl : UserControl
    {
        private const string LayoutSetting = "SplitLayout";
        private const string RatioSetting = "SplitRatio";
        private readonly ApplicationDataContainer? _settings;
        private MainViewModel ViewModel => MainViewModel.Shared;
        private bool _isStacked;
        private bool _primaryActive = true;
        private bool _soloMode;
        private bool _dragging;
        private uint _pointerId;
        private double _ratio = 0.5;

        public SplitPortalControl()
        {
            InitializeComponent();
            try { _settings = ApplicationData.Current.LocalSettings; }
            catch { _settings = null; }
            Loaded += OnLoaded;
            ViewModel.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName is nameof(ViewModel.ActivePlatformId) or nameof(ViewModel.SplitPlatformId)
                    or nameof(ViewModel.ActiveAccountId)) RefreshPanes();
            };
        }

        private void OnLoaded(object sender, RoutedEventArgs e)
        {
            _isStacked = (_settings?.Values[LayoutSetting] as string) == "rows";
            if (_settings?.Values[RatioSetting] is double savedRatio)
                _ratio = Math.Clamp(savedRatio, 0.2, 0.8);
            ApplyLayout();
            RefreshPanes();
            Focus(FocusState.Programmatic);
        }

        private void RefreshPanes()
        {
            LeftPaneTitle.Text = $"Primary · {ViewModel.ActivePlatformId.ToUpperInvariant()}";
            RightPaneTitle.Text = $"Secondary · {ViewModel.SplitPlatformId.ToUpperInvariant()}";
            LeftPortal.LoadPlatform(ViewModel.ActivePlatformId);
            RightPortal.LoadPlatform(ViewModel.SplitPlatformId);
        }

        private void ApplyLayout()
        {
            LayoutIcon.Glyph = _isStacked ? "\uE6E4" : "\uE6E5";
            DividerIcon.Glyph = _isStacked ? "\uE76F" : "\uE784";
            if (_soloMode)
            {
                LeftPaneBorder.Visibility = _primaryActive ? Visibility.Visible : Visibility.Collapsed;
                RightPaneBorder.Visibility = _primaryActive ? Visibility.Collapsed : Visibility.Visible;
                Divider.Visibility = Visibility.Collapsed;
                PlacePane(LeftPaneBorder, 0, 0);
                PlacePane(RightPaneBorder, 0, 0);
                PrimaryColumn.Width = new GridLength(1, GridUnitType.Star);
                DividerColumn.Width = new GridLength(0);
                SecondaryColumn.Width = new GridLength(0);
                PrimaryRow.Height = new GridLength(1, GridUnitType.Star);
                DividerRow.Height = new GridLength(0);
                SecondaryRow.Height = new GridLength(0);
            }
            else if (_isStacked)
            {
                ShowBothPanes();
                PlacePane(LeftPaneBorder, 0, 0);
                PlacePane(Divider, 0, 1);
                PlacePane(RightPaneBorder, 0, 2);
                PrimaryColumn.Width = new GridLength(1, GridUnitType.Star);
                DividerColumn.Width = new GridLength(0);
                SecondaryColumn.Width = new GridLength(0);
                PrimaryRow.Height = new GridLength(_ratio, GridUnitType.Star);
                DividerRow.Height = new GridLength(6);
                SecondaryRow.Height = new GridLength(1 - _ratio, GridUnitType.Star);
                Divider.BorderThickness = new Thickness(0, 1, 0, 1);
            }
            else
            {
                ShowBothPanes();
                PlacePane(LeftPaneBorder, 0, 0);
                PlacePane(Divider, 1, 0);
                PlacePane(RightPaneBorder, 2, 0);
                PrimaryColumn.Width = new GridLength(_ratio, GridUnitType.Star);
                DividerColumn.Width = new GridLength(6);
                SecondaryColumn.Width = new GridLength(1 - _ratio, GridUnitType.Star);
                PrimaryRow.Height = new GridLength(1, GridUnitType.Star);
                DividerRow.Height = new GridLength(0);
                SecondaryRow.Height = new GridLength(0);
                Divider.BorderThickness = new Thickness(1, 0, 1, 0);
            }
            UpdateActivePane();
            UpdateRatioButtons();
        }

        private void ShowBothPanes()
        {
            LeftPaneBorder.Visibility = Visibility.Visible;
            RightPaneBorder.Visibility = Visibility.Visible;
            Divider.Visibility = Visibility.Visible;
        }

        private static void PlacePane(FrameworkElement element, int column, int row)
        {
            Grid.SetColumn(element, column);
            Grid.SetRow(element, row);
        }

        private void UpdateActivePane()
        {
            LeftPaneBorder.BorderThickness = _primaryActive ? new Thickness(1) : new Thickness(0);
            RightPaneBorder.BorderThickness = _primaryActive ? new Thickness(0) : new Thickness(1);
            LeftActiveDot.Opacity = _primaryActive ? 1 : 0;
            RightActiveDot.Opacity = _primaryActive ? 0 : 1;
            SoloIcon.Glyph = _soloMode ? "\uE73F" : "\uE740";
        }

        private void OnLeftPaneTapped(object sender, TappedRoutedEventArgs e) => SetActivePane(true);
        private void OnRightPaneTapped(object sender, TappedRoutedEventArgs e) => SetActivePane(false);
        private void OnLeftPaneDoubleTapped(object sender, DoubleTappedRoutedEventArgs e) { SetActivePane(true); ToggleSolo(); }
        private void OnRightPaneDoubleTapped(object sender, DoubleTappedRoutedEventArgs e) { SetActivePane(false); ToggleSolo(); }
        private void SetActivePane(bool primary) { _primaryActive = primary; UpdateActivePane(); }

        private void OnLayoutClicked(object sender, RoutedEventArgs e)
        {
            _isStacked = !_isStacked;
            if (_settings != null) _settings.Values[LayoutSetting] = _isStacked ? "rows" : "columns";
            ApplyLayout();
        }

        private void OnSwapClicked(object sender, RoutedEventArgs e) { ViewModel.SwapSplitPanes(); RefreshPanes(); }
        private void OnCloseSplitClicked(object sender, RoutedEventArgs e) => ViewModel.ToggleSplitView();
        private void OnSoloClicked(object sender, RoutedEventArgs e) => ToggleSolo();
        private void ToggleSolo() { _soloMode = !_soloMode; ApplyLayout(); }
        private void OnRatio12Clicked(object sender, RoutedEventArgs e) => SetSplitRatio(0.33);
        private void OnRatio11Clicked(object sender, RoutedEventArgs e) => SetSplitRatio(0.50);
        private void OnRatio21Clicked(object sender, RoutedEventArgs e) => SetSplitRatio(0.67);

        private void SetSplitRatio(double ratio)
        {
            _ratio = Math.Clamp(ratio, 0.2, 0.8);
            if (_settings != null) _settings.Values[RatioSetting] = _ratio;
            if (_soloMode) _soloMode = false;
            ApplyLayout();
        }

        private void UpdateRatioButtons()
        {
            var active = Application.Current.Resources["AppAccentBrush"] as Brush;
            var clear = new SolidColorBrush(Colors.Transparent);
            RatioBtn12.Background = Math.Abs(_ratio - 0.33) < 0.05 ? active : clear;
            RatioBtn11.Background = Math.Abs(_ratio - 0.50) < 0.05 ? active : clear;
            RatioBtn21.Background = Math.Abs(_ratio - 0.67) < 0.05 ? active : clear;
        }

        private void OnDividerPointerEntered(object sender, PointerRoutedEventArgs e) =>
            ProtectedCursor = InputSystemCursor.Create(_isStacked ? InputSystemCursorShape.SizeNorthSouth : InputSystemCursorShape.SizeWestEast);
        private void OnDividerPointerExited(object sender, PointerRoutedEventArgs e)
        {
            if (!_dragging) ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.Arrow);
        }
        private void OnDividerPointerPressed(object sender, PointerRoutedEventArgs e)
        {
            _dragging = true;
            _pointerId = e.Pointer.PointerId;
            Divider.CapturePointer(e.Pointer);
            e.Handled = true;
        }
        private void OnDividerPointerMoved(object sender, PointerRoutedEventArgs e)
        {
            if (!_dragging || e.Pointer.PointerId != _pointerId) return;
            Point point = e.GetCurrentPoint(PaneGrid).Position;
            var total = _isStacked ? PaneGrid.ActualHeight : PaneGrid.ActualWidth;
            if (total > 0) SetSplitRatio((_isStacked ? point.Y : point.X) / total);
        }
        private void OnDividerPointerReleased(object sender, PointerRoutedEventArgs e)
        {
            if (e.Pointer.PointerId != _pointerId) return;
            _dragging = false;
            Divider.ReleasePointerCapture(e.Pointer);
            ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.Arrow);
            e.Handled = true;
        }
        private void OnDividerDoubleTapped(object sender, DoubleTappedRoutedEventArgs e) => SetSplitRatio(0.5);

        private async void OnAiBridgeClicked(object sender, RoutedEventArgs e)
        {
            var primary = ViewModel.GetSelectedAccount(ViewModel.ActivePlatformId);
            var secondary = ViewModel.GetSelectedAccount(ViewModel.SplitPlatformId);
            var primaryContext = primary == null ? null : ViewModel.GetActiveThreadContext(primary.Id);
            var secondaryContext = secondary == null ? null : ViewModel.GetActiveThreadContext(secondary.Id);
            if (primaryContext == null && secondaryContext == null)
            {
                await ShowBridgeDialog("AI Bridge needs an active conversation in at least one pane. Open a chat, then try again.", false);
                return;
            }
            var context = $"PRIMARY PANE ({ViewModel.ActivePlatformId}):\n{primaryContext?.ContextSnippet ?? "No active conversation."}\n\n" +
                          $"SECONDARY PANE ({ViewModel.SplitPlatformId}):\n{secondaryContext?.ContextSnippet ?? "No active conversation."}";
            try
            {
                var result = await AIService.Shared.AskCoPilotAsync("Compare these conversations. Summarize the shared topic, conflicts or dependencies, and the three most important next actions. Identify which pane each fact comes from.", context);
                await ShowBridgeDialog(result, true);
            }
            catch (Exception ex)
            {
                await ShowBridgeDialog($"AI Bridge could not complete the comparison. {ex.Message}", false);
            }
        }

        private async Task ShowBridgeDialog(string text, bool canCopy)
        {
            var output = new TextBox { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, AcceptsReturn = true, MinHeight = 180, MaxHeight = 420 };
            var dialog = new ContentDialog { XamlRoot = XamlRoot, Title = "AI Bridge · Cross-pane brief", Content = output, CloseButtonText = "Done", PrimaryButtonText = canCopy ? "Copy" : null, DefaultButton = ContentDialogButton.Close };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
                package.SetText(text);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
            }
        }

        private void OnKeyDown(object sender, KeyRoutedEventArgs e)
        {
            bool control = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Control).HasFlag(CoreVirtualKeyStates.Down);
            bool alt = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Menu).HasFlag(CoreVirtualKeyStates.Down);
            bool shift = InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down);
            if (control && alt && e.Key == VirtualKey.X) { OnSwapClicked(this, new RoutedEventArgs()); e.Handled = true; }
            else if (control && alt && e.Key == VirtualKey.Left) { SetActivePane(true); e.Handled = true; }
            else if (control && alt && e.Key == VirtualKey.Right) { SetActivePane(false); e.Handled = true; }
            else if (e.Key == VirtualKey.Escape && _soloMode) { _soloMode = false; ApplyLayout(); e.Handled = true; }
            else if (control && shift && e.Key == VirtualKey.M) { ToggleSolo(); e.Handled = true; }
        }
    }
}
