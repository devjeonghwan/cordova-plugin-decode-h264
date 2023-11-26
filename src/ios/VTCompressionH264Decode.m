#import "VTCompressionH264Decode.h"

@interface VTCompressionH264Decode()

@property (strong,nonatomic) NSData *cacheData;
@property (strong,nonatomic) NSData *sps;
@property (strong,nonatomic) NSData *pps;
@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic,strong) NSLock *lock;
@end

@implementation VTCompressionH264Decode


- (instancetype)init
{
    self = [super init];
    if (self) {
        self.cacheData = nil;
        self.sps = nil;
        self.pps = nil;
        self.lock = [NSLock new];
    }
    return self;
}

- (void)decode:(NSData *)decodeData{
    if(decodeData == nil){
        return;
    }
    [self.lock lock];
    NSMutableData *data;
    if (self.cacheData && self.cacheData.length > 0) {
        data =  [[NSMutableData alloc] initWithData:self.cacheData];
        [data appendData:decodeData];
    }else{
        data = [[NSMutableData alloc] initWithData:decodeData];
    }
    self.cacheData = data;
    NSData* naluData = [self findNextNalu];
    while (naluData) {
        char* frameBytes =  (char*)[naluData bytes];

        int nalu_type = (frameBytes[4] & 0x1F);
        if(nalu_type == 7){
            self.sps = [naluData subdataWithRange:NSMakeRange(4, naluData.length - 4)];;
        }else if(nalu_type == 8){
            self.pps = [naluData subdataWithRange:NSMakeRange(4, naluData.length - 4)];;
        }else if(nalu_type == 5){/
            uint32_t dataLength32 = htonl (naluData.length - 4);
            memcpy (frameBytes, &dataLength32, sizeof (uint32_t));
            [self decodeFrame:[NSData dataWithBytes:frameBytes length:naluData.length]];
        }else if(nalu_type == 1){
            uint32_t dataLength32 = htonl (naluData.length - 4);
            memcpy (frameBytes, &dataLength32, sizeof (uint32_t));
            [self decodeFrame:[NSData dataWithBytes:frameBytes length:naluData.length]];
        }
        if(self.sps && self.pps){
            OSStatus status = [self createFromH264ParameterSets];

            if(status != noErr){
                NSLog(@"createFromH264ParameterSets error:%d",status);
            }
        }
        if(self.decompressionSession == NULL && self.formatDesc != NULL){
            OSStatus status = [self createDecompSession];
            if(status != noErr){
                NSLog(@"createDecompSession error:%d",status);
            }
        }

        naluData = [self findNextNalu];
    }
    [self.lock unlock];
}

#pragma mark FIND NEXT Nalu Data
- (NSData *)findNextNalu{
    NSData *data = self.cacheData;
    int startIndex = -1;
    int endIndex = -1;
    char* frameBytes =  (char*)[data bytes];
    for (int i = 0; i < data.length; i ++ ) {
        if(i + 4 < data.length){
            if (frameBytes[i] == 0x00 && frameBytes[i + 1] == 0x00 && frameBytes[i + 2] == 0x00 && frameBytes[ i+3] == 0x01){
                if(startIndex == -1){
                    startIndex = i;
                }else{
                    endIndex = i;
                    break;
                }
            }
        }
    }
    if(startIndex != -1 && endIndex != -1){
        self.cacheData = [self.cacheData subdataWithRange:NSMakeRange(endIndex, self.cacheData.length - endIndex)];
        return [data subdataWithRange:NSMakeRange(startIndex, endIndex - startIndex)];
    }
    return nil;
}

#pragma mark createFromH264ParameterSets
- (OSStatus)createFromH264ParameterSets{
    CMVideoFormatDescriptionRef formatDesc = NULL;
    const uint8_t*  parameterSetPointers[2] = {(const uint8_t*)[self.sps bytes], (const uint8_t*)[self.pps bytes]};
    const size_t parameterSetSizes[2] = {self.sps.length, self.pps.length};
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2,
                                                                parameterSetPointers,
                                                                 parameterSetSizes, 4,
                                                                 &formatDesc);
    if(self.decompressionSession != NULL){
        BOOL needNewDecompSession = (VTDecompressionSessionCanAcceptFormatDescription(_decompressionSession, formatDesc) == NO);
        if(needNewDecompSession){
            VTDecompressionSessionInvalidate(self.decompressionSession);
            self.decompressionSession = NULL;
        }
    }
    self.formatDesc = formatDesc;
    return status;
}

#pragma mark createDecompSession
-(OSStatus) createDecompSession
{
    self.decompressionSession = NULL;
   VTDecompressionOutputCallbackRecord callBackRecord;
   callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;

   callBackRecord.decompressionOutputRefCon = (__bridge void *)self;


    NSDictionary* pixelBufferOptions = @{
                                         (NSString*) kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
                                         };


    return VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDesc, NULL, (__bridge CFDictionaryRef)pixelBufferOptions, &callBackRecord, &_decompressionSession);
}

#pragma mark decodeFrame
-(OSStatus) decodeFrame:(NSData *)frameData{

    CMBlockBufferRef blockBuffer = NULL;

    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, (void *)[frameData bytes],
                                                [frameData length],
                                                kCFAllocatorNull, NULL,
                                                0, 
                                                [frameData length],
                                                0, &blockBuffer);
    if(status != noErr){
        return status;
    }
    const size_t sampleSize = [frameData length];
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                 blockBuffer, true, NULL, NULL,
                                 _formatDesc, 1, 0, NULL, 1,
                                 &sampleSize, &sampleBuffer);
    if(status != noErr){
        return status;
    }

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
    CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);

    VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags flagOut;
    NSDate* currentTime = [NSDate date];
    status = VTDecompressionSessionDecodeFrame(_decompressionSession, sampleBuffer, flags,(void*)CFBridgingRetain(currentTime), &flagOut);
    CFRelease(sampleBuffer);

    return status;

}

- (void)invalidate{
    [self.lock lock];
    if(self.decompressionSession != NULL){
        VTDecompressionSessionWaitForAsynchronousFrames(self.decompressionSession);
    }
    self.formatDesc = NULL;
    self.decompressionSession = NULL;
    self.cacheData = nil;
    self.sps = nil;
    self.pps = nil;
    [self.lock unlock];
}

#pragma mark decompressionSessionDecodeFrameCallback
void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration)
{

    if (status != noErr)
    {
       NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
       NSLog(@"Decompressed error: %@", error);
   }
   else
   {
       VTCompressionH264Decode *decode = (__bridge VTCompressionH264Decode *)decompressionOutputRefCon;
       if(decode.delegate){
           [decode.delegate imageBufferCallBack:imageBuffer];
       }
   }
}
@end
