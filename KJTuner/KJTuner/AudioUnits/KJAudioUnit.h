//
//  KJAudioUnit.h
//  AudioUnitsTraining
//
//  Created by Nidhal on 29.05.17.
//  Copyright © 2017 Appsolute GmbH. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@protocol KJKernelUnit
-(AUImplementorValueProvider _Nullable )getter;
-(AUImplementorValueObserver _Nullable )setter;
@end

@interface KJAudioUnit : AUAudioUnit

@property AUAudioUnitBus * _Nullable outputBus;
@property AUAudioUnitBusArray * _Nullable inputBusArray;
@property AVAudioFormat * _Nullable defaultFormat;

@property double rampTime;
@property (readonly) float amplitude;
@property (readonly) float frequency;

- (void)start;
- (void)stop;
- (BOOL)isStarted;

- (instancetype _Nullable )initFromAVAudioUnit:(AVAudioUnit *_Nullable)avAudioUnit error:(NSError * _Nullable __autoreleasing *_Nullable)outError;
-(AUImplementorValueProvider _Nullable )getter;
-(AUImplementorValueObserver _Nullable )setter;

@end

@interface AUParameter(Ext)
-(instancetype _Nullable )init:(NSString *_Nullable)identifier
               name:(NSString *_Nullable)name
            address:(AUParameterAddress)address
                min:(AUValue)min
                max:(AUValue)max
               unit:(AudioUnitParameterUnit)unit;

+(instancetype _Nullable )parameter:(NSString *_Nullable)identifier
                    name:(NSString *_Nullable)name
                 address:(AUParameterAddress)address
                     min:(AUValue)min
                     max:(AUValue)max
                    unit:(AudioUnitParameterUnit)unit;

+(instancetype _Nullable )frequency:(NSString *_Nullable)identifier
                    name:(NSString *_Nullable)name
                 address:(AUParameterAddress)address;

@end

@interface AUParameterTree(Ext)
+(instancetype _Nullable )tree:(NSArray<AUParameterNode *> *_Nullable)children;
@end

@interface AVAudioNode(Ext)
-(instancetype _Nullable )initWithComponent:(AudioComponentDescription)component;
@end


