// HingeControl — drives iPhone Duo's hinge (and its orientation picker)
// from inside the simulator, the way Device Hub does.
//
// Device Hub speaks CoreDevice's UniversalHID to the guest daemon
// `dtuhidd`, which owns a virtual HID service it calls `avpCustom`
// (usage page 0xFF61, usage 0x5B) and dispatches every pose command on it
// as a vendor-defined IOHIDEvent whose payload is a keyed record:
//   {provider: "com.apple.Virtualization.VirtualMachines",
//    source: "hinge-slider-control", type: "range", value: <degrees>}
// for the hinge, and {source: "orientation-picker-control", type: "enum",
// value: "portrait"} for the picker. The runtime's consumer of those
// events does not care which process's service they came from — so this
// tool, spawned in the guest by `simctl spawn`, registers a service of the
// same shape with the private HID.framework and dispatches the same
// events. Measured against Device Hub with a HID event monitor in the
// guest; the encoder below reproduces its payload byte for byte.
//
// Record layout: `d3 00 00 00`, then items of [u24 aux][u8 type], the
// top bit of `type` marking a container's last entry. 0x01 dictionary
// (aux = entry count), 0x08 key (NUL-terminated, aux = length incl NUL),
// 0x09 string (aux = length), 0x04 double (aux = 0x3f, 8 bytes LE).
// Every item is padded to 4 bytes.
//
//   HingeControl angle <degrees>
//   HingeControl sweep <from> <to> <milliseconds>     (60 Hz, ease-out)
//   HingeControl orientation <portrait|landscapeLeft|landscapeRight|portraitUpsideDown>
//   HingeControl serve        — the same verbs, one per line on stdin,
//                               until EOF; baguette keeps one of these
//                               per device so a pose costs no spawn.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach_time.h>

typedef void *IOHIDEventRef;
static IOHIDEventRef (*IOHIDEventCreateVendorDefinedEvent)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint8_t *, CFIndex, uint32_t);

// --- payload -----------------------------------------------------------
// [u24 aux][u8 type | 0x80 on the container's last entry]; keys are
// NUL-terminated (type 8), strings not (type 9), doubles (type 4, aux 0x3f);
// every item is padded to 4 bytes; the whole thing starts with d3 00 00 00.
static void putHeader(NSMutableData *d, uint32_t aux, uint8_t type) {
  uint8_t h[4] = { aux & 0xff, (aux >> 8) & 0xff, (aux >> 16) & 0xff, type };
  [d appendBytes:h length:4];
}
static void pad4(NSMutableData *d) { while (d.length % 4) { uint8_t z = 0; [d appendBytes:&z length:1]; } }
static void putKey(NSMutableData *d, const char *k) {
  size_t n = strlen(k) + 1; putHeader(d, (uint32_t)n, 0x08); [d appendBytes:k length:n]; pad4(d);
}
static void putString(NSMutableData *d, const char *s, BOOL last) {
  size_t n = strlen(s); putHeader(d, (uint32_t)n, 0x09 | (last ? 0x80 : 0)); [d appendBytes:s length:n]; pad4(d);
}
static void putDouble(NSMutableData *d, double v, BOOL last) {
  putHeader(d, 0x3f, 0x04 | (last ? 0x80 : 0)); [d appendBytes:&v length:8];
}
static NSData *hingePayload(double degrees) {
  NSMutableData *d = [NSMutableData data];
  uint8_t magic[4] = { 0xd3, 0, 0, 0 }; [d appendBytes:magic length:4];
  putHeader(d, 4, 0x81);
  putKey(d, "provider"); putString(d, "com.apple.Virtualization.VirtualMachines", NO);
  putKey(d, "source");   putString(d, "hinge-slider-control", NO);
  putKey(d, "type");     putString(d, "range", NO);
  putKey(d, "value");    putDouble(d, degrees, YES);
  return d;
}
static NSData *orientationPayload(const char *value) {
  NSMutableData *d = [NSMutableData data];
  uint8_t magic[4] = { 0xd3, 0, 0, 0 }; [d appendBytes:magic length:4];
  putHeader(d, 4, 0x81);
  putKey(d, "provider"); putString(d, "com.apple.Virtualization.VirtualMachines", NO);
  putKey(d, "source");   putString(d, "orientation-picker-control", NO);
  putKey(d, "type");     putString(d, "enum", NO);
  putKey(d, "value");    putString(d, value, YES);
  return d;
}

// --- the virtual service's delegate -------------------------------------
@interface ServiceDelegate : NSObject
@property (nonatomic, strong) NSDictionary *properties;
@end
@implementation ServiceDelegate
- (id)propertyForKey:(NSString *)key forService:(id)service {
  id v = self.properties[key];
  return v;
}
- (BOOL)setProperty:(id)value forKey:(NSString *)key forService:(id)service {
  return YES;
}
- (id)copyEventMatching:(NSDictionary *)matching forService:(id)service { return nil; }
- (BOOL)setOutputEvent:(id)event forService:(id)service { return YES; }
- (void)notification:(uint32_t)type withProperty:(NSDictionary *)prop forService:(id)service {
}
@end

