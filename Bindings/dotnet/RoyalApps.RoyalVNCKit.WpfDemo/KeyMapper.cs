using System.Windows.Input;
using RoyalApps.RoyalVNCKit;

namespace RoyalApps.RoyalVNCKit.WpfDemo;

public static class KeyMapper
{
    public static KeySymbol? MapSpecialKey(Key key) => key switch
    {
        Key.Back => KeySymbol.XK_BackSpace,
        Key.Tab => KeySymbol.XK_Tab,
        Key.LineFeed => KeySymbol.XK_Linefeed,
        Key.Clear => KeySymbol.XK_Clear,
        Key.Return => KeySymbol.XK_Return,
        Key.Pause => KeySymbol.XK_Pause,
        Key.Scroll => KeySymbol.XK_Scroll_Lock,
        Key.Escape => KeySymbol.XK_Escape,
        Key.Delete => KeySymbol.XK_Delete,
        Key.Home => KeySymbol.XK_Home,
        Key.Left => KeySymbol.XK_Left,
        Key.Up => KeySymbol.XK_Up,
        Key.Right => KeySymbol.XK_Right,
        Key.Down => KeySymbol.XK_Down,
        Key.PageUp => KeySymbol.XK_Page_Up,
        Key.PageDown => KeySymbol.XK_Page_Down,
        Key.End => KeySymbol.XK_End,
        Key.PrintScreen => KeySymbol.XK_Print,
        Key.Insert => KeySymbol.XK_Insert,
        Key.LeftShift => KeySymbol.XK_Shift_L,
        Key.RightShift => KeySymbol.XK_Shift_R,
        Key.LeftCtrl => KeySymbol.XK_Control_L,
        Key.RightCtrl => KeySymbol.XK_Control_R,
        Key.LeftAlt or Key.System => KeySymbol.XK_Alt_L,
        Key.RightAlt => KeySymbol.XK_Alt_R,
        Key.CapsLock => KeySymbol.XK_Caps_Lock,
        Key.NumLock => KeySymbol.XK_Num_Lock,
        Key.Space => KeySymbol.XK_space,
        Key.F1 => KeySymbol.XK_F1,
        Key.F2 => KeySymbol.XK_F2,
        Key.F3 => KeySymbol.XK_F3,
        Key.F4 => KeySymbol.XK_F4,
        Key.F5 => KeySymbol.XK_F5,
        Key.F6 => KeySymbol.XK_F6,
        Key.F7 => KeySymbol.XK_F7,
        Key.F8 => KeySymbol.XK_F8,
        Key.F9 => KeySymbol.XK_F9,
        Key.F10 => KeySymbol.XK_F10,
        Key.F11 => KeySymbol.XK_F11,
        Key.F12 => KeySymbol.XK_F12,
        _ => null
    };
}
