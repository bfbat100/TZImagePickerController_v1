//
//  TZImageManager.m
//  TZImagePickerController
//
//  Created by 谭真 on 16/1/4.
//  Copyright © 2016年 谭真. All rights reserved.
//

#import "TZImageManager.h"
#import "TZAssetModel.h"
#import "TZImagePickerController.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <SVProgressHUD/SVProgressHUD.h>

@interface TZImageManager ()
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@end

@implementation TZImageManager

CGSize AssetGridThumbnailSize;
CGFloat TZScreenWidth;
CGFloat TZScreenScale;

static TZImageManager *manager;
static dispatch_once_t onceToken;


/*
 * 自定义视频压缩
 * videoUrl 原视频url路径 必传
 * outputBiteRate 压缩视频至指定比特率(bps) 可传nil 默认1500kbps
 * outputFrameRate 压缩视频至指定帧率 可传nil 默认30fps
 * outputWidth 压缩视频至指定宽度 可传nil 默认960
 * outputWidth 压缩视频至指定高度 可传nil 默认540
 * compressComplete 压缩后的视频信息回调 (id responseObjc) 可自行打印查看
 **/
- (void)compressVideoWithVideoUrl:(NSURL *)videoUrl withBiteRate:(NSNumber * _Nullable)outputBiteRate withFrameRate:(NSNumber * _Nullable)outputFrameRate withVideoWidth:(NSNumber * _Nullable)outputWidth withVideoHeight:(NSNumber * _Nullable)outputHeight  compressComplete:(void(^)(id responseObjc))compressComplete{
    
//    AVMutableComposition *comosition = [AVMutableComposition composition];
//
//    AVMutableCompositionTrack *videoTrack = [comosition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
//
//    //合成方向处理
//
//    videoTrack.preferredTransform =  CGAffineTransformMakeRotation(M_PI/2);
    
    if (!videoUrl) {
        [SVProgressHUD showErrorWithStatus:@"视频路径不能为空"];
        return;
    }
    NSLog(@"===videoUrl.abs = %@, videoUrl.path = %@", videoUrl.absoluteString, videoUrl.path);
    NSInteger compressBiteRate = outputBiteRate ? [outputBiteRate integerValue] : 1500 * 1024;
    NSInteger compressFrameRate = outputFrameRate ? [outputFrameRate integerValue] : 30;
    NSInteger compressWidth = outputWidth ? [outputWidth integerValue] : 960;
    NSInteger compressHeight = outputHeight ? [outputHeight integerValue] : 540;
    //取出原视频详细资料
    AVURLAsset *asset = [AVURLAsset assetWithURL:videoUrl];
    //视频时长 S
//    CMTime time = [asset duration];2
//    NSInteger seconds = ceil(time.value/time.timescale);
//    if (seconds < 3) {
//        [SVProgressHUD showErrorWithStatus:@"请上传3秒以上的视频"];
//        return;
//    }
    //压缩前原视频大小MB
    unsigned long long fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:videoUrl.path error:nil].fileSize;
    float fileSizeMB = fileSize / (1024.0*1024.0);
    //取出asset中的视频文件
    AVAssetTrack *videoTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    //压缩前原视频宽高
    NSInteger videoWidth = videoTrack.naturalSize.width;
    NSInteger videoHeight = videoTrack.naturalSize.height;
    //压缩前原视频比特率
    NSInteger kbps = videoTrack.estimatedDataRate / 1024;
    //压缩前原视频帧率
    NSInteger frameRate = [videoTrack nominalFrameRate];
//    NSLog(@"\noriginalVideo\nfileSize = %.2f MB,\n videoWidth = %ld,\n videoHeight = %ld,\n video bitRate = %ld\n, video frameRate = %ld", fileSizeMB, videoWidth, videoHeight, kbps, frameRate);
    NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithDictionary:@{@"urlStr" : videoUrl.path}];
    //原视频比特率小于指定比特率 不压缩 返回原视频
    if (kbps <= (compressBiteRate / 1024)) {
        compressComplete(dic);
        return;
    }
    //指定压缩视频沙盒根目录
    NSString *cachesDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    //添加文件完整路径
    NSDate *datenow = [NSDate date];
    NSString *timeSp = [NSString stringWithFormat:@"%ld", (long)([datenow timeIntervalSince1970]*1000)];
  
    NSString *outputUrlStr = [[cachesDir stringByAppendingPathComponent:timeSp] stringByAppendingPathExtension:@"mp4"];
