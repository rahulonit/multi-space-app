using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class InboxControl : UserControl
    {
        public InboxControl()
        {
            this.InitializeComponent();
            this.Loaded += (s, e) =>
            {
                var options = AIService.Shared.GenerateReplyOptions("Latest messages in team channels");
                RepliesRepeater.ItemsSource = options;
            };
        }

        private void OnCopyReplyClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string text)
            {
                var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
                package.SetText(text);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
                MainViewModel.Shared.ShowToast("Reply draft copied to clipboard!");
            }
        }
    }
}
