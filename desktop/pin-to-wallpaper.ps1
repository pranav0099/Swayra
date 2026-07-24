# Pins a window (by HWND) onto the Windows wallpaper layer so it lives on the
# desktop background — visible when you're at the desktop, never covering apps.
#
# It asks Progman to spawn the "WorkerW" wallpaper host, finds it, then reparents
# the given window into it and positions it. Invoked by the Electron widget.
#
#   powershell -ExecutionPolicy Bypass -File pin-to-wallpaper.ps1 -Hwnd <n> -X <n> -Y <n> -W <n> -H <n>
param(
  [Parameter(Mandatory=$true)][long]$Hwnd,
  [int]$X = 24,
  [int]$Y = 24,
  [int]$W = 240,
  [int]$H = 168,
  [switch]$Unpin
)

$src = @"
using System;
using System.Runtime.InteropServices;
public class WallpaperPin {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string cls, string win);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
  public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr child, string cls, string win);
  [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr newParent);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

  [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
  private static extern IntPtr GetWindowLong32(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
  private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
  private static extern IntPtr SetWindowLong32(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

  [DllImport("user32.dll", EntryPoint = "SetWindowLongPtr")]
  private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

  public static IntPtr GetWindowLong(IntPtr hWnd, int nIndex) {
    if (IntPtr.Size == 8) return GetWindowLongPtr64(hWnd, nIndex);
    else return GetWindowLong32(hWnd, nIndex);
  }

  public static IntPtr SetWindowLong(IntPtr hWnd, int nIndex, IntPtr dwNewLong) {
    if (IntPtr.Size == 8) return SetWindowLongPtr64(hWnd, nIndex, dwNewLong);
    else return SetWindowLong32(hWnd, nIndex, dwNewLong);
  }

  static IntPtr _worker = IntPtr.Zero;
  static bool Scan(IntPtr top, IntPtr l) {
    IntPtr shell = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
    if (shell != IntPtr.Zero) {
      // The WorkerW *after* the window that hosts the icons is the wallpaper layer.
      _worker = FindWindowEx(IntPtr.Zero, top, "WorkerW", null);
    }
    return true;
  }

  public static IntPtr FindWorkerW() {
    IntPtr progman = FindWindow("Progman", null);
    IntPtr res;
    // 0x052C makes Progman create the WorkerW behind the desktop icons.
    SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0, 1000, out res);
    _worker = IntPtr.Zero;
    EnumWindows(Scan, IntPtr.Zero);
    if (_worker == IntPtr.Zero) _worker = progman; // fallback: parent to Progman itself
    return _worker;
  }

  public static string Pin(IntPtr child, int x, int y, int w, int h) {
    IntPtr worker = FindWorkerW();

    // Modify styles for child window
    const int GWL_STYLE = -16;
    const uint WS_POPUP = 0x80000000;
    const uint WS_CHILD = 0x40000000;
    const uint WS_CLIPSIBLINGS = 0x04000000;

    IntPtr style = GetWindowLong(child, GWL_STYLE);
    long styleVal = style.ToInt64();
    styleVal = (styleVal & ~WS_POPUP) | WS_CHILD | WS_CLIPSIBLINGS;
    SetWindowLong(child, GWL_STYLE, new IntPtr(styleVal));

    // Remove topmost (WS_EX_TOPMOST) extended style if present
    const int GWL_EXSTYLE = -20;
    const uint WS_EX_TOPMOST = 0x00000008;
    IntPtr exStyle = GetWindowLong(child, GWL_EXSTYLE);
    long exStyleVal = exStyle.ToInt64();
    if ((exStyleVal & WS_EX_TOPMOST) != 0) {
      exStyleVal &= ~WS_EX_TOPMOST;
      SetWindowLong(child, GWL_EXSTYLE, new IntPtr(exStyleVal));
    }

    SetParent(child, worker);
    MoveWindow(child, x, y, w, h, true);

    // Call SetWindowPos to apply style and position updates
    // SWP_FRAMECHANGED = 0x0020, SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040
    SetWindowPos(child, IntPtr.Zero, x, y, w, h, 0x0020 | 0x0010 | 0x0040);

    return worker.ToString();
  }

  public static void Unpin(IntPtr child, int x, int y, int w, int h) {
    // Restore styles for top-level popup window
    const int GWL_STYLE = -16;
    const uint WS_POPUP = 0x80000000;
    const uint WS_CHILD = 0x40000000;

    IntPtr style = GetWindowLong(child, GWL_STYLE);
    long styleVal = style.ToInt64();
    styleVal = (styleVal & ~WS_CHILD) | WS_POPUP; // Add WS_POPUP, remove WS_CHILD
    SetWindowLong(child, GWL_STYLE, new IntPtr(styleVal));

    // Restore topmost (WS_EX_TOPMOST) extended style
    const int GWL_EXSTYLE = -20;
    const uint WS_EX_TOPMOST = 0x00000008;
    IntPtr exStyle = GetWindowLong(child, GWL_EXSTYLE);
    long exStyleVal = exStyle.ToInt64();
    exStyleVal |= WS_EX_TOPMOST;
    SetWindowLong(child, GWL_EXSTYLE, new IntPtr(exStyleVal));

    SetParent(child, IntPtr.Zero);
    MoveWindow(child, x, y, w, h, true);

    // SWP_FRAMECHANGED = 0x0020, SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040
    SetWindowPos(child, new IntPtr(-1), x, y, w, h, 0x0020 | 0x0010 | 0x0040); // HWND_TOPMOST = -1
  }
}
"@

try {
  Add-Type -TypeDefinition $src -Language CSharp -ErrorAction Stop
  if ($Unpin) {
    [WallpaperPin]::Unpin([IntPtr]$Hwnd, $X, $Y, $W, $H)
    Write-Output "UNPINNED"
    exit 0
  } else {
    $worker = [WallpaperPin]::Pin([IntPtr]$Hwnd, $X, $Y, $W, $H)
    Write-Output ("PINNED workerw=" + $worker)
    exit 0
  }
} catch {
  Write-Output ("PIN_FAILED " + $_.Exception.Message)
  exit 1
}