//    NSLog(@"===压缩视频存放的指定路径%@===", outputUrlStr);
    //如果指定路径下已存在其他文件 先移除指定文件
    if ([[NSFileManager defaultManager] fileExistsAtPath:outputUrlStr]) {
        BOOL removeSuccess =  [[NSFileManager defaultManager] removeItemAtPath:outputUrlStr error:nil];
        if (!removeSuccess) {
            [SVProgressHUD showErrorWithStatus:@"旧文件移除失败"];
            return;
        }
    }
    //创建视频文件读取者
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
    //从指定文件读取视频
    AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:[self configVideoOutput]];
    //取出原视频中音频详细资料
    AVAssetTrack *audioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    //从音频资料中读取音频
    AVAssetReaderTrackOutput *audioOutput;
    if(audioTrack){
      audioOutput  = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:[self configAudioOutput]];
        //将读取到的音频信息添加到读者队列中
          if ([reader canAddOutput:audioOutput]) {
              [reader addOutput:audioOutput];
          }
    }
    //将读取到的视频信息添加到读者队列中
    if ([reader canAddOutput:videoOutput]) {
        [reader addOutput:videoOutput];
    }
  
    //视频文件写入者
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:outputUrlStr] fileType:AVFileTypeMPEG4 error:nil];
    //根据指定配置创建写入的视频文件
    AVAssetWriterInput *videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:[self videoCompressSettingsWithBitRate:compressBiteRate withFrameRate:compressFrameRate withWidth:compressWidth WithHeight:compressHeight withOriginalWidth:videoWidth withOriginalHeight:videoHeight]];
    
    NSUInteger degress = 0;
    
    CGAffineTransform t = videoTrack.preferredTransform;
    
    if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0){
        // Portrait
        degress = 90;
    }else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0){
        // PortraitUpsideDown
        degress = 270;
    }else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0){
        // LandscapeRight
        degress = 0;
    }else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0){
        // LandscapeLeft
        degress = 180;
    }
    CGAffineTransform rotate = CGAffineTransformMakeRotation(degress / 180.0 * M_PI );
    videoInput.transform=rotate;
    
    //根据指定配置创建写入的音频文件
    AVAssetWriterInput *audioInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:[self audioCompressSettings]];
    if ([writer canAddInput:videoInput]) {
        [writer addInput:videoInput];
//        NSLog(@"videoInput==========videoInput");
    }
    if ([writer canAddInput:audioInput]) {
        [writer addInput:audioInput];
//        NSLog(@"audioInput==========audioInput");
    }
    [reader startReading];
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    //创建视频写入队列
    dispatch_queue_t videoQueue = dispatch_queue_create("Video Queue", DISPATCH_QUEUE_SERIAL);
    //创建音频写入队列
    dispatch_queue_t audioQueue = dispatch_queue_create("Audio Queue", DISPATCH_QUEUE_SERIAL);
    //创建一个线程组
    dispatch_group_t group = dispatch_group_create();
    //进入线程组
    dispatch_group_enter(group);
    //队列准备好后 usingBlock
    [videoInput requestMediaDataWhenReadyOnQueue:videoQueue usingBlock:^{
        BOOL completedOrFailed = NO;
        while ([videoInput isReadyForMoreMediaData] && !completedOrFailed) {
            CMSampleBufferRef sampleBuffer = [videoOutput copyNextSampleBuffer];
            if (sampleBuffer != NULL) {
                [videoInput appendSampleBuffer:sampleBuffer];
//                NSLog(@"===%@===", sampleBuffer);
                CFRelease(sampleBuffer);
            } else {
                completedOrFailed = YES;
                [videoInput markAsFinished];
                dispatch_group_leave(group);
            }
        }
    }];
    dispatch_group_enter(group);
    //队列准备好后 usingBlock
    [audioInput requestMediaDataWhenReadyOnQueue:audioQueue usingBlock:^{
        BOOL completedOrFailed = NO;
        while (audioInput && [audioInput isReadyForMoreMediaData] && !completedOrFailed) {
            CMSampleBufferRef sampleBuffer = [audioOutput copyNextSampleBuffer];
            if (sampleBuffer != NULL) {
                BOOL success = [audioInput appendSampleBuffer:sampleBuffer];
//                NSLog(@"===%@===", sampleBuffer);
                CFRelease(sampleBuffer);
                completedOrFailed = !success;
            } else {
                completedOrFailed = YES;
            }
        }
        if (completedOrFailed) {
            [audioInput markAsFinished];
            dispatch_group_leave(group);
        }
    }];
    //完成压缩
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if ([reader status] == AVAssetReaderStatusReading) {
            [reader cancelReading];
        }
        switch (writer.status) {
            case AVAssetWriterStatusWriting:
            {
//                [SVProgressHUD showSuccessWithStatus:@"视频压缩完成"];
                [writer finishWritingWithCompletionHandler:^{
                    [dic setObject:outputUrlStr forKey:@"urlStr"];
                    compressComplete(dic);
                }];
            }
                break;
            case AVAssetWriterStatusCancelled:
                [SVProgressHUD showInfoWithStatus:@"取消压缩"];
                break;
            case AVAssetWriterStatusFailed:
                NSLog(@"===error：%@===", writer.error);
//                [SVProgressHUD showErrorWithStatus:[NSString stringWithFormat:@"%@",writer.error]];
                break;
            case AVAssetWriterStatusCompleted:
            {
//                [SVProgressHUD showSuccessWithStatus:@"视频压缩完成"];
                [writer finishWritingWithCompletionHandler:^{
                    [dic setObject:outputUrlStr forKey:@"urlStr"];
                    compressComplete(dic);
                }];
            }
                break;
            default:
                break;
        }
    });
}
- (NSDictionary *)videoCompressSettingsWithBitRate:(NSInteger)biteRate withFrameRate:(NSInteger)frameRate withWidth:(NSInteger)width WithHeight:(NSInteger)height withOriginalWidth:(NSInteger)originalWidth withOriginalHeight:(NSInteger)originalHeight{
    /*
     * AVVideoAverageBitRateKey： 比特率（码率）每秒传输的文件大小 kbps
     * AVVideoExpectedSourceFrameRateKey：帧率 每秒播放的帧数
     * AVVideoProfileLevelKey：画质水平
     BP-Baseline Profile：基本画质。支持I/P 帧，只支持无交错（Progressive）和CAVLC；
     EP-Extended profile：进阶画质。支持I/P/B/SP/SI 帧，只支持无交错（Progressive）和CAVLC；
     MP-Main profile：主流画质。提供I/P/B 帧，支持无交错（Progressive）和交错（Interlaced），也支持CAVLC 和CABAC 的支持；
     HP-High profile：高级画质。在main Profile 的基础上增加了8×8内部预测、自定义量化、 无损视频编码和更多的YUV 格式；
     **/
    NSInteger returnWidth = originalWidth ;
    NSInteger returnHeight = originalHeight;
//    NSInteger returnWidth = originalWidth > originalHeight ? width : height;
//    NSInteger returnHeight = originalWidth > originalHeight ? height : width;
    NSDictionary *compressProperties = @{
                                         AVVideoAverageBitRateKey : @(biteRate),
                                         AVVideoExpectedSourceFrameRateKey : @(frameRate),
//                                         AVVideoMaxKeyFrameIntervalKey:@(2), //：关键帧最大间隔，1为每个都是关键帧，数值越大压缩率越高
                                         AVVideoProfileLevelKey : AVVideoProfileLevelH264HighAutoLevel
                                         };
    if (@available(iOS 11.0, *)) {
        NSDictionary *compressSetting = @{
                                          AVVideoCodecKey : AVVideoCodecTypeH264,
                                          AVVideoHeightKey : @(returnHeight),
                                          AVVideoWidthKey : @(returnWidth),
                                          AVVideoCompressionPropertiesKey : compressProperties,
                                          AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill
                                          };
        return compressSetting;
    }else {
        NSDictionary *compressSetting = @{
                                          AVVideoCodecKey : AVVideoCodecTypeH264,
                                          AVVideoWidthKey : @(returnWidth),
                                          AVVideoHeightKey : @(returnHeight),
                                          AVVideoCompressionPropertiesKey : compressProperties,
                                          AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill
                                          };
        return compressSetting;
    }
}
//音频设置
- (NSDictionary *)audioCompressSettings{
    AudioChannelLayout stereoChannelLayout = {
        .mChannelLayoutTag = kAudioChannelLayoutTag_Stereo,
        .mChannelBitmap = kAudioChannelBit_Left,
        .mNumberChannelDescriptions = 0,
    };
    NSData *channelLayoutAsData = [NSData dataWithBytes:&stereoChannelLayout length:offsetof(AudioChannelLayout, mChannelDescriptions)];
    NSDictionary *audioCompressSettings = @{
                                            AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                            AVEncoderBitRateKey : @(128000),
                                            AVSampleRateKey : @(44100),
                                            AVNumberOfChannelsKey : @(2),
                                            AVChannelLayoutKey : channelLayoutAsData
                                            };
    return audioCompressSettings;
}
/** 音频解码 */
- (NSDictionary *)configAudioOutput
{
    NSDictionary *audioOutputSetting = @{
                                         AVFormatIDKey: @(kAudioFormatLinearPCM)
                                         };
    return audioOutputSetting;
}
/** 视频解码 */
- (NSDictionary *)configVideoOutput
{
    NSDictionary *videoOutputSetting = @{
                                         (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8],
                                         (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey:[NSDictionary dictionary]
                                         };
    
    return videoOutputSetting;
}

-(NSUInteger)degressFromVideoFileWithURL:(NSURL *)url
{
    NSUInteger degress = 0;
    
    AVAsset *asset = [AVAsset assetWithURL:url];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if([tracks count] > 0) {
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        CGAffineTransform t = videoTrack.preferredTransform;
        
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0){
            // Portrait
            degress = 90;
        }else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0){
            // PortraitUpsideDown
            degress = 270;
        }else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0){
            // LandscapeRight
            degress = 0;
        }else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0){
            // LandscapeLeft
            degress = 180;
        }
    }
    return degress;
}


