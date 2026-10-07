/*
 * Paper Front Windows portable entry point.
 *
 * Godot resolves user:// and opens its log before any GDScript autoload runs.
 * Set the child process environment before launching its embedded game pack.
 * This changes only this process and its child, never the user's environment.
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

static void show_failure(const wchar_t *message, DWORD error) {
    wchar_t detail[512];
    if (error) {
        _snwprintf(detail, sizeof(detail) / sizeof(detail[0]),
                   L"%ls\n\nWindows error: %lu", message, (unsigned long)error);
        detail[sizeof(detail) / sizeof(detail[0]) - 1] = L'\0';
    } else {
        wcsncpy(detail, message, sizeof(detail) / sizeof(detail[0]));
        detail[sizeof(detail) / sizeof(detail[0]) - 1] = L'\0';
    }
    MessageBoxW(NULL, detail, L"Paper Front", MB_OK | MB_ICONERROR);
}

static wchar_t *join_path(const wchar_t *root, const wchar_t *suffix) {
    size_t length = wcslen(root) + wcslen(suffix) + 2;
    wchar_t *path = calloc(length, sizeof(wchar_t));
    if (!path) return NULL;
    const wchar_t *separator = root[wcslen(root) - 1] == L'\\' ? L"" : L"\\";
    _snwprintf(path, length, L"%ls%ls%ls", root, separator, suffix);
    return path;
}

static int ensure_directory(const wchar_t *path) {
    if (CreateDirectoryW(path, NULL)) return 1;
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        DWORD attributes = GetFileAttributesW(path);
        if (attributes != INVALID_FILE_ATTRIBUTES &&
            (attributes & FILE_ATTRIBUTE_DIRECTORY)) return 1;
    }
    show_failure(L"Cannot create portable data folders. Extract the complete ZIP to a writable folder.", GetLastError());
    return 0;
}

static int set_environment(const wchar_t *name, const wchar_t *value) {
    if (SetEnvironmentVariableW(name, value)) return 1;
    show_failure(L"Cannot configure the portable process environment.", GetLastError());
    return 0;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous,
                   PWSTR arguments, int show) {
    (void)instance; (void)previous; (void)show;
    int result = 1;
    wchar_t *root = calloc(32768, sizeof(wchar_t));
    wchar_t *data = NULL, *cache = NULL, *temporary = NULL, *logs = NULL;
    wchar_t *log_file = NULL, *runtime = NULL, *probe_path = NULL, *command = NULL;
    HANDLE probe = INVALID_HANDLE_VALUE;
    PROCESS_INFORMATION process = {0};
    STARTUPINFOW startup = {0};

    if (!root) goto memory_failure;
    DWORD path_length = GetModuleFileNameW(NULL, root, 32768);
    if (!path_length || path_length >= 32768) {
        show_failure(L"Cannot locate the portable game folder.", GetLastError());
        goto cleanup;
    }
    wchar_t *separator = wcsrchr(root, L'\\');
    if (!separator) {
        show_failure(L"Cannot locate the portable game folder.", 0);
        goto cleanup;
    }
    if (separator == root + 2 && root[1] == L':') separator[1] = L'\0';
    else *separator = L'\0';
    data = join_path(root, L"user_data");
    cache = join_path(root, L"user_data\\cache");
    temporary = join_path(root, L"user_data\\tmp");
    logs = join_path(root, L"user_data\\logs");
    log_file = join_path(root, L"user_data\\logs\\godot.log");
    runtime = join_path(root, L"bin\\PaperFrontRuntime.exe");
    if (!data || !cache || !temporary || !logs || !log_file || !runtime)
        goto memory_failure;

    DWORD attributes = GetFileAttributesW(runtime);
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
        show_failure(L"The game runtime is missing. Extract the complete ZIP before starting PaperFront.exe.", 0);
        goto cleanup;
    }
    if (!ensure_directory(data) || !ensure_directory(cache) ||
        !ensure_directory(temporary) || !ensure_directory(logs)) goto cleanup;

    wchar_t probe_name[96];
    _snwprintf(probe_name, 96, L"user_data\\.write_probe_%lu_%llu.tmp",
               (unsigned long)GetCurrentProcessId(),
               (unsigned long long)GetTickCount64());
    probe_path = join_path(root, probe_name);
    if (!probe_path) goto memory_failure;
    probe = CreateFileW(probe_path, GENERIC_WRITE, 0, NULL, CREATE_NEW,
                        FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, NULL);
    if (probe == INVALID_HANDLE_VALUE) {
        show_failure(L"The portable game folder is not writable. Move the extracted folder to a location where you can save files.", GetLastError());
        goto cleanup;
    }
    CloseHandle(probe);
    probe = INVALID_HANDLE_VALUE;

    if (!set_environment(L"APPDATA", root) ||
        !set_environment(L"LOCALAPPDATA", cache) ||
        !set_environment(L"TEMP", temporary) ||
        !set_environment(L"TMP", temporary) ||
        !set_environment(L"PAPER_FRONT_PORTABLE_ROOT", root)) goto cleanup;

    /* Preserve the original argument string, including quoting and Unicode. */
    size_t command_length = wcslen(runtime) + wcslen(log_file) +
                            wcslen(arguments) + 24;
    command = calloc(command_length, sizeof(wchar_t));
    if (!command) goto memory_failure;
    _snwprintf(command, command_length, L"\"%ls\" --log-file \"%ls\" %ls",
               runtime, log_file, arguments);

    startup.cb = sizeof(startup);
    if (!CreateProcessW(runtime, command, NULL, NULL, TRUE, 0,
                        NULL, root, &startup, &process)) {
        show_failure(L"Cannot start Paper Front. Ensure bin/PaperFrontRuntime.exe and the native DLL are present.", GetLastError());
        goto cleanup;
    }
    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exit_code;
    if (GetExitCodeProcess(process.hProcess, &exit_code)) result = (int)exit_code;
    CloseHandle(process.hProcess);
    goto cleanup;

memory_failure:
    show_failure(L"Not enough memory to start Paper Front.", 0);
cleanup:
    if (probe != INVALID_HANDLE_VALUE) CloseHandle(probe);
    free(command); free(probe_path); free(runtime); free(log_file);
    free(logs); free(temporary); free(cache); free(data); free(root);
    return result;
}
