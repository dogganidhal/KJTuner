//
//  KJTuner.m
//  KJTuner
//
//  Created by Nidhal on 23.05.17.
//  Copyright © 2017 Appsolute GmbH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "KJTuner.h"
#import "KJAudioUnit.h"
#import "SilenceAudioUnit.h"

static double __frequencies[108] = {
    16.35, 17.32, 18.35, 19.45, 20.60, 21.83, 23.12, 24.50, 25.96, 27.50, 29.14, 30.87, // 0
    32.70, 34.65, 36.71, 38.89, 41.20, 43.65, 46.25, 49.00, 51.91, 55.00, 58.27, 61.74, // 1
    65.41, 69.30, 73.42, 77.78, 82.41, 87.31, 92.50, 98.00, 103.8, 110.0, 116.5, 123.5, // 2
    130.8, 138.6, 146.8, 155.6, 164.8, 174.6, 185.0, 196.0, 207.7, 220.0, 233.1, 246.9, // 3
    261.6, 277.2, 293.7, 311.1, 329.6, 349.2, 370.0, 392.0, 415.3, 440.0, 466.2, 493.9, // 4
    523.3, 554.4, 587.3, 622.3, 659.3, 698.5, 740.0, 784.0, 830.6, 880.0, 932.3, 987.8, // 5
    1047, 1109, 1175, 1245, 1319, 1397, 1480, 1568, 1661, 1760, 1865, 1976,             // 6
    2093, 2217, 2349, 2489, 2637, 2794, 2960, 3136, 3322, 3520, 3729, 3951,             // 7
    4186, 4435, 4699, 4978, 5274, 5588, 5920, 6272, 6645, 7040, 7459, 7902              // 8
};

@implementation KJTunerOutput

- (instancetype)init {
    self = [super init];
    if (self) {
        _octave = 0;
        _midiNoteNr = 0;
        _distance = 0.0;
        _amplitude = 0.0;
        _frequency = 0.0;
    }
    return self;
}
@end

@interface KJTuner()

@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioSession *session;
@property (nonatomic, strong) AVAudioMixerNode *microphone;
@property (nonatomic, strong) AVAudioFormat *defaultFormat;

@property (nonatomic,strong) NSTimer *timer;
@property (nonatomic,strong) NSMutableArray *smoothingBuffer;
@property (nonatomic,strong) NSMutableArray *lastNotNrs;

@property (nonatomic) NSInteger lastDetectedNoteNr;
@property (nonatomic) BOOL isRunning;
@property (nonatomic) NSTimeInterval lastDetectedTimeInterval;

@end

@implementation KJTuner {
    KJAudioUnit *_kjAudioUnit;
    __block AVAudioUnit *_tracker;
    __block AVAudioUnit *_booster;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _updateInterval = 0.03;
        _smoothingBufferCount = 30;
        _threshold = 0;
        _smoothing = 0.25;
        _lastNotNrs=[NSMutableArray new];
        _minDetectedNoteNrs = 8;
        _minimumTimeInterval = 0.4;
        _defaultFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:2];
        [self setupAudioUnit];
#if TARGET_OS_IPHONE
        [self setupAudioSession];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationWillEnterForegroundNotification object:nil];
#endif
    }
    return self;
}

#pragma mark - Setup the AudioSession

- (void)setupAudioSession {
    NSError *sessionError;
    _session = [AVAudioSession sharedInstance];
    assert([_session setCategory:AVAudioSessionCategoryPlayAndRecord error:&sessionError]);
    assert([_session setMode:AVAudioSessionModeMeasurement error:&sessionError]);
    assert([_session setPreferredSampleRate:44100 error:&sessionError]);
    assert([_session setPreferredIOBufferDuration:0.01 error:&sessionError]);
    [_session requestRecordPermission:^(BOOL granted) {
        if (!granted) {
            NSLog(@"Record permission request has been denied");
        }
    }];
}

#pragma mark - Setup the AudioUnit

