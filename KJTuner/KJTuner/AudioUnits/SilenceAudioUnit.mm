//
//  SilenceAudioUnit.m
//  KJTuner
//
//  Created by Nidhal on 30.05.17.
//  Copyright © 2017 appsolute GmbH. All rights reserved.
//

#import "SilenceAudioUnit.h"
#import "BoosterDSPKernel.hpp"
#import "BufferedAudioBus.hpp"

@interface AUParameter(Ext)
-(instancetype)init:(NSString *)identifier
               name:(NSString *)name
            address:(AUParameterAddress)address
                min:(AUValue)min
                max:(AUValue)max
               unit:(AudioUnitParameterUnit)unit;

+(instancetype)parameter:(NSString *)identifier
                    name:(NSString *)name
                 address:(AUParameterAddress)address
                     min:(AUValue)min
                     max:(AUValue)max
                    unit:(AudioUnitParameterUnit)unit;

+(instancetype)frequency:(NSString *)identifier
                    name:(NSString *)name
                 address:(AUParameterAddress)address;

@end

@interface AUParameterTree(Ext)
+(instancetype)tree:(NSArray<AUParameterNode *> *)children;
@end

@interface AVAudioNode(Ext)
-(instancetype)initWithComponent:(AudioComponentDescription)component;
@end


@implementation SilenceAudioUnit {
    AUAudioUnitBusArray *_outputBusArray;
    BoosterDSPKernel _kernel;
    BufferedInputBus _inputBus;
}

@synthesize parameterTree = _parameterTree;
@synthesize rampTime = _rampTime;

- (void)setGain:(float)gain {
    _kernel.setGain(gain);
}

- (void)start {
    _kernel.start();
}

- (void)stop {
    _kernel.stop();
}

- (BOOL)isPlaying {
    return _kernel.started;
}

- (BOOL)isSetUp {
    return _kernel.resetted;
}


-(double)rampTime {
    return _rampTime;
}

-(void)setRampTime:(double)rampTime {
    if (_rampTime == rampTime) { return; }
    _rampTime = rampTime;
    [self setUpParameterRamp];
}

- (void)createParameters {
    self.rampTime = 0.0002;
    self.defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100
                                                                        channels:2];
    _kernel.init(self.defaultFormat.channelCount, self.defaultFormat.sampleRate);
    _inputBus.init(self.defaultFormat, 8);
    self.inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                                busType:AUAudioUnitBusTypeInput
                                                                 busses:@[_inputBus.bus]];
    // Create a parameter object for the gain.
    AUParameter *gainAUParameter = [AUParameter parameter:@"gain"
                                                     name:@"Boosting amount."
                                                  address:gainAddress
                                                      min:0
                                                      max:1
                                                     unit:kAudioUnitParameterUnit_Generic];
    
    // Initialize the parameter values.
    gainAUParameter.value = 0;
    
    _kernel.setParameter(gainAddress, gainAUParameter.value);
    
    // Create the parameter tree.
    _parameterTree = [AUParameterTree tree:@[
                                             gainAUParameter
                                             ]];
    
    __block BoosterDSPKernel *blockKernel = &_kernel;
    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        blockKernel->setParameter(param.address, value);
    };
    self.parameterTree.implementorValueProvider = ^(AUParameter *param) {
        return blockKernel->getParameter(param.address); 
    };
    
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    
    if (self == nil) {
        return nil;
    }
    
    // Initialize a default format for the busses.
    self.defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100
                                                                        channels:2];
    
    [self createParameters];
    
    // Create the output busses.
    self.outputBus = [[AUAudioUnitBus alloc] initWithFormat:self.defaultFormat error:nil];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                             busType:AUAudioUnitBusTypeOutput
                                                              busses: @[self.outputBus]];
    
    self.maximumFramesToRender = 512;
    
    return self;
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    [self setUpParameterRamp];
    if (self.outputBus.format.channelCount != _inputBus.bus.format.channelCount) {
        if (outError) {
            *outError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                            code:kAudioUnitErr_FailedInitialization
                                        userInfo:nil];
        }
        self.renderResourcesAllocated = NO;
        return NO;
    }
    _inputBus.allocateRenderResources(self.maximumFramesToRender);
    _kernel.init(self.outputBus.format.channelCount, self.outputBus.format.sampleRate);
    _kernel.reset();
    return YES;
}

- (void)deallocateRenderResources {
    [super deallocateRenderResources];
    _kernel.destroy();
    _inputBus.deallocateRenderResources();
}

