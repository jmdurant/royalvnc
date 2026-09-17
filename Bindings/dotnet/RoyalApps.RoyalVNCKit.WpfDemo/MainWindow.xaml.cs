using System;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using RoyalApps.RoyalVNCKit;

namespace RoyalApps.RoyalVNCKit.WpfDemo;

public partial class MainWindow : Window
{
    VncConnection? _connection;
    VncSettings? _connectionSettings;
    VncConnectionDelegate? _connectionDelegate;

    WriteableBitmap? _writeableBitmap;
    int _framebufferWidth;
    int _framebufferHeight;

    readonly object _bufferLock = new();
    byte[]? _pixelBuffer;

    // Authentication synchronization
    ManualResetEventSlim? _authSignal;
    AuthenticationRequest? _activeAuthRequest;
    bool _authResult;

    public MainWindow()
    {
        InitializeComponent();

        try
        {
            var iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "RoyalApps_1024.png");
            if (System.IO.File.Exists(iconPath))
            {
                Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri(iconPath));
            }
        }
        catch
        {
            // Ignore icon loading failures
        }

        Loaded += (s, e) =>
        {
            Topmost = true;
            Topmost = false;
            Activate();
            Focus();
        };
    }

    protected override void OnClosed(EventArgs e)
    {
        TeardownConnection();
        base.OnClosed(e);
    }

    #region Connection Lifecycle

    void OnConnectClick(object sender, RoutedEventArgs e)
    {
        string host = HostTextBox.Text.Trim();
        if (string.IsNullOrEmpty(host))
        {
            ShowError("Please enter a valid hostname or IP address.");
            return;
        }

        if (!ushort.TryParse(PortTextBox.Text.Trim(), out ushort port) || port == 0)
        {
            port = 5900;
            PortTextBox.Text = "5900";
        }

        TeardownConnection();
        HideError();

        UpdateStatus("Connecting...", isConnected: false, isConnecting: true);
        ConnectButton.IsEnabled = false;

        try
        {
            var settings = new DemoSettings
            {
                Hostname = host,
                Port = port,
                IsDebugLoggingEnabled = false,
                IsShared = true,
                IsScalingEnabled = false,
                UseDisplayLink = false,
                InputMode = InputMode.None,
                IsClipboardRedirectionEnabled = true,
                ColorDepth = ColorDepth.Bits24,
                FrameEncodings = null
            };

            _connectionSettings = new VncSettings(settings);
            _connection = new VncConnection(_connectionSettings);

            _connectionDelegate = new VncConnectionDelegate
            {
                ConnectionStateChanged = OnConnectionStateChanged,
                AuthenticationRequested = OnAuthenticationRequested,
                FramebufferCreated = OnFramebufferCreated,
                FramebufferResized = OnFramebufferResized,
                FramebufferUpdated = OnFramebufferUpdated
            };

            _connection.Delegate = _connectionDelegate;
            _connection.Connect();
        }
        catch (Exception ex)
        {
            ShowError($"Failed to initiate connection: {ex.Message}");
            UpdateStatus("Connection failed", isConnected: false);
            ConnectButton.IsEnabled = true;
        }
    }

    void OnDisconnectClick(object sender, RoutedEventArgs e)
    {
        UpdateStatus("Disconnecting...", isConnected: false);
        _connection?.Disconnect();
    }

    void TeardownConnection()
    {
        _authSignal?.Set();
        _connection?.Dispose();
        _connection = null;
        _connectionDelegate?.Dispose();
        _connectionDelegate = null;
        _connectionSettings?.Dispose();
        _connectionSettings = null;
    }

    void OnConnectionStateChanged(VncConnection connection, VncConnectionState state)
    {
        ConnectionStatus status = state.Status;
        bool displayError = state.DisplayErrorToUser;
        bool isAuthError = state.IsAuthenticationError;
        string? errorDesc = state.ErrorDescription;

        Dispatcher.InvokeAsync(() =>
        {
            switch (status)
            {
                case ConnectionStatus.Connecting:
                    UpdateStatus("Connecting...", isConnected: false, isConnecting: true);
                    break;

                case ConnectionStatus.Connected:
                    UpdateStatus("Connected", isConnected: true);
                    EmptyStatePanel.Visibility = Visibility.Collapsed;
                    ScreenScrollViewer.Visibility = Visibility.Visible;
                    ConnectButton.Visibility = Visibility.Collapsed;
                    DisconnectButton.Visibility = Visibility.Visible;
                    CadButton.IsEnabled = true;
                    ScreenImage.Focus();
                    break;

                case ConnectionStatus.Disconnecting:
                    UpdateStatus("Disconnecting...", isConnected: false);
                    break;

                case ConnectionStatus.Disconnected:
                    UpdateStatus("Disconnected", isConnected: false);
                    EmptyStatePanel.Visibility = Visibility.Visible;
                    ScreenScrollViewer.Visibility = Visibility.Collapsed;
                    ConnectButton.Visibility = Visibility.Visible;
                    ConnectButton.IsEnabled = true;
                    DisconnectButton.Visibility = Visibility.Collapsed;
                    CadButton.IsEnabled = false;

                    if (displayError)
                    {
                        string err = isAuthError
                            ? $"Authentication failed: {errorDesc}"
                            : $"Disconnected: {errorDesc}";
                        ShowError(err);
                    }
                    break;
            }
        });
    }

    #endregion

    #region Framebuffer Rendering

    void OnFramebufferCreated(VncConnection connection, VncFramebuffer framebuffer)
    {
        int width = framebuffer.Width;
        int height = framebuffer.Height;

        lock (_bufferLock)
        {
            _framebufferWidth = width;
            _framebufferHeight = height;
            _pixelBuffer = new byte[width * height * 4];

            if (!framebuffer.PixelData.IsEmpty)
            {
                framebuffer.PixelData.CopyTo(_pixelBuffer);
            }
        }

        Dispatcher.Invoke(() =>
        {
            InitFramebuffer(width, height);
        });
    }

    void OnFramebufferResized(VncConnection connection, VncFramebuffer framebuffer)
    {
        int width = framebuffer.Width;
        int height = framebuffer.Height;

        lock (_bufferLock)
        {
            _framebufferWidth = width;
            _framebufferHeight = height;
            _pixelBuffer = new byte[width * height * 4];

            if (!framebuffer.PixelData.IsEmpty)
            {
                framebuffer.PixelData.CopyTo(_pixelBuffer);
            }
        }

        Dispatcher.Invoke(() =>
        {
            InitFramebuffer(width, height);
        });
    }

    void InitFramebuffer(int width, int height)
    {
        _writeableBitmap = new WriteableBitmap(
            width, height,
            96, 96,
            PixelFormats.Bgra32,
            null);

        lock (_bufferLock)
        {
            if (_pixelBuffer != null)
            {
                _writeableBitmap.WritePixels(
                    new Int32Rect(0, 0, width, height),
                    _pixelBuffer,
                    width * 4,
                    0);
            }
        }

        ScreenImage.Source = _writeableBitmap;
        UpdateScreenLayout();
        UpdateStatus($"Connected ({width}x{height})", isConnected: true);
    }

    void OnFramebufferUpdated(VncConnection connection, VncFramebuffer framebuffer, VncFramebufferRegion region)
    {
        int rx = region.X;
        int ry = region.Y;
        int rw = region.Width;
        int rh = region.Height;

        lock (_bufferLock)
        {
            if (_pixelBuffer == null || _framebufferWidth <= 0) return;

            unsafe
            {
                fixed (byte* src = framebuffer.PixelData)
                fixed (byte* dst = _pixelBuffer)
                {
                    int bytesPerPixel = 4;
                    int stride = _framebufferWidth * bytesPerPixel;
                    int regionBytes = rw * bytesPerPixel;

                    for (int row = 0; row < rh; row++)
                    {
                        int y = ry + row;
                        int offset = (y * stride) + (rx * bytesPerPixel);
                        Buffer.MemoryCopy(src + offset, dst + offset, regionBytes, regionBytes);
                    }
                }
            }
        }

        Dispatcher.InvokeAsync(() =>
        {
            if (_writeableBitmap == null || _pixelBuffer == null) return;

            lock (_bufferLock)
            {
                _writeableBitmap.WritePixels(
                    new Int32Rect(rx, ry, rw, rh),
                    _pixelBuffer,
                    _framebufferWidth * 4,
                    ((ry * _framebufferWidth) + rx) * 4);
            }
        }, DispatcherPriority.Render);
    }

    void OnScalingChanged(object sender, RoutedEventArgs e)
    {
        UpdateScreenLayout();
    }

    void UpdateScreenLayout()
    {
        if (ScreenImage == null || ScreenScrollViewer == null) return;

        if (ScaleToFitCheckBox.IsChecked == true)
        {
            ScreenImage.Stretch = Stretch.Uniform;
            ScreenImage.Width = double.NaN;
            ScreenImage.Height = double.NaN;
            ScreenScrollViewer.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            ScreenScrollViewer.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
        }
        else
        {
            ScreenImage.Stretch = Stretch.None;
            ScreenImage.Width = _framebufferWidth > 0 ? _framebufferWidth : double.NaN;
            ScreenImage.Height = _framebufferHeight > 0 ? _framebufferHeight : double.NaN;
            ScreenScrollViewer.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
            ScreenScrollViewer.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        }
    }

    #endregion

    #region Mouse & Keyboard Input

    bool GetRemoteCoordinates(MouseEventArgs e, out ushort remoteX, out ushort remoteY)
    {
        remoteX = 0;
        remoteY = 0;

        if (_framebufferWidth <= 0 || _framebufferHeight <= 0 || ScreenImage.ActualWidth <= 0 || ScreenImage.ActualHeight <= 0)
            return false;

        Point pos = e.GetPosition(ScreenImage);

        double actualWidth = ScreenImage.ActualWidth;
        double actualHeight = ScreenImage.ActualHeight;

        double scaleX = _framebufferWidth / actualWidth;
        double scaleY = _framebufferHeight / actualHeight;

        int rx = (int)(pos.X * scaleX);
        int ry = (int)(pos.Y * scaleY);

        if (rx < 0 || rx >= _framebufferWidth || ry < 0 || ry >= _framebufferHeight)
            return false;

        remoteX = (ushort)rx;
        remoteY = (ushort)ry;
        return true;
    }

    void OnScreenMouseMove(object sender, MouseEventArgs e)
    {
        if (GetRemoteCoordinates(e, out ushort x, out ushort y))
        {
            _connection?.SendMouseMove(x, y);
        }
    }

    void OnScreenMouseDown(object sender, MouseButtonEventArgs e)
    {
        ScreenImage.Focus();

        if (GetRemoteCoordinates(e, out ushort x, out ushort y))
        {
            MouseButton btn = e.ChangedButton switch
            {
                System.Windows.Input.MouseButton.Left => RoyalApps.RoyalVNCKit.MouseButton.Left,
                System.Windows.Input.MouseButton.Right => RoyalApps.RoyalVNCKit.MouseButton.Right,
                System.Windows.Input.MouseButton.Middle => RoyalApps.RoyalVNCKit.MouseButton.Middle,
                _ => RoyalApps.RoyalVNCKit.MouseButton.Left
            };

            _connection?.SendMouseButtonDown(x, y, btn);
            e.Handled = true;
        }
    }

    void OnScreenMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (GetRemoteCoordinates(e, out ushort x, out ushort y))
        {
            MouseButton btn = e.ChangedButton switch
            {
                System.Windows.Input.MouseButton.Left => RoyalApps.RoyalVNCKit.MouseButton.Left,
                System.Windows.Input.MouseButton.Right => RoyalApps.RoyalVNCKit.MouseButton.Right,
                System.Windows.Input.MouseButton.Middle => RoyalApps.RoyalVNCKit.MouseButton.Middle,
                _ => RoyalApps.RoyalVNCKit.MouseButton.Left
            };

            _connection?.SendMouseButtonUp(x, y, btn);
            e.Handled = true;
        }
    }

    void OnScreenMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (GetRemoteCoordinates(e, out ushort x, out ushort y))
        {
            _connection?.SendMouseScroll(x, y, 0, e.Delta);
            e.Handled = true;
        }
    }

    void OnScreenKeyDown(object sender, KeyEventArgs e)
    {
        Key k = e.Key == Key.System ? e.SystemKey : e.Key;
        var sym = KeyMapper.MapSpecialKey(k);
        if (sym.HasValue)
        {
            _connection?.SendKeyDown(sym.Value);
            e.Handled = true;
        }
    }

    void OnScreenKeyUp(object sender, KeyEventArgs e)
    {
        Key k = e.Key == Key.System ? e.SystemKey : e.Key;
        var sym = KeyMapper.MapSpecialKey(k);
        if (sym.HasValue)
        {
            _connection?.SendKeyUp(sym.Value);
            e.Handled = true;
        }
    }

    void OnScreenTextInput(object sender, TextCompositionEventArgs e)
    {
        if (!string.IsNullOrEmpty(e.Text))
        {
            foreach (char c in e.Text)
            {
                uint sym = c;
                _connection?.SendKeyDown((KeySymbol)sym);
                _connection?.SendKeyUp((KeySymbol)sym);
            }
            e.Handled = true;
        }
    }

    void OnCadClick(object sender, RoutedEventArgs e)
    {
        if (_connection == null) return;

        // Send Ctrl+Alt+Delete sequence
        _connection.SendKeyDown(KeySymbol.XK_Control_L);
        _connection.SendKeyDown(KeySymbol.XK_Alt_L);
        _connection.SendKeyDown(KeySymbol.XK_Delete);

        _connection.SendKeyUp(KeySymbol.XK_Delete);
        _connection.SendKeyUp(KeySymbol.XK_Alt_L);
        _connection.SendKeyUp(KeySymbol.XK_Control_L);
    }

    #endregion

    #region Authentication Modal

    bool OnAuthenticationRequested(VncConnection connection, AuthenticationRequest request)
    {
        _activeAuthRequest = request;
        _authSignal = new ManualResetEventSlim(false);
        _authResult = false;

        Dispatcher.Invoke(() =>
        {
            string typeName = request.AuthenticationType switch
            {
                AuthenticationType.Vnc => "VNC Password",
                AuthenticationType.AppleRemoteDesktop => "Apple Remote Desktop",
                AuthenticationType.UltraVncMSLogonII => "UltraVNC MS Logon II",
                _ => "Remote Server"
            };

            AuthTypeLabel.Text = $"Authentication type: {typeName}";
            UsernamePanel.Visibility = request.RequiresUsername ? Visibility.Visible : Visibility.Collapsed;
            AuthPasswordBox.Password = "";
            AuthModalOverlay.Visibility = Visibility.Visible;

            if (request.RequiresUsername)
                AuthUsernameBox.Focus();
            else
                AuthPasswordBox.Focus();
        });

        // Wait on worker thread for user response
        _authSignal.Wait();
        _authSignal.Dispose();
        _authSignal = null;

        return _authResult;
    }

    void OnAuthSubmitClick(object sender, RoutedEventArgs e)
    {
        if (_activeAuthRequest != null)
        {
            if (_activeAuthRequest.RequiresUsername)
                _activeAuthRequest.Username = AuthUsernameBox.Text.Trim();

            if (_activeAuthRequest.RequiresPassword)
                _activeAuthRequest.Password = AuthPasswordBox.Password;

            _authResult = true;
        }

        AuthModalOverlay.Visibility = Visibility.Collapsed;
        _authSignal?.Set();
    }

    void OnAuthCancelClick(object sender, RoutedEventArgs e)
    {
        _authResult = false;
        AuthModalOverlay.Visibility = Visibility.Collapsed;
        _authSignal?.Set();
    }

    void OnAuthPasswordKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            OnAuthSubmitClick(sender, e);
        }
    }

    #endregion

    #region Status & Error Helpers

    void UpdateStatus(string text, bool isConnected, bool isConnecting = false)
    {
        StatusLabel.Text = text;

        if (isConnected)
        {
            StatusDot.Fill = (SolidColorBrush)FindResource("SuccessColor");
        }
        else if (isConnecting)
        {
            StatusDot.Fill = (SolidColorBrush)FindResource("AccentColor");
        }
        else
        {
            StatusDot.Fill = (SolidColorBrush)FindResource("TextSecondary");
        }
    }

    void ShowError(string message)
    {
        ErrorMessageText.Text = message;
        ErrorBanner.Visibility = Visibility.Visible;
    }

    void HideError()
    {
        ErrorBanner.Visibility = Visibility.Collapsed;
    }

    #endregion

    readonly struct DemoSettings : IVncSettings
    {
        public string Hostname { get; init; }
        public ushort Port { get; init; }
        public InputMode InputMode { get; init; }
        public ColorDepth ColorDepth { get; init; }
        public bool IsClipboardRedirectionEnabled { get; init; }
        public bool IsDebugLoggingEnabled { get; init; }
        public bool IsScalingEnabled { get; init; }
        public bool IsShared { get; init; }
        public bool UseDisplayLink { get; init; }
        public VncFrameEncodingType[]? FrameEncodings { get; init; }
    }
}