+ (instancetype)manager {
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
        // manager.cachingImageManager = [[PHCachingImageManager alloc] init];
        // manager.cachingImageManager.allowsCachingHighQualityImages = YES;
        
        [manager configTZScreenWidth];
    });
    return manager;
}

+ (void)deallocManager {
    onceToken = 0;
    manager = nil;
}
+ (void)judgeAssetBigger:(TZAssetModel*)model isNeedSizeControl:(BOOL)isNeedSizeControl result:(nonnull void (^)(BOOL isFail,NSString *errorMsg))result{
    
    static BOOL tmpResult = false;
    static NSString *msg;
    
    if (model.type == TZAssetModelMediaTypeVideo) {
        PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
        options.version = PHVideoRequestOptionsVersionOriginal;
        
        [[PHImageManager defaultManager] requestAVAssetForVideo:model.asset options:options resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                AVURLAsset* urlAsset = (AVURLAsset*)asset;
                NSNumber *size;
                [urlAsset.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
                
                if (!([TZImageManager manager].videoNum < [TZImageManager manager].videoMaxCount)) {
                    msg = [NSString stringWithFormat:@"最多可选择%d个视频",[TZImageManager manager].videoMaxCount];
                    result(true,msg);
                    return;
                }
                if ([size floatValue]/(1024.0*1024.0) > 30.0) { //大于30M
                    msg = @"不可选择大于30M的视频";
                    result(true,msg);
                    return ;
                }
                if ([TZImageManager manager].videoMaxDuration == 0) {
                    result(false,nil);
                    return;
                }
                else if (model.asset.duration > [TZImageManager manager].videoMaxDuration) {
                    if ((int)[TZImageManager manager].videoMaxDuration%60 == 0){
                        msg = [NSString stringWithFormat:@"不可选择大于%d分钟的视频",(int)[TZImageManager manager].videoMaxDuration/60];
                    }else {
                        msg = [NSString stringWithFormat:@"不可选择大于%d分%d秒的视频",(int)[TZImageManager manager].videoMaxDuration/60,(int)[TZImageManager manager].videoMaxDuration%60];
                    }
                    result(true,msg);
                    return ;
                }
                result(false,nil);
            }
        }];
    }else {
        PHImageManager * imageManager = [PHImageManager defaultManager];
        [imageManager requestImageDataForAsset:model.asset options:nil resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
            NSInteger length = imageData.length;   // 图片大小，单位B
            if (length / (1024.0*1024.0) > 30.0) { //大于30M
                tmpResult = true;
                msg = @"不可选择大于30M的图片";
            }else{
                tmpResult = false;
            }
            result(tmpResult,msg);
        }];
    }
}

- (void)setPhotoWidth:(CGFloat)photoWidth {
    _photoWidth = photoWidth;
    TZScreenWidth = photoWidth / 2;
}

- (void)setColumnNumber:(NSInteger)columnNumber {
    [self configTZScreenWidth];

    _columnNumber = columnNumber;
    CGFloat margin = 4;
    CGFloat itemWH = (TZScreenWidth - 2 * margin - 4) / columnNumber - margin;
    AssetGridThumbnailSize = CGSizeMake(itemWH * TZScreenScale, itemWH * TZScreenScale);
}

- (void)configTZScreenWidth {
    TZScreenWidth = [UIScreen mainScreen].bounds.size.width;
    // 测试发现，如果scale在plus真机上取到3.0，内存会增大特别多。故这里写死成2.0
    TZScreenScale = 2.0;
    if (TZScreenWidth > 700) {
        TZScreenScale = 1.5;
    }
}

/// Return YES if Authorized 返回YES如果得到了授权
- (BOOL)authorizationStatusAuthorized {
    if (self.isPreviewNetworkImage) {
        return YES;
    }
    NSInteger status = [PHPhotoLibrary authorizationStatus];
    if (status == 0) {
        /**
         * 当某些情况下AuthorizationStatus == AuthorizationStatusNotDetermined时，无法弹出系统首次使用的授权alertView，系统应用设置里亦没有相册的设置，此时将无法使用，故作以下操作，弹出系统首次使用的授权alertView
         */
        [self requestAuthorizationWithCompletion:nil];
    }
    
    return status == 3;
}

- (void)requestAuthorizationWithCompletion:(void (^)(void))completion {
    void (^callCompletionBlock)(void) = ^(){
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion();
            }
        });
    };
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            callCompletionBlock();
        }];
    });
}

#pragma mark - Get Album

- (void)getCameraRollAlbum:(BOOL)allowPickingVideo allowPickingImage:(BOOL)allowPickingImage needFetchAssets:(BOOL)needFetchAssets completion:(void (^)(TZAlbumModel *model))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    config.allowPickingVideo = allowPickingVideo;
    config.allowPickingImage = allowPickingImage;
    [self getCameraRollAlbumWithFetchAssets:needFetchAssets completion:completion];
}

/// Get Album 获得相册/相册数组
- (void)getCameraRollAlbumWithFetchAssets:(BOOL)needFetchAssets completion:(void (^)(TZAlbumModel *model))completion {
    __block TZAlbumModel *model;
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    PHFetchOptions *option = [[PHFetchOptions alloc] init];
    if (!config.allowPickingVideo) option.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeImage];
    if (!config.allowPickingImage) option.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld",
                                                PHAssetMediaTypeVideo];
    // option.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"modificationDate" ascending:self.sortAscendingByModificationDate]];
    if (!self.sortAscendingByModificationDate) {
        option.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:self.sortAscendingByModificationDate]];
    }
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    for (PHAssetCollection *collection in smartAlbums) {
        // 有可能是PHCollectionList类的的对象，过滤掉
        if (![collection isKindOfClass:[PHAssetCollection class]]) continue;
        // 过滤空相册
        if (collection.estimatedAssetCount <= 0) continue;
        if ([self isCameraRollAlbum:collection]) {
            PHFetchResult *fetchResult = [PHAsset fetchAssetsInAssetCollection:collection options:option];
            model = [self modelWithResult:fetchResult collection:collection isCameraRoll:YES needFetchAssets:needFetchAssets options:option];
            if (completion) completion(model);
            break;
        }
    }
}

- (void)getAllAlbums:(BOOL)allowPickingVideo allowPickingImage:(BOOL)allowPickingImage needFetchAssets:(BOOL)needFetchAssets completion:(void (^)(NSArray<TZAlbumModel *> *))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    config.allowPickingVideo = allowPickingVideo;
    config.allowPickingImage = allowPickingImage;
    [self getAllAlbumsWithFetchAssets:needFetchAssets completion:completion];
}