- (void)setupAudioUnit {
    // the AudioUnit's component description
    AudioComponentDescription trackerComponentDescription = {0};
    trackerComponentDescription.componentType = kAudioUnitType_Effect;
    trackerComponentDescription.componentSubType = 'ptrk';
    trackerComponentDescription.componentManufacturer = 'BeEa';
    trackerComponentDescription.componentFlags = kAudioComponentFlag_SandboxSafe;
    trackerComponentDescription.componentFlagsMask = 0;
    // Getting audio components matching out descriptions of the tracker and the booster
    [AUAudioUnit registerSubclass:KJAudioUnit.class asComponentDescription:trackerComponentDescription name:(NSString *)KJAudioUnit.class version:1];
    [AVAudioUnit instantiateWithComponentDescription:trackerComponentDescription
                                             options:kAudioComponentInstantiation_LoadOutOfProcess
                                   completionHandler:^(__kindof AVAudioUnit * _Nullable audioUnit, NSError * _Nullable error) {
                                       _tracker = audioUnit;
                                   }];
    AudioComponentDescription boosterComponentDescription = {0};
    boosterComponentDescription.componentType = kAudioUnitType_Effect;
    boosterComponentDescription.componentSubType = 'gain';
    boosterComponentDescription.componentManufacturer = 'BeEa';
    boosterComponentDescription.componentFlags = kAudioComponentFlag_SandboxSafe;
    boosterComponentDescription.componentFlagsMask = 0;
    [AUAudioUnit registerSubclass:SilenceAudioUnit.class asComponentDescription:boosterComponentDescription name:@"Local Booster" version:1];
    [AVAudioUnit instantiateWithComponentDescription:boosterComponentDescription options:kAudioComponentInstantiation_LoadOutOfProcess completionHandler:^(__kindof AVAudioUnit * _Nullable audioUnit, NSError * _Nullable error) {
        _booster = audioUnit;
    }];
    // getting data from the instanciated audio units
    _kjAudioUnit = (KJAudioUnit*)_tracker.AUAudioUnit;
    SilenceAudioUnit *kjBooster = (SilenceAudioUnit *)_booster.AUAudioUnit;
    kjBooster.gain = 0;
    // initializing inputNode & thr audio engine
    _microphone = [[AVAudioMixerNode alloc] init];
    _engine = [[AVAudioEngine alloc] init];
    // attaching to the engine and connecting the nodes
    // NB: the nodes cycle is very simple :
    // engine's inputNode --> microphone --> tracker (KJAudioUnit) --> booster (SilenceAudioUnit) --> engine's outputNode
    [_engine attachNode:_microphone];
    [_engine attachNode:_tracker];
    [_engine attachNode:_booster];
    [_engine connect:_engine.inputNode to: _microphone format:_defaultFormat];
    [_engine connect:_microphone to:_tracker format:_defaultFormat];
    [_engine connect:_tracker to:_booster format:_defaultFormat];
    [_engine connect:_booster to:_engine.outputNode format:_defaultFormat];
}

#pragma mark - prepare and start the audio engine

- (void)startTheAudioEngine {
    [_engine prepare];
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(restartEngineAfterRouteChange:)
                                                 name:@"io.audiokit.enginerestartedafterroutechange" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioEngineConfigurationChange:)
                                                 name:AVAudioEngineConfigurationChangeNotification
                                               object:_engine];
#endif
    NSError *startingError = nil;
    assert([_engine startAndReturnError:&startingError]);
}

- (void) didEnterBackground:(NSNotification*)notification {
    [_timer invalidate];
}

- (void) didBecomeActive:(NSNotification*)notification {
    if (_isRunning)
    {
        [self startTimer];
    }
}

- (void) startTimer {
    [_timer invalidate];
    _timer = [NSTimer scheduledTimerWithTimeInterval:_updateInterval target:self selector:@selector(handleTimer) userInfo:nil repeats:YES];
}

- (instancetype)initWithThreshold:(double)threshold smoothing:(double)smoothing {
    self = [self init];
    if (self) {
        _threshold = MIN(fabs(threshold), 1.0);
        _smoothing = MIN(fabs(smoothing), 1.0);
    }
    return self;
}

- (void) start {
    if (!_isRunning) {
        [self startTheAudioEngine];
        [self startTimer];
        _isRunning = YES;
    }
}

- (void) stop {
    if (_isRunning) {
        _isRunning = NO;
        [_timer invalidate];
        [_engine stop];
#if TARGET_OS_IPHONE
        NSError *potentialError = nil;
        assert([[AVAudioSession sharedInstance] setActive:NO error:&potentialError]);
#endif
    }
}