- (AUInternalRenderBlock)internalRenderBlock {
    __block BoosterDSPKernel *state = &_kernel;
    __block BufferedInputBus *input = &_inputBus;
    return ^AUAudioUnitStatus(
                              AudioUnitRenderActionFlags *actionFlags,
                              const AudioTimeStamp       *timestamp,
                              AVAudioFrameCount           frameCount,
                              NSInteger                   outputBusNumber,
                              AudioBufferList            *outputData,
                              const AURenderEvent        *realtimeEventListHead,
                              AURenderPullInputBlock      pullInputBlock) {
        AudioUnitRenderActionFlags pullFlags = 0;
        AUAudioUnitStatus err = input->pullInput(&pullFlags, timestamp, frameCount, 0, pullInputBlock);
        if (err != 0) {
            return err;
        }
        AudioBufferList *inAudioBufferList = input->mutableAudioBufferList;
        AudioBufferList *outAudioBufferList = outputData;
        if (outAudioBufferList->mBuffers[0].mData == nullptr) {
            for (UInt32 i = 0; i < outAudioBufferList->mNumberBuffers; ++i) {
                outAudioBufferList->mBuffers[i].mData = inAudioBufferList->mBuffers[i].mData;
            }
        }
        state->setBuffers(inAudioBufferList, outAudioBufferList);
        state->processWithEvents(timestamp, frameCount, realtimeEventListHead);
        return noErr;
    };
}

#pragma mark - AUAudioUnit Overrides

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}
- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

-(AUImplementorValueProvider)getter {
    return _parameterTree.implementorValueProvider;
}

-(AUImplementorValueObserver)setter {
    return _parameterTree.implementorValueObserver;
}

#pragma mark - AUAudioUnit Overrides

- (void)setUpParameterRamp {
    /*
     While rendering, we want to schedule all parameter changes. Setting them
     off the render thread is not thread safe.
     */
    __block AUScheduleParameterBlock scheduleParameter = self.scheduleParameterBlock;
    
    // Ramp over rampTime in seconds.
    __block AUAudioFrameCount rampTime = AUAudioFrameCount(_rampTime * self.outputBus.format.sampleRate);
    
    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        scheduleParameter(AUEventSampleTimeImmediate, rampTime, param.address, value);
    };
}

@end

//
// Not currently achievable in Swift because you cannot set self in a class constructor
//

@implementation AUParameter(Ext)

-(instancetype)init:(NSString *)identifier
               name:(NSString *)name
            address:(AUParameterAddress)address
                min:(AUValue)min
                max:(AUValue)max
               unit:(AudioUnitParameterUnit)unit {
    
    return self = [AUParameterTree createParameterWithIdentifier:identifier
                                                            name:name
                                                         address:address
                                                             min:min
                                                             max:max
                                                            unit:unit
                                                        unitName:nil
                                                           flags:0
                                                    valueStrings:nil
                                             dependentParameters:nil];
}

+(instancetype)parameter:(NSString *)identifier
                    name:(NSString *)name
                 address:(AUParameterAddress)address
                     min:(AUValue)min
                     max:(AUValue)max
                    unit:(AudioUnitParameterUnit)unit {
    return [[AUParameter alloc] init:identifier
                                name:name
                             address:address
                                 min:min
                                 max:max
                                unit:unit];
}

+(instancetype)frequency:(NSString *)identifier
                    name:(NSString *)name
                 address:(AUParameterAddress)address {
    return [AUParameter parameter:identifier
                             name:name
                          address:address
                              min:20
                              max:22050
                             unit:kAudioUnitParameterUnit_Hertz];
}
@end

@implementation AUParameterTree(Ext)

+(instancetype)tree:(NSArray<AUParameterNode *> *)children {
    AUParameterTree* tree = [AUParameterTree createTreeWithChildren:children];
    if (tree == nil) {
        return nil;
    }
    
    tree.implementorStringFromValueCallback = ^(AUParameter *param, const AUValue *__nullable valuePtr) {
        AUValue value = valuePtr == nil ? param.value : *valuePtr;
        return [NSString stringWithFormat:@"%.3f", value];
        
    };
    return tree;
    
}
@end



@implementation AVAudioNode(Ext)
-(instancetype)initWithComponent:(AudioComponentDescription)component {
    self = [self init];
    __block AVAudioNode * __strong * _this = &self;
    
    [AVAudioUnit instantiateWithComponentDescription:component
                                             options:0
                                   completionHandler:^(__kindof AVAudioUnit * _Nullable audioUnit,
                                                       NSError * _Nullable error) {
                                       
                                       *_this = audioUnit;
                                   }];
    return self;
}


@end