- (void)getAllAlbumsWithFetchAssets:(BOOL)needFetchAssets completion:(void (^)(NSArray<TZAlbumModel *> *))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    NSMutableArray *albumArr = [NSMutableArray array];
    PHFetchOptions *option = [[PHFetchOptions alloc] init];
    if (!config.allowPickingVideo) option.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld", PHAssetMediaTypeImage];
    if (!config.allowPickingImage) option.predicate = [NSPredicate predicateWithFormat:@"mediaType == %ld",
                                                PHAssetMediaTypeVideo];
    // option.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"modificationDate" ascending:self.sortAscendingByModificationDate]];
    if (!self.sortAscendingByModificationDate) {
        option.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:self.sortAscendingByModificationDate]];
    }
    // 我的照片流 1.6.10重新加入..
    PHFetchResult *myPhotoStreamAlbum = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumMyPhotoStream options:nil];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    PHFetchResult *topLevelUserCollections = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    PHFetchResult *syncedAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumSyncedAlbum options:nil];
    PHFetchResult *sharedAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumCloudShared options:nil];
    NSArray *allAlbums = @[myPhotoStreamAlbum,smartAlbums,topLevelUserCollections,syncedAlbums,sharedAlbums];
    for (PHFetchResult *fetchResult in allAlbums) {
        for (PHAssetCollection *collection in fetchResult) {
            // 有可能是PHCollectionList类的的对象，过滤掉
            if (![collection isKindOfClass:[PHAssetCollection class]]) continue;
            // 过滤空相册
            if (collection.estimatedAssetCount <= 0 && ![self isCameraRollAlbum:collection]) continue;
            PHFetchResult *fetchResult = [PHAsset fetchAssetsInAssetCollection:collection options:option];
            if (fetchResult.count < 1 && ![self isCameraRollAlbum:collection]) continue;
            
            if ([self.pickerDelegate respondsToSelector:@selector(isAlbumCanSelect:result:)]) {
                if (![self.pickerDelegate isAlbumCanSelect:collection.localizedTitle result:fetchResult]) {
                    continue;
                }
            }
            
            if (collection.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumAllHidden) continue;
            if (collection.assetCollectionSubtype == 1000000201) continue; //『最近删除』相册
            if ([self isCameraRollAlbum:collection]) {
                [albumArr insertObject:[self modelWithResult:fetchResult collection:collection isCameraRoll:YES needFetchAssets:needFetchAssets options:option] atIndex:0];
            } else {
                [albumArr addObject:[self modelWithResult:fetchResult collection:collection isCameraRoll:NO needFetchAssets:needFetchAssets options:option]];
            }
        }
    }
    if (completion) {
        completion(albumArr);
    }
}

#pragma mark - Get Assets

/// Get Assets 获得照片数组
- (void)getAssetsFromFetchResult:(PHFetchResult *)result allowPickingVideo:(BOOL)allowPickingVideo allowPickingImage:(BOOL)allowPickingImage completion:(void (^)(NSArray<TZAssetModel *> *))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    config.allowPickingVideo = allowPickingVideo;
    config.allowPickingImage = allowPickingImage;
    return [self getAssetsFromFetchResult:result completion:completion];
}

- (void)getAssetsFromFetchResult:(PHFetchResult *)result completion:(void (^)(NSArray<TZAssetModel *> *))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    NSMutableArray *photoArr = [NSMutableArray array];
    [result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL * _Nonnull stop) {
        TZAssetModel *model = [self assetModelWithAsset:asset allowPickingVideo:config.allowPickingVideo allowPickingImage:config.allowPickingImage];
        if (model) {
            [photoArr addObject:model];
        }
    }];
    if (completion) completion(photoArr);
}

///  Get asset at index 获得下标为index的单个照片
///  if index beyond bounds, return nil in callback 如果索引越界, 在回调中返回 nil
- (void)getAssetFromFetchResult:(PHFetchResult *)result atIndex:(NSInteger)index allowPickingVideo:(BOOL)allowPickingVideo allowPickingImage:(BOOL)allowPickingImage completion:(void (^)(TZAssetModel *))completion {
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    config.allowPickingVideo = allowPickingVideo;
    config.allowPickingImage = allowPickingImage;
    [self getAssetFromFetchResult:result atIndex:index allowPickingVideo:config.allowPickingVideo allowPickingImage:config.allowPickingImage completion:completion];
}

- (void)getAssetFromFetchResult:(PHFetchResult *)result atIndex:(NSInteger)index completion:(void (^)(TZAssetModel *))completion {
    PHAsset *asset;
    @try {
        asset = result[index];
    }
    @catch (NSException* e) {
        if (completion) completion(nil);
        return;
    }
    TZImagePickerConfig *config = [TZImagePickerConfig sharedInstance];
    TZAssetModel *model = [self assetModelWithAsset:asset allowPickingVideo:config.allowPickingVideo allowPickingImage:config.allowPickingImage];
    if (completion) completion(model);
}

- (TZAssetModel *)assetModelWithAsset:(PHAsset *)asset allowPickingVideo:(BOOL)allowPickingVideo allowPickingImage:(BOOL)allowPickingImage {
    BOOL canSelect = YES;
    if ([self.pickerDelegate respondsToSelector:@selector(isAssetCanSelect:)]) {
        canSelect = [self.pickerDelegate isAssetCanSelect:asset];
    }
    if (!canSelect) return nil;
    
    TZAssetModel *model;
    TZAssetModelMediaType type = [self getAssetType:asset];
    if (!allowPickingVideo && type == TZAssetModelMediaTypeVideo) return nil;
    if (!allowPickingImage && type == TZAssetModelMediaTypePhoto) return nil;
    if (!allowPickingImage && type == TZAssetModelMediaTypePhotoGif) return nil;
    
    PHAsset *phAsset = (PHAsset *)asset;
    if (self.hideWhenCanNotSelect) {
        // 过滤掉尺寸不满足要求的图片
        if (![self isPhotoSelectableWithAsset:phAsset]) {
            return nil;
        }
    }
    NSString *timeLength = type == TZAssetModelMediaTypeVideo ? [NSString stringWithFormat:@"%0.0f",phAsset.duration] : @"";
    timeLength = [self getNewTimeFromDurationSecond:timeLength.integerValue];
    model = [TZAssetModel modelWithAsset:asset type:type timeLength:timeLength];
    return model;
}

- (TZAssetModelMediaType)getAssetType:(PHAsset *)asset {
    TZAssetModelMediaType type = TZAssetModelMediaTypePhoto;
    PHAsset *phAsset = (PHAsset *)asset;
    if (phAsset.mediaType == PHAssetMediaTypeVideo)      type = TZAssetModelMediaTypeVideo;
    else if (phAsset.mediaType == PHAssetMediaTypeAudio) type = TZAssetModelMediaTypeAudio;
    else if (phAsset.mediaType == PHAssetMediaTypeImage) {
        if (@available(iOS 9.1, *)) {
            // if (asset.mediaSubtypes == PHAssetMediaSubtypePhotoLive) type = TZAssetModelMediaTypeLivePhoto;
        }
        // Gif
        if ([[phAsset valueForKey:@"filename"] hasSuffix:@"GIF"]) {
            type = TZAssetModelMediaTypePhotoGif;
        }
    }
    return type;
}

