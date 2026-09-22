using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class InboxControl : UserControl
    {
        private List<SmartReplyOption> _allOptions = new();
        private string _activeFilter = "All";

        public InboxControl()
        {
            this.InitializeComponent();
            this.Loaded += (s, e) =>
            {
                _allOptions = AIService.Shared.GenerateReplyOptions("Latest messages in team channels");
                ApplyFilter();
            };
        }

        private void OnTriageFilterClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string filter)
            {
                _activeFilter = filter;
                ApplyFilter();
            }
        }

        private void ApplyFilter()
        {
            switch (_activeFilter)
            {
                case "Urgent":
                    RepliesRepeater.ItemsSource = _allOptions.Where(o => o.Tone == "Professional" || o.Tone == "Polite Decline").ToList();
                    break;
                case "Meetings":
                    RepliesRepeater.ItemsSource = _allOptions.Where(o => o.Tone == "Propose Time").ToList();
                    break;
                case "Questions":
                    RepliesRepeater.ItemsSource = _allOptions.Where(o => o.Tone == "Friendly" || o.Tone == "Concise").ToList();
                    break;
                case "Reviews":
                    RepliesRepeater.ItemsSource = _allOptions.Where(o => o.Tone == "Professional" || o.Tone == "Concise").ToList();
                    break;
                default:
                    RepliesRepeater.ItemsSource = _allOptions;
                    break;
            }
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
