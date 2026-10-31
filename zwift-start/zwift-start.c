/* LinuxZwiftLauncher.exe (zwift-start.c) - start ZwiftApp.exe the way ZwiftLauncher.exe does. Part of zwift-linux.
 *
 *   LinuxZwiftLauncher.exe TOKENFILE LAUNCHER_VERSION
 *
 * The launcher calls Process.Start("ZwiftApp.exe", "--launcher_version=<v> --token=<json>"), which
 * gives the game the raw command line  "ZwiftApp.exe" --launcher_version=<v> --token={"access_token":...}
 * with the token JSON's quotes unescaped. Passing the token as a normal Unix argument through Wine
 * would escape those quotes, so this helper builds the identical command line with CreateProcessW.
 * TOKENFILE (the token response JSON) is deleted as soon as it has been read, before the game starts.
 * Runs in the game folder; waits for the game and returns its exit code.
 *
 * Installed as LinuxZwiftLauncher.exe: at startup ZwiftApp.exe checks its parent process, and unless
 * the parent's path contains "ZwiftLauncher.exe" (or ZwiftHelper.exe / devenv.exe) it runs
 * ZwiftLauncher.exe and exits, or shows "ERROR ZA1 Could not run Update process" when that fails.
 * Built as a GUI program (no console), so Wine opens no extra console window next to the game:
 *   x86_64-w64-mingw32-gcc -municode -O2 -s -Wl,--subsystem,windows -o LinuxZwiftLauncher.exe zwift-start.c */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

/* No console to print to: show the error in a box, which also reaches stderr through Wine's log. */
static int fail(int code, const wchar_t *fmt, ...)
{
    wchar_t msg[1024];
    va_list ap;
    va_start(ap, fmt);
    vswprintf(msg, 1024, fmt, ap);
    va_end(ap);
    fwprintf(stderr, L"LinuxZwiftLauncher: %ls\n", msg);
    MessageBoxW(NULL, msg, L"Zwift", MB_OK | MB_ICONERROR);
    return code;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc < 3) return fail(2, L"usage: LinuxZwiftLauncher.exe TOKENFILE LAUNCHER_VERSION");

    HANDLE f = CreateFileW(argv[1], GENERIC_READ, 0, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return fail(2, L"cannot open %ls", argv[1]);
    DWORD size = GetFileSize(f, NULL), got = 0;
    char *json = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, size + 1);
    ReadFile(f, json, size, &got, NULL);
    CloseHandle(f);
    DeleteFileW(argv[1]);
    while (got && (json[got - 1] == '\n' || json[got - 1] == '\r' || json[got - 1] == ' ')) json[--got] = 0;
    if (!got || json[0] != '{') return fail(2, L"token file is not JSON");

    int wlen = MultiByteToWideChar(CP_UTF8, 0, json, -1, NULL, 0);
    wchar_t *wjson = HeapAlloc(GetProcessHeap(), 0, wlen * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, json, -1, wjson, wlen);
    SecureZeroMemory(json, size);

    wchar_t exe[MAX_PATH];
    GetFullPathNameW(L"ZwiftApp.exe", MAX_PATH, exe, NULL);
    size_t clen = wcslen(exe) + wcslen(argv[2]) + wlen + 64;
    wchar_t *cmd = HeapAlloc(GetProcessHeap(), 0, clen * sizeof(wchar_t));
    swprintf(cmd, clen, L"\"%ls\" --launcher_version=%ls --token=%ls", exe, argv[2], wjson);
    SecureZeroMemory(wjson, wlen * sizeof(wchar_t));

    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
        return fail(1, L"cannot start %ls (error %lu)", exe, GetLastError());
    SecureZeroMemory(cmd, clen * sizeof(wchar_t));
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
