#pragma once
#ifdef _WIN32
#include <windows.h>
#include <delayimp.h>

FARPROC WINAPI delay_load_hook(unsigned dliNotify, PDelayLoadInfo pdli);
#endif