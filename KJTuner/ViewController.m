//
//  ViewController.m
//  KJTuner
//
//  Created by Holger Meyer on 15.05.17.
//  Copyright © 2017 appsolute GmbH. All rights reserved.
//

#import "ViewController.h"
#import "KJTuner.h"

@interface ViewController ()<KJTunerDelegate>

@property (strong, nonatomic) IBOutlet UITextField *midiNoteNrTextField;
@property (strong, nonatomic) IBOutlet UITextField *amplitudeTextField;
@property (strong, nonatomic) IBOutlet UIImageView *thresholdLED;

@property (nonatomic,strong) KJTuner *tuner;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _tuner = [[KJTuner alloc] initWithThreshold:0.1 smoothing:0.25];
   _tuner.delegate = self;
    [_tuner start];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - KJTuner Delegate -

- (void) tunerDidUpdate:(KJTuner*)tuner withOutput:(KJTunerOutput*)output {
    if (output.amplitude < 0.01) {
        return;
    }
    
    _midiNoteNrTextField.text = [NSString stringWithFormat:@"%ld",(long)output.midiNoteNr];
    
    NSLog(@"NoteNr:%ld",(long)output.midiNoteNr);
    
}

- (void) tuner:(KJTuner*)tuner processWithAmplitude:(double)amplitude isGreaterThenThreshold:(BOOL)flag
{
    _amplitudeTextField.text = [NSString stringWithFormat:@"%.4f",amplitude];
   if (amplitude >= 0.01) {
        if (flag) {
            self.thresholdLED.image = [UIImage imageNamed:@"ledRed"];
            
        } else {
            self.thresholdLED.image = [UIImage imageNamed:@"ledOff"];
        }
    } else {
        self.thresholdLED.image = [UIImage imageNamed:@"ledOff"];
    }
}


@end
