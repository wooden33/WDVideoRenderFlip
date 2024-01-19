//
//  VideoTransform.h
//  VideoDemo
//
//  Created by ByteDance on 2023/12/22.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

#define VDWeak(object) __weak __typeof__(object) weak##_##object = object;
#define VDStrong(object) __strong __typeof__(object) object = weak##_##object;

@class VideoCoder;
@protocol VideoCoderDelegate<NSObject>

- (void)videoCoder:(VideoCoder *)coder didFinishRender:(NSString *)msg;

@end

@interface VideoCoder : NSObject

@property (nonatomic, weak) id<VideoCoderDelegate>delegate;

- (instancetype)initWithAsset:(AVAsset *)asset;

- (void)transcode:(NSString *)outputPath;

@end

NS_ASSUME_NONNULL_END