- (NSInteger) _countForNoteNr:(NSInteger)noteNr {
    NSCountedSet *setOfObjects = [[NSCountedSet alloc] initWithArray:_lastNotNrs];
    return [setOfObjects countForObject:@(noteNr)];
}

- (void) handleTimer {
    if (_kjAudioUnit.amplitude > _threshold) {
        double amplitude = _kjAudioUnit.amplitude;
        double frequency = [self smooth:_kjAudioUnit.frequency];
        KJTunerOutput *output = [KJTuner newOutput:frequency amplitude:amplitude];
        [_lastNotNrs addObject:@(output.midiNoteNr)];
        NSInteger count = [self _countForNoteNr:output.midiNoteNr];
        if ([_delegate respondsToSelector:@selector(tuner:processWithAmplitude:isGreaterThenThreshold:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (count < _minDetectedNoteNrs) {
                    [self.delegate tuner:self processWithAmplitude:_kjAudioUnit.amplitude isGreaterThenThreshold:_kjAudioUnit.amplitude > _threshold];
                } else {
                    [self.delegate tuner:self processWithAmplitude:0 isGreaterThenThreshold:NO];
                }
            });
        }
        if ([_delegate respondsToSelector:@selector(tunerDidUpdate:withOutput:)]) {
            if (count >= _minDetectedNoteNrs && output.midiNoteNr != _lastDetectedNoteNr) {
                NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
                if ((now - _lastDetectedNoteNr) > _minimumTimeInterval) {
                    _lastDetectedNoteNr = output.midiNoteNr;
                    _lastDetectedTimeInterval = [NSDate timeIntervalSinceReferenceDate];
                    [_lastNotNrs removeAllObjects];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_delegate tunerDidUpdate:self withOutput:output];
                    });
                }
            }
        }
        
    } else {
        [_lastNotNrs removeAllObjects];
        _lastDetectedNoteNr = 0;
        if ([self.delegate respondsToSelector:@selector(tuner:processWithAmplitude:isGreaterThenThreshold:)]) {
            [self.delegate tuner:self processWithAmplitude:_kjAudioUnit.amplitude isGreaterThenThreshold:_kjAudioUnit.amplitude > _threshold];
        }
    }
}

- (double) smooth:(double)value {
    double frequency = value;
    if (_smoothingBuffer.count > 0) {
        double last = [[_smoothingBuffer lastObject] doubleValue];
        frequency = (_smoothing * value) + (1.0 - _smoothing) * last;
        if (_smoothingBuffer.count > _smoothingBufferCount) {
            [_smoothingBuffer removeObjectAtIndex:0];
        }
    }
    [_smoothingBuffer addObject:@(frequency)];
    return frequency;
}

+ (KJTunerOutput*) newOutput:(double)frequency amplitude:(double)amplitude {
    KJTunerOutput *output = [KJTunerOutput new];
    double norm = frequency;
    while (norm > __frequencies[107]) {
        norm = norm / 2.0;
    }
    while (norm < __frequencies[0]) {
        norm = norm * 2.0;
    }
    
    NSInteger i = -1;
    NSInteger min = DBL_MAX;
    
    for (NSInteger n=0; n<108; n++) {
        double diff = __frequencies[n] - norm;
        if (fabs(diff) < labs(min)) {
            min = diff;
            i = n;
        }
    }
    
    output.octave = i / 12;
    output.frequency = frequency;
    output.amplitude = amplitude;
    output.distance = frequency - __frequencies[i];
    output.midiNoteNr = ((output.octave+1) * 12) + (i % 12);
    
    return output;
}

#pragma mark - Handling the notifications sent from the device

- (void)restartEngineAfterRouteChange:(NSNotification *)notification {
    if (_isRunning) {
        NSError *startingError = nil;
        assert([_engine startAndReturnError:&startingError]);
        [[NSNotificationCenter defaultCenter] postNotificationName:@"io.audiokit.enginerestartedafterroutechange"
                                                            object:nil
                                                          userInfo:[notification userInfo]];
    }
}

- (void)audioEngineConfigurationChange:(NSNotification *)notification {
    if (_isRunning && !_engine.isRunning) {
        NSError *startingError = nil;
        assert([_engine startAndReturnError:&startingError]);
    }
}

@end





