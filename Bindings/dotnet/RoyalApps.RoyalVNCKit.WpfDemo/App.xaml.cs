using System;
using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace RoyalApps.RoyalVNCKit.WpfDemo;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        string logDir = AppDomain.CurrentDomain.BaseDirectory;

        DispatcherUnhandledException += (s, args) =>
        {
            File.WriteAllText(Path.Combine(logDir, "wpf_dispatcher_error.log"), args.Exception.ToString());
            MessageBox.Show(args.Exception.ToString(), "RoyalVNC Dispatcher Error");
            args.Handled = true;
        };

        AppDomain.CurrentDomain.UnhandledException += (s, args) =>
        {
            File.WriteAllText(Path.Combine(logDir, "wpf_domain_error.log"), args.ExceptionObject.ToString());
            MessageBox.Show(args.ExceptionObject.ToString(), "RoyalVNC Fatal Error");
        };

        try
        {
            var window = new MainWindow();
            MainWindow = window;
            window.Show();
        }
        catch (Exception ex)
        {
            File.WriteAllText(Path.Combine(logDir, "wpf_startup_error.log"), ex.ToString());
            MessageBox.Show(ex.ToString(), "RoyalVNC Startup Error");
        }
    }
}
