#include "version.h"

#include <cstdio>
#include <cstring>

int main(int argc, char** argv)
{
    if (argc > 1 && std::strcmp(argv[1], "--version") == 0)
    {
        std::printf("sensor-daemon %s\n", SENSOR_DAEMON_VERSION);
        return 0;
    }
    std::printf("sensor-daemon %s\n", SENSOR_DAEMON_VERSION);
    return 0;
}
