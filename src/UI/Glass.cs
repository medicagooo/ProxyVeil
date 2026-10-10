using System;
using System.Runtime.InteropServices;
public static class ProxyVeilGlass {
    [StructLayout(LayoutKind.Sequential)] private struct Margins { public int L, R, T, B; }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref Margins margins);
    public static bool Apply(IntPtr hwnd) {
        var margin = new Margins { L = -1, R = -1, T = -1, B = -1 };
        DwmExtendFrameIntoClientArea(hwnd, ref margin);
        int rounded = 2;
        DwmSetWindowAttribute(hwnd, 33, ref rounded, sizeof(int));
        int acrylic = 3;
        return DwmSetWindowAttribute(hwnd, 38, ref acrylic, sizeof(int)) == 0;
    }
}
