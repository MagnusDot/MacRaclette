//
//  HIDTemperatureReader.h
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HIDTemperatureSensorReading: NSObject

@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) double temperature;

- (instancetype)initWithName:(NSString *)name temperature:(double)temperature;

@end

@interface HIDTemperatureReader: NSObject

- (NSArray<HIDTemperatureSensorReading *> *)readTemperatureSensors;

@end

NS_ASSUME_NONNULL_END
