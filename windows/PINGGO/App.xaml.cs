using System;
using Microsoft.UI.Xaml;
using PINGGO.Services;

namespace PINGGO
{
    public partial class App : Application
    {
        public static Window? CurrentWindow { get; private set; }

        public App()
        {
            this.InitializeComponent();
        }

        protected override void OnLaunched(LaunchActivatedEventArgs args)
        {
            var window = new MainWindow();
            CurrentWindow = window;
            window.Activate();

            // Start inactivity lock check timer
            var timer = new System.Timers.Timer(30000); // Check every 30s
            timer.Elapsed += (s, e) =>
            {
                SecurityService.Shared.CheckInactivityLock();
            };
            timer.Start();
        }
    }
}
