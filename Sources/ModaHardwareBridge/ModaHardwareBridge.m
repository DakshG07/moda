#import "ModaHardwareBridge.h"

#import <Foundation/Foundation.h>
#import <math.h>

@interface KeyboardBrightnessClient : NSObject
- (id)copyKeyboardBacklightIDs;
- (BOOL)isKeyboardBuiltIn:(uint64_t)keyboardID;
- (float)brightnessForKeyboard:(uint64_t)keyboardID;
- (BOOL)setBrightness:(float)brightness forKeyboard:(uint64_t)keyboardID;
@end

ModaKeyboardBrightnessClientRef ModaKeyboardBrightnessClientCreate(void) {
  NSBundle *bundle = [NSBundle bundleWithPath:
      @"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
  if (![bundle load]) return NULL;
  Class clientClass = NSClassFromString(@"KeyboardBrightnessClient");
  if (clientClass == Nil) return NULL;
  KeyboardBrightnessClient *client = [[clientClass alloc] init];
  return (__bridge_retained void *)client;
}

void ModaKeyboardBrightnessClientRelease(ModaKeyboardBrightnessClientRef client) {
  if (client != NULL) {
    CFRelease(client);
  }
}

bool ModaKeyboardBrightnessGet(
    ModaKeyboardBrightnessClientRef clientReference,
    uint64_t *keyboardID,
    float *brightness
) {
  if (clientReference == NULL || keyboardID == NULL || brightness == NULL) return false;
  KeyboardBrightnessClient *client = (__bridge KeyboardBrightnessClient *)clientReference;
  id identifiers = [client copyKeyboardBacklightIDs];
  if (![identifiers conformsToProtocol:@protocol(NSFastEnumeration)]) return false;

  for (NSNumber *identifier in identifiers) {
    uint64_t candidate = identifier.unsignedLongLongValue;
    if ([client isKeyboardBuiltIn:candidate]) {
      *keyboardID = candidate;
      *brightness = [client brightnessForKeyboard:candidate];
      return isfinite(*brightness);
    }
  }
  return false;
}

bool ModaKeyboardBrightnessSet(
    ModaKeyboardBrightnessClientRef clientReference,
    uint64_t keyboardID,
    float brightness
) {
  if (clientReference == NULL) return false;
  KeyboardBrightnessClient *client = (__bridge KeyboardBrightnessClient *)clientReference;
  return [client setBrightness:brightness forKeyboard:keyboardID];
}