- (NSString *)getNewTimeFromDurationSecond:(NSInteger)duration {
    NSString *newTime;
    if (duration < 10) {
        newTime = [NSString stringWithFormat:@"0:0%zd",duration];
    } else if (duration < 60) {
        newTime = [NSString stringWithFormat:@"0:%zd",duration];
    } else {
        NSInteger min = duration / 60;
        NSInteger sec = duration - (min * 60);
        if (sec < 10) {
            newTime = [NSString stringWithFormat:@"%zd:0%zd",min,sec];
        } else {
            newTime = [NSString stringWithFormat:@"%zd:%zd",min,sec];
        }
    }
    return newTime;
}

/// Get photo bytes 获得一组照片的大小
- (void)getPhotosBytesWithArray:(NSArray *)photos completion:(void (^)(NSString *totalBytes))completion {
    if (!photos || !photos.count) {
        if (completion) completion(@"0B");
        return;
    }
    __block NSInteger dataLength = 0;
    __block NSInteger assetCount = 0;
    for (NSInteger i = 0; i < photos.count; i++) {
        TZAssetModel *model = photos[i];
        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        options.resizeMode = PHImageRequestOptionsResizeModeFast;
        options.networkAccessAllowed = YES;
        if (model.type == TZAssetModelMediaTypePhotoGif) {
            options.version = PHImageRequestOptionsVersionOriginal;
        }
        [[PHImageManager defaultManager] requestImageDataForAsset:model.asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
            if (model.type != TZAssetModelMediaTypeVideo) dataLength += imageData.length;
            assetCount ++;
            if (assetCount >= photos.count) {
                NSString *bytes = [self getBytesFromDataLength:dataLength];
                if (completion) completion(bytes);
            }
        }];
    }
}

- (NSString *)getBytesFromDataLength:(NSInteger)dataLength {
    NSString *bytes;
    if (dataLength >= 0.1 * (1024 * 1024)) {
        bytes = [NSString stringWithFormat:@"%0.1fM",dataLength/1024/1024.0];
    } else if (dataLength >= 1024) {
        bytes = [NSString stringWithFormat:@"%0.0fK",dataLength/1024.0];
    } else {
        bytes = [NSString stringWithFormat:@"%zdB",dataLength];
    }
    return bytes;
}

#pragma mark - Get Photo

/// Get photo 获得照片本身
- (PHImageRequestID)getPhotoWithAsset:(PHAsset *)asset completion:(void (^)(UIImage *, NSDictionary *, BOOL isDegraded))completion {
    CGFloat fullScreenWidth = TZScreenWidth;
    if (fullScreenWidth > _photoPreviewMaxWidth) {
        fullScreenWidth = _photoPreviewMaxWidth;
    }
    return [self getPhotoWithAsset:asset photoWidth:fullScreenWidth completion:completion progressHandler:nil networkAccessAllowed:YES];
}

- (PHImageRequestID)getPhotoWithAsset:(PHAsset *)asset photoWidth:(CGFloat)photoWidth completion:(void (^)(UIImage *photo,NSDictionary *info,BOOL isDegraded))completion {
    return [self getPhotoWithAsset:asset photoWidth:photoWidth completion:completion progressHandler:nil networkAccessAllowed:YES];
}

- (PHImageRequestID)getPhotoWithAsset:(PHAsset *)asset completion:(void (^)(UIImage *photo,NSDictionary *info,BOOL isDegraded))completion progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler networkAccessAllowed:(BOOL)networkAccessAllowed {
    CGFloat fullScreenWidth = TZScreenWidth;
    if (_photoPreviewMaxWidth > 0 && fullScreenWidth > _photoPreviewMaxWidth) {
        fullScreenWidth = _photoPreviewMaxWidth;
    }
    return [self getPhotoWithAsset:asset photoWidth:fullScreenWidth completion:completion progressHandler:progressHandler networkAccessAllowed:networkAccessAllowed];
}

- (PHImageRequestID)requestImageDataForAsset:(PHAsset *)asset completion:(void (^)(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info))completion progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler {
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progressHandler) {
                progressHandler(progress, error, stop, info);
            }
        });
    };
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    int32_t imageRequestID = [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
        if (completion) completion(imageData,dataUTI,orientation,info);
    }];
    return imageRequestID;
}

- (PHImageRequestID)getPhotoWithAsset:(PHAsset *)asset photoWidth:(CGFloat)photoWidth completion:(void (^)(UIImage *photo,NSDictionary *info,BOOL isDegraded))completion progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler networkAccessAllowed:(BOOL)networkAccessAllowed {
    CGSize imageSize;
    if (photoWidth < TZScreenWidth && photoWidth < _photoPreviewMaxWidth) {
        imageSize = AssetGridThumbnailSize;
    } else {
        PHAsset *phAsset = (PHAsset *)asset;
        CGFloat aspectRatio = phAsset.pixelWidth / (CGFloat)phAsset.pixelHeight;
        CGFloat pixelWidth = photoWidth * TZScreenScale;
        // 超宽图片
        if (aspectRatio > 1.8) {
            pixelWidth = pixelWidth * aspectRatio;
        }
        // 超高图片
        if (aspectRatio < 0.2) {
            pixelWidth = pixelWidth * 0.5;
        }
        CGFloat pixelHeight = pixelWidth / aspectRatio;
        imageSize = CGSizeMake(pixelWidth, pixelHeight);
    }
    
    // 修复获取图片时出现的瞬间内存过高问题
    // 下面两行代码，来自hsjcom，他的github是：https://github.com/hsjcom 表示感谢
    PHImageRequestOptions *option = [[PHImageRequestOptions alloc] init];
    option.resizeMode = PHImageRequestOptionsResizeModeFast;
    int32_t imageRequestID = [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:imageSize contentMode:PHImageContentModeAspectFill options:option resultHandler:^(UIImage *result, NSDictionary *info) {
        BOOL cancelled = [[info objectForKey:PHImageCancelledKey] boolValue];
        if (!cancelled && result) {
            result = [self fixOrientation:result];
            if (completion) completion(result,info,[[info objectForKey:PHImageResultIsDegradedKey] boolValue]);
        }
        // Download image from iCloud / 从iCloud下载图片
        if ([info objectForKey:PHImageResultIsInCloudKey] && !result && networkAccessAllowed) {
            PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
            options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (progressHandler) {
                        progressHandler(progress, error, stop, info);
                    }
                });
            };
            options.networkAccessAllowed = YES;
            options.resizeMode = PHImageRequestOptionsResizeModeFast;
            [[PHImageManager defaultManager] requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                UIImage *resultImage = [UIImage imageWithData:imageData];
                if (![TZImagePickerConfig sharedInstance].notScaleImage) {
                    resultImage = [self scaleImage:resultImage toSize:imageSize];
                }
                if (!resultImage && result) {
                    resultImage = result;
                }
                resultImage = [self fixOrientation:resultImage];
                if (completion) completion(resultImage,info,NO);
            }];
        }
    }];
    return imageRequestID;
}