int main(int argc, char **argv) {
  @autoreleasepool {
    if (argc < 2) { fprintf(stderr, "usage: HingeControl angle <deg> | sweep <from> <to> <ms> | orientation <portrait|landscapeLeft|landscapeRight|portraitUpsideDown>\n"); return 2; }
    dlopen("/System/Library/PrivateFrameworks/HID.framework/HID", RTLD_NOW);
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
    IOHIDEventCreateVendorDefinedEvent = dlsym(iokit, "IOHIDEventCreateVendorDefinedEvent");
    if (!IOHIDEventCreateVendorDefinedEvent) { fprintf(stderr, "no IOHIDEventCreateVendorDefinedEvent\n"); return 1; }
    Class S = NSClassFromString(@"HIDVirtualEventService");
    id service = [[S alloc] init];
    ServiceDelegate *delegate = [ServiceDelegate new];
    delegate.properties = @{
      @"PrimaryUsagePage": @0xFF61, @"PrimaryUsage": @0x5B,
      @"DeviceUsagePairs": @[@{@"DeviceUsagePage": @0xFF61, @"DeviceUsage": @0x5B}],
      @"Transport": @"CoreDevice", @"Product": @"baguette HingeControl",
      @"VendorID": @0, @"ProductID": @0, @"VersionNumber": @0, @"ReportInterval": @8000,
    };
    ((void (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("setDelegate:"), delegate);
    dispatch_queue_t q = dispatch_queue_create("HingeControl", DISPATCH_QUEUE_SERIAL);
    ((void (*)(id, SEL, id))objc_msgSend)(service, sel_registerName("setDispatchQueue:"), q);
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("activate"));
    uint64_t sid = ((uint64_t (*)(id, SEL))objc_msgSend)(service, sel_registerName("serviceID"));
    if (!sid) { fprintf(stderr, "HID service did not activate\n"); return 1; }
    usleep(300 * 1000);   // let the event system enumerate it

    BOOL (*dispatch)(id, SEL, id) = (BOOL (*)(id, SEL, id))objc_msgSend;
    void (^send)(NSData *) = ^(NSData *payload) {
      IOHIDEventRef ev = IOHIDEventCreateVendorDefinedEvent(kCFAllocatorDefault, mach_absolute_time(), 0xFF61, 0x5B, 0,
        (uint8_t *)payload.bytes, payload.length, 0);
      BOOL ok = dispatch(service, sel_registerName("dispatchEvent:"), (__bridge id)ev);
      if (!ok) fprintf(stderr, "dispatch failed\n");
      CFRelease(ev);
    };
    // One command: `angle D`, `sweep F T MS` or `orientation NAME`.
    // Returns NO for a line it does not understand.
    BOOL (^perform)(NSArray<NSString *> *) = ^BOOL(NSArray<NSString *> *words) {
      NSString *verb = words.firstObject ?: @"";
      if ([verb isEqualToString:@"angle"] && words.count >= 2) {
        send(hingePayload(words[1].doubleValue));
      } else if ([verb isEqualToString:@"sweep"] && words.count >= 4) {
        double from = words[1].doubleValue, to = words[2].doubleValue, ms = words[3].doubleValue;
        int frames = (int)(ms / 16.667); if (frames < 1) frames = 1;
        for (int i = 1; i <= frames; i++) {
          double p = (double)i / frames, e = 1 - pow(1 - p, 3);
          send(hingePayload(from + (to - from) * e));
          usleep(16667);
        }
      } else if ([verb isEqualToString:@"orientation"] && words.count >= 2) {
        send(orientationPayload(words[1].UTF8String));
      } else {
        return NO;
      }
      return YES;
    };
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (int i = 1; i < argc; i++) [words addObject:[NSString stringWithUTF8String:argv[i]]];
    if ([words.firstObject isEqualToString:@"serve"]) {
      // Commands line by line until stdin closes — the owner's exit.
      char *line = NULL; size_t cap = 0; ssize_t n;
      while ((n = getline(&line, &cap, stdin)) > 0) {
        NSString *text = [[NSString stringWithUTF8String:line]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSArray<NSString *> *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (text.length && !perform(parts)) fprintf(stderr, "bad line: %s\n", text.UTF8String);
      }
      free(line);
    } else if (!perform(words)) {
      fprintf(stderr, "bad arguments\n"); return 2;
    }
    usleep(300 * 1000);
    ((void (*)(id, SEL))objc_msgSend)(service, sel_registerName("cancel"));
    usleep(100 * 1000);
  }
  return 0;
}
