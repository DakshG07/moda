#ifndef MODA_HARDWARE_BRIDGE_H
#define MODA_HARDWARE_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef void *ModaKeyboardBrightnessClientRef;

ModaKeyboardBrightnessClientRef ModaKeyboardBrightnessClientCreate(void);
void ModaKeyboardBrightnessClientRelease(ModaKeyboardBrightnessClientRef client);
bool ModaKeyboardBrightnessGet(
    ModaKeyboardBrightnessClientRef client,
    uint64_t *keyboardID,
    float *brightness
);
bool ModaKeyboardBrightnessSet(
    ModaKeyboardBrightnessClientRef client,
    uint64_t keyboardID,
    float brightness
);

#endif