/// Get postImage / 获取封面图
- (PHImageRequestID)getPostImageWithAlbumModel:(TZAlbumModel *)model completion:(void (^)(UIImage *))completion {
    id asset = [model.result lastObject];
    if (!self.sortAscendingByModificationDate) {
        asset = [model.result firstObject];
    }
    if (!asset) {
        return -1;
    }
    return [[TZImageManager manager] getPhotoWithAsset:asset photoWidth:80 completion:^(UIImage *photo, NSDictionary *info, BOOL isDegraded) {
        if (completion) completion(photo);
    }];
}

/// Get Original Photo / 获取原图
- (PHImageRequestID)getOriginalPhotoWithAsset:(PHAsset *)asset completion:(void (^)(UIImage *photo,NSDictionary *info))completion {
   return [self getOriginalPhotoWithAsset:asset newCompletion:^(UIImage *photo, NSDictionary *info, BOOL isDegraded) {
        if (completion) {
            completion(photo,info);
        }
    }];
}

- (PHImageRequestID)getOriginalPhotoWithAsset:(PHAsset *)asset newCompletion:(void (^)(UIImage *photo,NSDictionary *info,BOOL isDegraded))completion {
    return [self getOriginalPhotoWithAsset:asset progressHandler:nil newCompletion:completion];
}

- (PHImageRequestID)getOriginalPhotoWithAsset:(PHAsset *)asset progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler newCompletion:(void (^)(UIImage *photo,NSDictionary *info,BOOL isDegraded))completion {
    PHImageRequestOptions *option = [[PHImageRequestOptions alloc]init];
    option.networkAccessAllowed = YES;
    if (progressHandler) {
        [option setProgressHandler:progressHandler];
    }
    option.resizeMode = PHImageRequestOptionsResizeModeFast;
    return [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:PHImageManagerMaximumSize contentMode:PHImageContentModeAspectFit options:option resultHandler:^(UIImage *result, NSDictionary *info) {
        BOOL cancelled = [[info objectForKey:PHImageCancelledKey] boolValue];
        if (!cancelled && result) {
            result = [self fixOrientation:result];
            BOOL isDegraded = [[info objectForKey:PHImageResultIsDegradedKey] boolValue];
            if (completion) completion(result,info,isDegraded);
        }
    }];
}

- (PHImageRequestID)getOriginalPhotoDataWithAsset:(PHAsset *)asset completion:(void (^)(NSData *data,NSDictionary *info,BOOL isDegraded))completion {
    return [self getOriginalPhotoDataWithAsset:asset progressHandler:nil completion:completion];
}

- (PHImageRequestID)getOriginalPhotoDataWithAsset:(PHAsset *)asset progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler completion:(void (^)(NSData *data,NSDictionary *info,BOOL isDegraded))completion {
    PHImageRequestOptions *option = [[PHImageRequestOptions alloc] init];
    option.networkAccessAllowed = YES;
    if ([[asset valueForKey:@"filename"] hasSuffix:@"GIF"]) {
        // if version isn't PHImageRequestOptionsVersionOriginal, the gif may cann't play
        option.version = PHImageRequestOptionsVersionOriginal;
    }
    [option setProgressHandler:progressHandler];
    option.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    return [[PHImageManager defaultManager] requestImageDataForAsset:asset options:option resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
        BOOL cancelled = [[info objectForKey:PHImageCancelledKey] boolValue];
        if (!cancelled && imageData) {
            if (completion) completion(imageData,info,NO);
        }
    }];
}

#pragma mark - Save photo

- (void)savePhotoWithImage:(UIImage *)image completion:(void (^)(PHAsset *asset, NSError *error))completion {
    [self savePhotoWithImage:image location:nil completion:completion];
}

- (void)savePhotoWithImage:(UIImage *)image location:(CLLocation *)location completion:(void (^)(PHAsset *asset, NSError *error))completion {
    __block NSString *localIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        localIdentifier = request.placeholderForCreatedAsset.localIdentifier;
        if (location) {
            request.location = location;
        }
        request.creationDate = [NSDate date];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && completion) {
                [self fetchAssetByIocalIdentifier:localIdentifier retryCount:10 completion:completion];
            } else if (error) {
//                NSLog(@"保存照片出错:%@",error.localizedDescription);
                if (completion) {
                    completion(nil, error);
                }
            }
        });
    }];
}

- (void)savePhotoWithImage:(UIImage *)image meta:(NSDictionary *)meta location:(CLLocation *)location completion:(void (^)(PHAsset *asset, NSError *error))completion {
    NSData *imageData = UIImageJPEGRepresentation(image, 1.0f);
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    NSDateFormatter *formater = [[NSDateFormatter alloc] init];
    [formater setDateFormat:@"yyyy-MM-dd-HH:mm:ss-SSS"];
    NSString *path = [NSTemporaryDirectory() stringByAppendingFormat:@"image-%@.jpg", [formater stringFromDate:[NSDate date]]];
    NSURL *tmpURL = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)tmpURL, kUTTypeJPEG, 1, NULL);
    CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef)meta);
    CGImageDestinationFinalize(destination);
    CFRelease(source);
    CFRelease(destination);
    
    __block NSString *localIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:tmpURL];
        localIdentifier = request.placeholderForCreatedAsset.localIdentifier;
        if (location) {
            request.location = location;
        }
        request.creationDate = [NSDate date];
    } completionHandler:^(BOOL success, NSError *error) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && completion) {
                [self fetchAssetByIocalIdentifier:localIdentifier retryCount:10 completion:completion];
            } else if (error) {
//                NSLog(@"保存照片出错:%@",error.localizedDescription);
                if (completion) {
                    completion(nil, error);
                }
            }
        });
    }];
}

- (void)fetchAssetByIocalIdentifier:(NSString *)localIdentifier retryCount:(NSInteger)retryCount completion:(void (^)(PHAsset *asset, NSError *error))completion {
    PHAsset *asset = [[PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil] firstObject];
    if (asset || retryCount <= 0) {
        if (completion) {
            completion(asset, nil);
        }
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self fetchAssetByIocalIdentifier:localIdentifier retryCount:retryCount - 1 completion:completion];
    });
}

#pragma mark - Save video

- (void)saveVideoWithUrl:(NSURL *)url completion:(void (^)(PHAsset *asset, NSError *error))completion {
    [self saveVideoWithUrl:url location:nil completion:completion];
}

- (void)saveVideoWithUrl:(NSURL *)url location:(CLLocation *)location completion:(void (^)(PHAsset *asset, NSError *error))completion {
    __block NSString *localIdentifier = nil;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
        localIdentifier = request.placeholderForCreatedAsset.localIdentifier;
        if (location) {
            request.location = location;
        }
        request.creationDate = [NSDate date];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success && completion) {
                [self fetchAssetByIocalIdentifier:localIdentifier retryCount:10 completion:completion];
            } else if (error) {
//                NSLog(@"保存视频出错:%@",error.localizedDescription);
                if (completion) {
                    completion(nil, error);
                }
            }
        });
    }];
}

#pragma mark - Get Video

/// Get Video / 获取视频
- (void)getVideoWithAsset:(PHAsset *)asset completion:(void (^)(AVPlayerItem *, NSDictionary *))completion {
    [self getVideoWithAsset:asset progressHandler:nil completion:completion];
}

