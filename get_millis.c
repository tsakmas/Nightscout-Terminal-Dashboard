#include <stdio.h>
#include <sys/time.h>
#include <time.h>

int main() {
    // Structure to hold the time in seconds and microseconds
    struct timeval tv;
    
    // Get the current time of day.
    if (gettimeofday(&tv, NULL) != 0) {
        // Simple error handling
        return 1;
    }
    
    // Calculate milliseconds: (seconds * 1000) + (microseconds / 1000)
    // We use 'long long' to ensure the result is large enough for the epoch time in milliseconds.
    long long milliseconds = (long long)tv.tv_sec * 1000LL + (long long)tv.tv_usec / 1000LL;
    
    // Print the result as a single integer
    printf("%lld\n", milliseconds);
    
    return 0;
}
