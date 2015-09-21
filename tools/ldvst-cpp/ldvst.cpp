#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <vector>

typedef __cdecl void* (*VSTPluginMain_t)(void*);

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

    for (int i = 0; i < dllPaths.size(); ++i)
    {
        char* dllPath = dllPaths[i];

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
    }
    return 0;
}