//
//  HIDTemperatureReader.m
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

#import "HIDTemperatureReader.h"
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>

typedef NS_ENUM(int64_t, MRHIDPage) {
    MRHIDPageAppleVendor = 0xFF00
};

typedef NS_ENUM(int64_t, MRHIDUsageAppleVendor) {
    MRHIDUsageAppleVendorTemperatureSensor = 0x05
};

typedef NS_ENUM(int64_t, MRHIDEvent) {
    MRHIDEventTypeTemperature = 0x0F
};

#define MRHIDEventFieldBase(type) (type << 16)

typedef NS_ENUM(int64_t, MRHIDEventField) {
    MRHIDEventFieldTemperatureLevel = MRHIDEventFieldBase(MRHIDEventTypeTemperature)
};

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFTypeRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t eventType, int64_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(CFTypeRef event, int64_t field);

@implementation HIDTemperatureSensorReading

- (instancetype)initWithName:(NSString *)name temperature:(double)temperature
{
    self = [super init];

    if(self)
    {
        _name        = [name copy];
        _temperature = temperature;
    }

    return self;
}

@end

@interface HIDTemperatureReader()

@property(nonatomic, assign, nullable) IOHIDEventSystemClientRef client;

@end

@implementation HIDTemperatureReader

- (instancetype)init
{
    self = [super init];

    if(self)
    {
        self.client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    }

    return self;
}

- (void)dealloc
{
    if(self.client != NULL)
    {
        CFRelease(self.client);
    }
}

- (NSArray<HIDTemperatureSensorReading *> *)readTemperatureSensors
{
    if(self.client == NULL)
    {
        return @[];
    }

    NSDictionary *filter =
    @{
        @"PrimaryUsagePage": @(MRHIDPageAppleVendor),
        @"PrimaryUsage": @(MRHIDUsageAppleVendorTemperatureSensor)
    };

    IOHIDEventSystemClientSetMatching(self.client, (__bridge CFDictionaryRef)filter);

    NSArray *services = CFBridgingRelease(IOHIDEventSystemClientCopyServices(self.client));
    NSMutableDictionary<NSString *, HIDTemperatureSensorReading *> *values = [NSMutableDictionary new];

    for(id object in services)
    {
        IOHIDServiceClientRef service = (__bridge IOHIDServiceClientRef)object;
        NSString *name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        CFTypeRef event = IOHIDServiceClientCopyEvent(service, MRHIDEventTypeTemperature, 0, 0);

        if(name == nil)
        {
            NSNumber *locationID = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("LocationID")));

            if([locationID isKindOfClass:[NSNumber class]])
            {
                name = [NSString stringWithFormat:@"Unknown-HID-%llX", locationID.unsignedLongLongValue];
            }
        }

        if(name != nil && event != NULL)
        {
            double temperature = IOHIDEventGetFloatValue(event, MRHIDEventFieldTemperatureLevel);

            if(temperature > -40 && temperature < 130)
            {
                values[name] = [[HIDTemperatureSensorReading alloc] initWithName:name temperature:temperature];
            }
        }

        if(event != NULL)
        {
            CFRelease(event);
        }
    }

    return values.allValues;
}

@end