- (void)getVideoWithAsset:(PHAsset *)asset progressHandler:(void (^)(double progress, NSError *error, BOOL *stop, NSDictionary *info))progressHandler completion:(void (^)(AVPlayerItem *, NSDictionary *))completion {
    PHVideoRequestOptions *option = [[PHVideoRequestOptions alloc] init];
    option.networkAccessAllowed = YES;
    option.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progressHandler) {
                progressHandler(progress, error, stop, info);
            }
        });
    };
    [[PHImageManager defaultManager] requestPlayerItemForVideo:asset options:option resultHandler:^(AVPlayerItem *playerItem, NSDictionary *info) {
        if (completion) completion(playerItem,info);
    }];
}

#pragma mark - Export video

/// Export Video / 导出视频
- (void)getVideoOutputPathWithAsset:(PHAsset *)asset success:(void (^)(NSString *outputPath))success failure:(void (^)(NSString *errorMessage, NSError *error))failure {
    [self getVideoOutputPathWithAsset:asset presetName:AVAssetExportPreset640x480 success:success failure:failure];
}

- (void)getVideoOutputPathWithAsset:(PHAsset *)asset presetName:(NSString *)presetName success:(void (^)(NSString *outputPath))success failure:(void (^)(NSString *errorMessage, NSError *error))failure {
    PHVideoRequestOptions* options = [[PHVideoRequestOptions alloc] init];
    options.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
    options.networkAccessAllowed = YES;
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset* avasset, AVAudioMix* audioMix, NSDictionary* info){
        // NSLog(@"Info:\n%@",info);
        AVURLAsset *videoAsset = (AVURLAsset*)avasset;
        // NSLog(@"AVAsset URL: %@",myAsset.URL);
        [self startExportVideoWithVideoAsset:videoAsset presetName:presetName success:success failure:failure];
    }];
}

/// Deprecated, Use -getVideoOutputPathWithAsset:failure:success:
- (void)getVideoOutputPathWithAsset:(PHAsset *)asset completion:(void (^)(NSString *outputPath))completion {
    [self getVideoOutputPathWithAsset:asset success:completion failure:nil];
}

- (void)startExportVideoWithVideoAsset:(AVURLAsset *)videoAsset presetName:(NSString *)presetName success:(void (^)(NSString *outputPath))success failure:(void (^)(NSString *errorMessage, NSError *error))failure {
    // Find compatible presets by video asset.
    NSArray *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:videoAsset];
    
    // Begin to compress video
    // Now we just compress to low resolution if it supports
    // If you need to upload to the server, but server does't support to upload by streaming,
    // You can compress the resolution to lower. Or you can support more higher resolution.
    if ([presets containsObject:presetName]) {
        AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:videoAsset presetName:presetName];
        
        NSDateFormatter *formater = [[NSDateFormatter alloc] init];
        [formater setDateFormat:@"yyyy-MM-dd-HH:mm:ss-SSS"];
        NSString *outputPath = [NSHomeDirectory() stringByAppendingFormat:@"/tmp/video-%@.mp4", [formater stringFromDate:[NSDate date]]];
        
        // Optimize for network use.
        session.shouldOptimizeForNetworkUse = true;
        
        NSArray *supportedTypeArray = session.supportedFileTypes;
        if ([supportedTypeArray containsObject:AVFileTypeMPEG4]) {
            session.outputFileType = AVFileTypeMPEG4;
        } else if (supportedTypeArray.count == 0) {
            if (failure) {
                failure(@"该视频类型暂不支持导出", nil);
            }
//            NSLog(@"No supported file types 视频类型暂不支持导出");
            return;
        } else {
            session.outputFileType = [supportedTypeArray objectAtIndex:0];
            if (videoAsset.URL && videoAsset.URL.lastPathComponent) {
                outputPath = [outputPath stringByReplacingOccurrencesOfString:@".mp4" withString:[NSString stringWithFormat:@"-%@", videoAsset.URL.lastPathComponent]];
            }
        }
        // NSLog(@"video outputPath = %@",outputPath);
        session.outputURL = [NSURL fileURLWithPath:outputPath];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:[NSHomeDirectory() stringByAppendingFormat:@"/tmp"]]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:[NSHomeDirectory() stringByAppendingFormat:@"/tmp"] withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        if ([TZImagePickerConfig sharedInstance].needFixComposition) {
            AVMutableVideoComposition *videoComposition = [self fixedCompositionWithAsset:videoAsset];
            if (videoComposition.renderSize.width) {
                // 修正视频转向
                session.videoComposition = videoComposition;
            }
        }
        
        if (self.showHud) {
            self.showHud();
        }

            [self compressVideoWithVideoUrl:videoAsset.URL withBiteRate:@(2000 * 1024) withFrameRate:@(20) withVideoWidth:@(1080) withVideoHeight:@(1920)  compressComplete:^(id responseObjc) {
//                NSLog(@"压缩成功%@",responseObjc);
                 if (success) {
//                     if (self.hideHud) { // 此处不必控制隐藏
//                         self.hideHud();
//                    }
                    success(responseObjc[@"urlStr"]);
                }
            }];
        /*
        // Begin to export video to the output path asynchronously.
        [session exportAsynchronouslyWithCompletionHandler:^(void) {
            dispatch_async(dispatch_get_main_queue(), ^{
                switch (session.status) {
                    case AVAssetExportSessionStatusUnknown: {
                        NSLog(@"AVAssetExportSessionStatusUnknown");
                    }  break;
                    case AVAssetExportSessionStatusWaiting: {
                        NSLog(@"AVAssetExportSessionStatusWaiting");
                    }  break;
                    case AVAssetExportSessionStatusExporting: {
                        NSLog(@"AVAssetExportSessionStatusExporting");
                    }  break;
                    case AVAssetExportSessionStatusCompleted: {
                        NSLog(@"AVAssetExportSessionStatusCompleted");
                        if (success) {
                            success(outputPath);
                        }
                    }  break;
                    case AVAssetExportSessionStatusFailed: {
                        NSLog(@"AVAssetExportSessionStatusFailed");
                        if (failure) {
                            failure(@"视频导出失败", session.error);
                        }
                    }  break;
                    case AVAssetExportSessionStatusCancelled: {
                        NSLog(@"AVAssetExportSessionStatusCancelled");
                        if (failure) {
                            failure(@"导出任务已被取消", nil);
                        }
                    }  break;
                    default: break;
                }
            });
        }];
        */
    }
    else {
        if (failure) {
            NSString *errorMessage = [NSString stringWithFormat:@"当前设备不支持该预设:%@", presetName];
            failure(errorMessage, nil);
        }
    }
}

- (BOOL)isCameraRollAlbum:(PHAssetCollection *)metadata {
    NSString *versionStr = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
    if (versionStr.length <= 1) {
        versionStr = [versionStr stringByAppendingString:@"00"];
    } else if (versionStr.length <= 2) {
        versionStr = [versionStr stringByAppendingString:@"0"];
    }
    CGFloat version = versionStr.floatValue;
    // 目前已知8.0.0 ~ 8.0.2系统，拍照后的图片会保存在最近添加中
    if (version >= 800 && version <= 802) {
        return ((PHAssetCollection *)metadata).assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumRecentlyAdded;
    } else {
        return ((PHAssetCollection *)metadata).assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumUserLibrary;
    }
}

