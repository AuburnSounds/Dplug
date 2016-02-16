

#if defined (__unix__) || (defined (__APPLE__) && defined (__MACH__))
#include <dlfcn.h>
typedef __cdecl void*(*VSTPluginMain_t)(void*);
#else
#include <Windows.h>

typedef void* (*VSTPluginMain_t)(void*);
#endif

#include <cstdio>
#include <cstring>
#include <vector>

typedef void* pvoid;

int main(int argc, char**argv)
{
    std::vector<char*> dllPaths;
    if (argc < 2)
    {
        printf("usage: ldvst [-lazy] <thing.vst>\n");
        return 1;
    }

    bool lazy = false;

    for (int i = 1; i < argc; ++i)
    {
        char* arg = argv[i];
        if (strcmp(arg, "-lazy") == 0)
            lazy = true;
        else if (strcmp(arg, "-now") == 0)
            lazy = false;
        else
            dllPaths.push_back(arg);
    }

    for (int i = 0; i < (int)dllPaths.size(); ++i)
    {
        char* dllPath = dllPaths[i];

        #if defined (__unix__) || (defined (__APPLE__) && defined (__MACH__))

            printf("dlopen(%s)\n", dllPath);
            void* handle = dlopen(dllPath, lazy ? RTLD_LAZY : RTLD_NOW);
            if (handle == NULL)
            {
                printf("error: dlopen of %s failed\n", dllPath);
                return 2;
            }

            VSTPluginMain_t VSTPluginMain = (VSTPluginMain_t) dlsym(handle, "VSTPluginMain");
            printf("dlsym returned %p\n", (void*)VSTPluginMain);

            if (VSTPluginMain != NULL)
            {
                void* result = VSTPluginMain(NULL);
                printf("VSTPluginMain returned %p\n", result);
            }

            printf("dlclose(%s)\n\n", dllPath);
            dlclose(handle);

        #else

            printf("LoadLibraryA(%s)\n", dllPath);
            HMODULE handle = LoadLibraryA(dllPath);
            if (handle == NULL)
            {
                printf("error: dlopen of %s failed\n", dllPath);
                return 2;
            }

            VSTPluginMain_t VSTPluginMain = (VSTPluginMain_t)GetProcAddress(handle, "VSTPluginMain");
            printf("GetProcAddress returned %p\n", (void*)VSTPluginMain);

            if (VSTPluginMain != NULL)
            {
                void* result = VSTPluginMain(NULL);
                printf("VSTPluginMain returned %p\n", result);
            }

            printf("FreeLibrary(%s)\n\n", dllPath);
            BOOL result = FreeLibrary(handle);
            if (result == 0)
            {
                printf("FreeLibrary failed\n");
            }

        #endif
    }
    return 0;
}