//
//  ViewController.m
//  VideoDemo
//
//  Created by ByteDance on 2023/11/29.
//

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import "ViewController.h"
#import "VideoCoder.h"



@interface ViewController () <VideoCoderDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVAsset *asset;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UIImageView *playIcon;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, strong) NSTimer *progressTimer;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) VideoCoder *coder;
@property (nonatomic, copy) NSString *outputPath;
@property (nonatomic, strong) UIButton *renderBtn;

@end

@implementation ViewController 

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.renderBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.renderBtn.frame = CGRectMake(SCREENWIDTH/2-40, 400, 80, 40);
    [self.renderBtn setTitle:@"开始渲染" forState:UIControlStateNormal];
    [self.renderBtn addTarget:self action:@selector(startRender) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.renderBtn];
}

- (void)startRender {
    NSString *videoPath = [[NSBundle mainBundle] pathForResource:@"MLBB_Hanabi" ofType:@"mp4"];
    
    NSArray *documentDirectories = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [documentDirectories firstObject];
    self.outputPath = [documentsDirectory stringByAppendingPathComponent:@"MLBB_Hanabi_Mirror.mp4"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.outputPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.outputPath error:nil];
    }
    
    self.asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:videoPath]];
    self.coder = [[VideoCoder alloc] initWithAsset:self.asset];
    self.coder.delegate = self;
    
    [self.coder transcode:self.outputPath];
}

- (void)customInit {
    NSURL *url = [NSURL fileURLWithPath:self.outputPath];
    NSDictionary *fileDic = [[[NSFileManager alloc] init] attributesOfItemAtPath:self.outputPath error:nil];
    if ([fileDic[NSFileSize] longLongValue] < 1000) {
        url = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"MLBB_Hanabi" ofType:@"mp4"]];
    }
    self.player = [AVPlayer playerWithURL:url];
    
    // 播放器
    NSArray *tracks = [self.asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
    CGFloat width = videoTrack.naturalSize.width;
    CGFloat height = videoTrack.naturalSize.height;
    CGFloat ratio = height / width;
    
    self.playerLayer = [AVPlayerLayer new];
    self.playerLayer.frame = CGRectMake(0, STATUSBARHEIGHT, SCREENWIDTH, SCREENWIDTH * ratio);
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    
    [self.view.layer addSublayer:self.playerLayer];
    [self.playerLayer setPlayer:self.player];
    
    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(SCREENWIDTH-70, self.playerLayer.frame.size.height+65, 70, 30)];
    [self updateProgress];
    self.timeLabel.font = [UIFont systemFontOfSize:10];
    [self.view addSubview:self.timeLabel];
    
    // 播放按钮
    self.playIcon = [UIImageView new];
    self.playIcon.frame = CGRectMake(10, self.playerLayer.frame.size.height+65, 30, 30);
    self.playIcon.image = [UIImage imageNamed:@"play.png"];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(playOrPause)];
    [self.playIcon addGestureRecognizer:tap];
    self.playIcon.userInteractionEnabled = YES;
    [self.view addSubview:self.playIcon];
    
    // 进度
    self.progressSlider = [UISlider new];
    self.progressSlider.frame = CGRectMake(50, self.playIcon.frame.origin.y + 10, SCREENWIDTH - 130, 10);
    self.progressSlider.maximumTrackTintColor = [UIColor grayColor];
    self.progressSlider.minimumTrackTintColor = [UIColor darkGrayColor];
    [self.progressSlider setThumbImage:[UIImage imageNamed:@"point"] forState:UIControlStateNormal];
    [self.progressSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(sliderTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.progressSlider];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFinished:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFinished:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:self.player.currentItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFinished:) name:AVPlayerItemPlaybackStalledNotification object:self.player.currentItem];
}

- (void)playbackFinished:(NSNotification *)notification {
    if (self.player) {
        [self playOrPause];
    }
}

- (void)playOrPause {
    NSLog(@"播放或者暂停");
    if (self.player.rate == 0) {
        [self.player play];
        [self addProgressTimer];
        self.playIcon.image = [UIImage imageNamed:@"pause.png"];
    } else {
        [self.player pause];
        [self removeProgressTimer];
        self.playIcon.image = [UIImage imageNamed:@"play.png"];
    }
}


// 用户拖拽进度条时，系统调用，此时关闭NSTimer
- (void)sliderValueChanged:(UISlider *)slider {
    double progress = self.progressSlider.value;
    CMTime duration = self.player.currentItem.duration;
    CMTime seekTime = CMTimeMakeWithSeconds(CMTimeGetSeconds(duration) * progress, NSEC_PER_SEC);
    
    self.timeLabel.text = [NSString stringWithFormat:@"%@/%@", GMRDTimeMMssStr(CMTimeGetSeconds(seekTime)), GMRDTimeMMssStr(CMTimeGetSeconds(duration))];
    
    [self.player seekToTime:seekTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

// 播放过程中，NSTimer调用
- (void)updateProgress {
    CMTime currentTime = self.player.currentTime;
    CMTime duration = self.player.currentItem.duration;
    CGFloat progress = CMTimeGetSeconds(currentTime) / CMTimeGetSeconds(duration);
    
    self.timeLabel.text = [NSString stringWithFormat:@"%@/%@", GMRDTimeMMssStr(CMTimeGetSeconds(currentTime)), GMRDTimeMMssStr(CMTimeGetSeconds(duration))];
    self.progressSlider.value = progress;
}

- (void)addProgressTimer {
    self.progressTimer = [NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(updateProgress) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.progressTimer forMode:NSRunLoopCommonModes];
}

- (void)removeProgressTimer {
    [self.progressTimer invalidate];
    self.progressTimer = nil;
}


- (void)sliderTouchDown:(UISlider *)slider {
    // 当滑块被按下时触发的事件
    [self.player pause];
    [self removeProgressTimer];
    NSLog(@"Slider touch down");
}


- (void)sliderTouchUpInside:(UISlider *)slider {
    // 当滑块被释放时触发的事件
    [self.player play];
    [self addProgressTimer];
    NSLog(@"Slider touch up inside");
}


- (void)videoCoder:(nonnull VideoCoder *)coder didFinishRender:(nonnull NSString *)msg { 
    [self customInit];
}


@end