/// 检查照片大小是否满足最小要求
- (BOOL)isPhotoSelectableWithAsset:(PHAsset *)asset {
    CGSize photoSize = CGSizeMake(asset.pixelWidth, asset.pixelHeight);
    if (self.minPhotoWidthSelectable > photoSize.width || self.minPhotoHeightSelectable > photoSize.height) {
        return NO;
    }
    return YES;
}

#pragma mark - Private Method

- (TZAlbumModel *)modelWithResult:(PHFetchResult *)result collection:(PHAssetCollection *)collection isCameraRoll:(BOOL)isCameraRoll needFetchAssets:(BOOL)needFetchAssets options:(PHFetchOptions *)options {
    TZAlbumModel *model = [[TZAlbumModel alloc] init];
    [model setResult:result needFetchAssets:needFetchAssets];
    model.name = collection.localizedTitle;
    model.collection = collection;
    model.options = options;
    model.isCameraRoll = isCameraRoll;
    model.count = result.count;
    return model;
}

/// 缩放图片至新尺寸
- (UIImage *)scaleImage:(UIImage *)image toSize:(CGSize)size {
    if (image.size.width > size.width) {
        UIGraphicsBeginImageContext(size);
        [image drawInRect:CGRectMake(0, 0, size.width, size.height)];
        UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return newImage;
        
        /* 好像不怎么管用：https://mp.weixin.qq.com/s/CiqMlEIp1Ir2EJSDGgMooQ
        CGFloat maxPixelSize = MAX(size.width, size.height);
        CGImageSourceRef sourceRef = CGImageSourceCreateWithData((__bridge CFDataRef)UIImageJPEGRepresentation(image, 0.9), nil);
        NSDictionary *options = @{(__bridge id)kCGImageSourceCreateThumbnailFromImageAlways:(__bridge id)kCFBooleanTrue,
                                  (__bridge id)kCGImageSourceThumbnailMaxPixelSize:[NSNumber numberWithFloat:maxPixelSize]
                                  };
        CGImageRef imageRef = CGImageSourceCreateImageAtIndex(sourceRef, 0, (__bridge CFDictionaryRef)options);
        UIImage *newImage = [UIImage imageWithCGImage:imageRef scale:2 orientation:image.imageOrientation];
        CGImageRelease(imageRef);
        CFRelease(sourceRef);
        return newImage;
         */
    } else {
        return image;
    }
}

/// 判断asset是否是视频
- (BOOL)isVideo:(PHAsset *)asset {
    return asset.mediaType == PHAssetMediaTypeVideo;
}

- (TZAssetModel *)createModelWithAsset:(PHAsset *)asset {
    TZAssetModelMediaType type = [[TZImageManager manager] getAssetType:asset];
    NSString *timeLength = type == TZAssetModelMediaTypeVideo ? [NSString stringWithFormat:@"%0.0f",asset.duration] : @"";
    timeLength = [[TZImageManager manager] getNewTimeFromDurationSecond:timeLength.integerValue];
    TZAssetModel *model = [TZAssetModel modelWithAsset:asset type:type timeLength:timeLength];
    return model;
}

/// 获取优化后的视频转向信息
- (AVMutableVideoComposition *)fixedCompositionWithAsset:(AVAsset *)videoAsset {
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    // 视频转向
    int degrees = [self degressFromVideoFileWithAsset:videoAsset];
    if (degrees != 0) {
        CGAffineTransform translateToCenter;
        CGAffineTransform mixedTransform;
        videoComposition.frameDuration = CMTimeMake(1, 30);
        
        NSArray *tracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        
        AVMutableVideoCompositionInstruction *roateInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        roateInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, [videoAsset duration]);
        AVMutableVideoCompositionLayerInstruction *roateLayerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
        
        if (degrees == 90) {
            // 顺时针旋转90°
            translateToCenter = CGAffineTransformMakeTranslation(videoTrack.naturalSize.height, 0.0);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI_2);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.height,videoTrack.naturalSize.width);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        } else if(degrees == 180){
            // 顺时针旋转180°
            translateToCenter = CGAffineTransformMakeTranslation(videoTrack.naturalSize.width, videoTrack.naturalSize.height);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.width,videoTrack.naturalSize.height);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        } else if(degrees == 270){
            // 顺时针旋转270°
            translateToCenter = CGAffineTransformMakeTranslation(0.0, videoTrack.naturalSize.width);
            mixedTransform = CGAffineTransformRotate(translateToCenter,M_PI_2*3.0);
            videoComposition.renderSize = CGSizeMake(videoTrack.naturalSize.height,videoTrack.naturalSize.width);
            [roateLayerInstruction setTransform:mixedTransform atTime:kCMTimeZero];
        }
        
        roateInstruction.layerInstructions = @[roateLayerInstruction];
        // 加入视频方向信息
        videoComposition.instructions = @[roateInstruction];
    }
    return videoComposition;
}

/// 获取视频角度
- (int)degressFromVideoFileWithAsset:(AVAsset *)asset {
    int degress = 0;
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if([tracks count] > 0) {
        AVAssetTrack *videoTrack = [tracks objectAtIndex:0];
        CGAffineTransform t = videoTrack.preferredTransform;
        if(t.a == 0 && t.b == 1.0 && t.c == -1.0 && t.d == 0){
            // Portrait
            degress = 90;
        } else if(t.a == 0 && t.b == -1.0 && t.c == 1.0 && t.d == 0){
            // PortraitUpsideDown
            degress = 270;
        } else if(t.a == 1.0 && t.b == 0 && t.c == 0 && t.d == 1.0){
            // LandscapeRight
            degress = 0;
        } else if(t.a == -1.0 && t.b == 0 && t.c == 0 && t.d == -1.0){
            // LandscapeLeft
            degress = 180;
        }
    }
    return degress;
}

/// 修正图片转向
- (UIImage *)fixOrientation:(UIImage *)aImage {
    if (!self.shouldFixOrientation) return aImage;
    
    // No-op if the orientation is already correct
    if (aImage.imageOrientation == UIImageOrientationUp)
        return aImage;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, aImage.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, aImage.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        default:
            break;
    }
    
    switch (aImage.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, aImage.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        default:
            break;
    }
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
    CGContextRef ctx = CGBitmapContextCreate(NULL, aImage.size.width, aImage.size.height,
                                             CGImageGetBitsPerComponent(aImage.CGImage), 0,
                                             CGImageGetColorSpace(aImage.CGImage),
                                             CGImageGetBitmapInfo(aImage.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (aImage.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.height,aImage.size.width), aImage.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,aImage.size.width,aImage.size.height), aImage.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

#pragma clang diagnostic pop

@end


//@implementation TZSortDescriptor
//
//- (id)reversedSortDescriptor {
//    return [NSNumber numberWithBool:![TZImageManager manager].sortAscendingByModificationDate];
//}
//
//@end
