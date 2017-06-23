//
//  SilenceAudioUnit.h
//  KJTuner
//
//  Created by Nidhal on 30.05.17.
//  Copyright © 2017 appsolute GmbH. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@protocol AKKernelUnit
-(AUImplementorValueProvider)getter;
-(AUImplementorValueObserver)setter;
@end

@interface SilenceAudioUnit : AUAudioUnit

@property AUAudioUnitBus *outputBus;
@property AUAudioUnitBusArray *inputBusArray;
@property AVAudioFormat *defaultFormat;

- (void)start;
- (void)stop;
@property double rampTime;

-(AUImplementorValueProvider)getter;
-(AUImplementorValueObserver)setter;

@property (nonatomic) float gain;

@end

