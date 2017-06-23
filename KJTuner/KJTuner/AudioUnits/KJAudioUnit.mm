//
//  KJAudioUnit.m
//  AudioUnitsTraining
//
//  Created by Nidhal on 29.05.17.
//  Copyright © 2017 Appsolute GmbH. All rights reserved.
//

#import "KJAudioUnit.h"
#import "FrequencyTrackerDSPKernel.hpp"
#import "BufferedAudioBus.hpp"

@implementation KJAudioUnit {
    AUAudioUnitBusArray *_outputBusArray;
    FrequencyTrackerDSPKernel _kernel;
    BufferedInputBus _inputBus;
}

@synthesize rampTime = _rampTime;
@synthesize parameterTree = _parameterTree;

- (void)start {
    _kernel.start();
}

- (void)stop {
    _kernel.stop();
}

- (BOOL)isStarted {
    return _kernel.started;
}


- (float)frequency {
    return _kernel.trackedFrequency * 2.0; // stereo hack
}

- (float)amplitude {
    return _kernel.trackedAmplitude / 2.0; // stereo hack
}


- (double)rampTime {
    return _rampTime;
}

- (void)setRampTime:(double)rampTime {
    if (_rampTime == rampTime) { return; }
    _rampTime = rampTime;
    [self setUpParameterRamp];
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription error:(NSError * _Nullable __autoreleasing *)outError {
    self = [super initWithComponentDescription:componentDescription error:outError];
    if (self) {
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
    }
    return self;
}

- (instancetype)initFromAVAudioUnit:(AVAudioUnit *)avAudioUnit error:(NSError * _Nullable __autoreleasing *)outError {
    self = [self initWithComponentDescription:avAudioUnit.audioComponentDescription error:outError];
    return self;
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
    _parameterTree = [AUParameterTree createTreeWithChildren:@[]];
    
    __block FrequencyTrackerDSPKernel *blockKernel = &_kernel;
    self.parameterTree.implementorValueObserver = ^(AUParameter *param, AUValue value) {
        blockKernel->setParameter(param.address, value);
    };
    self.parameterTree.implementorValueProvider = ^(AUParameter *param) {
        return blockKernel->getParameter(param.address);
    };
}

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
    __block FrequencyTrackerDSPKernel *state = &_kernel;
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

@end


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



