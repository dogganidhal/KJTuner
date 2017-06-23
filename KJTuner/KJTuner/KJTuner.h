//
//  KJTuner.h
//  KJTuner
//
//  Created by Nidhal on 23.05.17.
//  Copyright © 2017 Appsolute GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol KJTunerDelegate;

@interface KJTunerOutput : NSObject

@property (nonatomic) NSInteger octave;
@property (nonatomic) NSInteger midiNoteNr;
@property (nonatomic) double distance;
@property (nonatomic) double amplitude;
@property (nonatomic) double frequency;

@end

@interface KJTuner : NSObject

@property (nonatomic) NSTimeInterval updateInterval;
@property (nonatomic) NSInteger smoothingBufferCount;
@property (nonatomic, unsafe_unretained) id<KJTunerDelegate> delegate;
@property (nonatomic) double threshold;
@property (nonatomic) double smoothing;
@property (nonatomic) NSInteger minDetectedNoteNrs;
@property (nonatomic) NSTimeInterval minimumTimeInterval;



- (instancetype)initWithThreshold:(double)threshold smoothing:(double)smoothing;
- (void) start;
- (void) stop;


@end

@protocol KJTunerDelegate <NSObject>

- (void) tunerDidUpdate:(KJTuner*)tuner withOutput:(KJTunerOutput*)output;
- (void) tuner:(KJTuner*)tuner processWithAmplitude:(double)amplitude isGreaterThenThreshold:(BOOL)flag;

@end
