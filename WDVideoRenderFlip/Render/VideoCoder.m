//
//  VideoTransform.m
//  VideoDemo
//
//  Created by ByteDance on 2023/12/22.
//

#import "VideoCoder.h"


@interface VideoCoder()

@property (nonatomic, strong)AVAsset *asset;
@property (nonatomic, strong)AVAssetReader *reader;
@property (nonatomic, strong)AVAssetWriter *writer;
@property (nonatomic, strong)AVAssetTrack *videoTrack;
@property (nonatomic, strong)AVAssetReaderTrackOutput *videoOutput;
@property (nonatomic, strong)AVAssetWriterInput *writerInput;
@property (nonatomic, strong)AVAssetWriterInputPixelBufferAdaptor *inputAdaptor;
@property (nonatomic, strong)dispatch_queue_t queue;
// Metal相关
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> cmdQueue;
@property (nonatomic, strong) id<MTLComputePipelineState> pipelineState;
@property (nonatomic, strong) MTLTextureDescriptor *originDes;
@property (nonatomic, strong) MTLTextureDescriptor *targetDes;

@end

@implementation VideoCoder

- (nonnull instancetype)initWithAsset:(nonnull AVAsset *)asset {
    if (self = [super init]) {
        self.asset = asset;
        [self prepareReader];
        self.queue = dispatch_queue_create("videodemo.coder.demo", 0);
    }
    return self;
}

- (void)prepareReader {
    self.reader = [AVAssetReader assetReaderWithAsset:self.asset error:nil];
    
    self.videoTrack = [[self.asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];  
    NSDictionary *options = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferMetalCompatibilityKey: @YES
    };
    
    self.videoOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:self.videoTrack outputSettings:options];
    
    [self.reader addOutput:self.videoOutput];
    [self.reader startReading];
    [self setupMetal];
}

- (void)prepareWriter:(NSString *)outputPath {
    NSURL *url = [NSURL fileURLWithPath:outputPath];
    size_t width = self.videoTrack.naturalSize.width;
    size_t height = self.videoTrack.naturalSize.height;
    NSDictionary *outputSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(width),
        AVVideoHeightKey: @(height)
    };
    
    self.writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    self.writer = [[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeMPEG4 error:nil];
    if (![self.writer canAddInput:self.writerInput]) {
        NSLog(@"cannot addInput");
        return;
    }
    NSDictionary *bufferAttributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey: @(width),
        (id)kCVPixelBufferHeightKey: @(height),
    };
    [self.writer addInput:self.writerInput];
    self.inputAdaptor = [AVAssetWriterInputPixelBufferAdaptor
                         assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.writerInput sourcePixelBufferAttributes:bufferAttributes];
}

- (CVPixelBufferRef)render:(CVPixelBufferRef)buffer {
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    // 输入纹理
    id<MTLTexture> originTexture = [self.device newTextureWithDescriptor:self.originDes];
    // 输出纹理
    id<MTLTexture> targetTexture = [self.device newTextureWithDescriptor:self.targetDes];
    // pixelbuffer填充到纹理中
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *data = (unsigned char *)CVPixelBufferGetBaseAddress(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    [originTexture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:data bytesPerRow:stride];
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    
    id<MTLCommandBuffer> cmd = [self.cmdQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [cmd computeCommandEncoder];
    [encoder setTexture:originTexture atIndex:0];
    [encoder setTexture:targetTexture atIndex:1];
    [encoder setComputePipelineState:self.pipelineState];
    MTLSize threadSize = MTLSizeMake(self.pipelineState.threadExecutionWidth,
                                     self.pipelineState.maxTotalThreadsPerThreadgroup / self.pipelineState.threadExecutionWidth, 1);
    [encoder dispatchThreads:MTLSizeMake(width, height, 1) threadsPerThreadgroup:threadSize];
    [encoder endEncoding];
    [cmd commit];
    [cmd waitUntilCompleted];
    
    if (cmd.error) {
        NSLog(@"render: %@", cmd.error);
        exit(0);
    }
    
    return [self copyPixelBufferFrom:targetTexture];
}


- (void)setupMetal {
    self.device = MTLCreateSystemDefaultDevice();
    self.cmdQueue = [self.device newCommandQueue];
    id<MTLLibrary> library = [self.device newDefaultLibrary];
    id<MTLFunction> func = [library newFunctionWithName:@"flipShader"];
    self.pipelineState = [self.device newComputePipelineStateWithFunction:func error:nil];
    
    self.originDes = [MTLTextureDescriptor new];
    self.originDes.width = self.videoTrack.naturalSize.width;
    self.originDes.height = self.videoTrack.naturalSize.height;
    self.originDes.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.originDes.textureType = MTLTextureType2D;
    self.originDes.usage = MTLTextureUsageShaderRead;
    
    self.targetDes = [MTLTextureDescriptor new];
    self.targetDes.width = self.videoTrack.naturalSize.width;
    self.targetDes.height = self.videoTrack.naturalSize.height;
    self.targetDes.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.targetDes.textureType = MTLTextureType2D;
    self.targetDes.usage = MTLTextureUsageShaderWrite;
}

- (void)transcode:(nonnull NSString *)outputPath {
    [self prepareWriter:outputPath];
    
    if (![self.writer startWriting]) {
        NSLog(@"Error:startWriting");
        return;
    }
    
    [self.writer startSessionAtSourceTime:kCMTimeZero];
    
    VDWeak(self);
    [self.writerInput requestMediaDataWhenReadyOnQueue:self.queue usingBlock:^{
        VDStrong(self);
        BOOL completed = NO;
        while (self.writerInput.readyForMoreMediaData) {
            @autoreleasepool {
                CMSampleBufferRef sampleBuffer = [self.videoOutput copyNextSampleBuffer];
                if (sampleBuffer) {
                    CVPixelBufferRef targetPixel = [self render:CMSampleBufferGetImageBuffer(sampleBuffer)];
                    [self.inputAdaptor appendPixelBuffer:targetPixel
                                    withPresentationTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                    CFRelease(sampleBuffer);
                    CVPixelBufferRelease(targetPixel);
                } else {
                    completed = YES;
                    [self.writerInput markAsFinished];
                    break;
                }
            }
            
        }
        if (completed) {
            VDWeak(self);
            [self.writer finishWritingWithCompletionHandler:^{
                VDStrong(self);
                if (self.writer.status == AVAssetWriterStatusCompleted) {
                    NSLog(@"Video transcoding completed.");
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate videoCoder:self didFinishRender:@"123"];
                    });
                } else if (self.writer.status == AVAssetWriterStatusFailed) {
                    NSLog(@"Video transcoding failed: %@",self.writer.error.localizedDescription);
                    NSLog(@"%@", self.writer.error);
                }
            }];
        }
    }];
}

# pragma mark - texture处理

- (CVPixelBufferRef)copyPixelBufferFrom:(id<MTLTexture>)texture {
    if (!texture) {
        return NULL;
    }
    
    CVPixelBufferRef buffer;
    CVPixelBufferCreate(NULL, texture.width, texture.height, kCVPixelFormatType_32BGRA, NULL, &buffer);
    if (!buffer) {
        return NULL;
    }
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    void *data = CVPixelBufferGetBaseAddress(buffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    MTLRegion region = MTLRegionMake2D(0, 0, texture.width, texture.height);
    [texture getBytes:data bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return buffer;
}

@end
