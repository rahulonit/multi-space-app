using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public class PaletteCommand
    {
        public string Title { get; set; } = string.Empty;
        public string Category { get; set; } = string.Empty;
        public Action Action { get; set; } = () => { };
    }

    public sealed partial class CommandPaletteControl : UserControl
    {
        private readonly List<PaletteCommand> _allCommands = new();

        public CommandPaletteControl()
        {
            this.InitializeComponent();
            this.Loaded += (s, e) =>
            {
                PaletteSearchBox.Focus(FocusState.Programmatic);
                BuildCommandsList();
                FilterCommands("");
            };
        }

        private void BuildCommandsList()
        {
            _allCommands.Clear();
            var vm = MainViewModel.Shared;

            // Navigation
            _allCommands.Add(new PaletteCommand { Title = "Go to Overview Dashboard", Category = "Navigation", Action = () => vm.Navigate(NavigationDestination.Overview) });
            _allCommands.Add(new PaletteCommand { Title = "Open Private Browser", Category = "Navigation", Action = () => vm.Navigate(NavigationDestination.Browser) });
            _allCommands.Add(new PaletteCommand { Title = "Open Settings & Accounts", Category = "Navigation", Action = () => vm.Navigate(NavigationDestination.Settings) });

            // Actions
            _allCommands.Add(new PaletteCommand { Title = "Toggle Split View", Category = "Actions", Action = () => vm.ToggleSplitView() });
            _allCommands.Add(new PaletteCommand { Title = "Swap Split Panes (⇄)", Category = "Actions", Action = () => vm.SwapSplitPanes() });
            _allCommands.Add(new PaletteCommand { Title = "Lock PINGGO Now", Category = "Security", Action = () => SecurityService.Shared.LockApp() });

            // AI Assistant Controls
            _allCommands.Add(new PaletteCommand { Title = "Use Google Gemini for Smart Replies", Category = "AI Assistant", Action = () => { vm.Preferences.AiProvider = "gemini"; vm.ShowToast("Active AI set to Google Gemini"); } });
            _allCommands.Add(new PaletteCommand { Title = "Use OpenAI ChatGPT for Smart Replies", Category = "AI Assistant", Action = () => { vm.Preferences.AiProvider = "chatgpt"; vm.ShowToast("Active AI set to OpenAI ChatGPT"); } });
            _allCommands.Add(new PaletteCommand { Title = $"Use Local Ollama ({vm.Preferences.OllamaModel})", Category = "AI Assistant", Action = () => { vm.Preferences.AiProvider = "ollama"; vm.ShowToast($"Active AI set to Local Ollama ({vm.Preferences.OllamaModel})"); } });
            _allCommands.Add(new PaletteCommand { Title = "Set Persona: Executive & Professional", Category = "AI Assistant", Action = () => { vm.Preferences.PersonaStyle = "Professional"; vm.ShowToast("AI Persona set to Professional"); } });
            _allCommands.Add(new PaletteCommand { Title = "Set Persona: Friendly & Casual", Category = "AI Assistant", Action = () => { vm.Preferences.PersonaStyle = "Casual"; vm.ShowToast("AI Persona set to Casual"); } });

            // Social platforms
            foreach (var p in vm.Platforms)
            {
                _allCommands.Add(new PaletteCommand
                {
                    Title = $"Switch to {p.Name}",
                    Category = "Workspaces",
                    Action = () => vm.SelectPlatform(p.Id)
                });
            }

            // Accounts
            foreach (var acc in vm.Accounts)
            {
                var plat = vm.Platforms.FirstOrDefault(p => p.Id == acc.PlatformID);
                var platName = plat?.Name ?? acc.PlatformID;
                _allCommands.Add(new PaletteCommand
                {
                    Title = $"Switch to {platName} · {acc.AccountName}",
                    Category = "Accounts",
                    Action = () => vm.SelectAccount(acc.Id)
                });
            }
        }

        private void FilterCommands(string query)
        {
            var filtered = string.IsNullOrWhiteSpace(query)
                ? _allCommands
                : _allCommands.Where(c => c.Title.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                                          c.Category.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();

            ResultsListView.ItemsSource = filtered;
            if (filtered.Any()) ResultsListView.SelectedIndex = 0;
        }

        private void OnSearchTextChanged(object sender, TextChangedEventArgs e)
        {
            FilterCommands(PaletteSearchBox.Text);
        }

        private void OnSearchKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Escape)
            {
                MainViewModel.Shared.ToggleCommandPalette();
            }
            else if (e.Key == Windows.System.VirtualKey.Enter)
            {
                if (ResultsListView.SelectedItem is PaletteCommand cmd)
                {
                    ExecuteCommand(cmd);
                }
            }
        }

        private void OnCommandItemClicked(object sender, ItemClickEventArgs e)
        {
            if (e.ClickedItem is PaletteCommand cmd)
            {
                ExecuteCommand(cmd);
            }
        }

        private void ExecuteCommand(PaletteCommand cmd)
        {
            MainViewModel.Shared.ToggleCommandPalette();
            cmd.Action();
        }

        private void OnBackdropTapped(object sender, Microsoft.UI.Xaml.Input.TappedRoutedEventArgs e)
        {
            MainViewModel.Shared.ToggleCommandPalette();
        }
    }
}
