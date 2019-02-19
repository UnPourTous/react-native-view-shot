#import "RNViewShot.h"
#import <AVFoundation/AVFoundation.h>
#import <React/RCTLog.h>
#import <React/UIView+React.h>
#import <React/RCTUtils.h>
#import <React/RCTConvert.h>
#import <React/RCTScrollView.h>
#import <React/RCTUIManager.h>
#if __has_include(<React/RCTUIManagerUtils.h>)
#import <React/RCTUIManagerUtils.h>
#endif
#import <React/RCTBridge.h>
#import <Photos/Photos.h>

@implementation RNViewShot

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (dispatch_queue_t)methodQueue
{
  return RCTGetUIManagerQueue();
}

RCT_EXPORT_METHOD(captureScreen: (NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) 
{
  [self captureRef: [NSNumber numberWithInt:-1] withOptions:options resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(releaseCapture:(nonnull NSString *)uri)
{
  NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ReactNative"];
  // Ensure it's a valid file in the tmp directory
  if ([uri hasPrefix:directory] && ![uri isEqualToString:directory]) {
    NSFileManager *fileManager = [NSFileManager new];
    if ([fileManager fileExistsAtPath:uri]) {
      [fileManager removeItemAtPath:uri error:NULL];
    }
  }
}

RCT_EXPORT_METHOD(captureRefList:(NSDictionary *)viewRef
                  withOptions:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    NSArray* targetList = [RCTConvert NSArray:viewRef[@"viewRefArr"]];
    [self doCapture:targetList withOptions:options resolve:resolve reject:reject];
}

RCT_EXPORT_METHOD(captureRef:(nonnull NSNumber *)target
                  withOptions:(NSDictionary *)options
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    [self doCapture:@[target] withOptions:options resolve:resolve reject:reject];
}

- (void)doCapture:(NSArray *)targetList
            withOptions:(NSDictionary *)options
            resolve:(RCTPromiseResolveBlock)resolve
            reject:(RCTPromiseRejectBlock)reject
{
    if (!targetList || [targetList count] == 0) {
        reject(RCTErrorUnspecified, @"parma error", nil);
        return;
    }

    [self.bridge.uiManager addUIBlock:^(__unused RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
        // Get options
        NSString *format = [RCTConvert NSString:options[@"format"]];
        NSString *result = [RCTConvert NSString:options[@"result"]];
        NSString *backgroundColor = [options objectForKey:@"backgroundColor"];
        BOOL snapshotContentContainer = [RCTConvert BOOL:options[@"snapshotContentContainer"]];
        BOOL saveToPhotosAlbum = [RCTConvert BOOL:options[@"saveToPhotosAlbum"]];

        UIImage *lastImage = nil;
        for (NSInteger i = 0; i < [targetList count]; i++) {
            NSNumber* target = targetList[i];
            // Get view
            UIView *view;
            if ([target intValue] == -1) {
                UIWindow *window = [[UIApplication sharedApplication] keyWindow];
                view = window.rootViewController.view;
            } else {
                view = viewRegistry[target];
            }
            
            if (!view) {
                reject(RCTErrorUnspecified, [NSString stringWithFormat:@"No view found with reactTag: %@", target], nil);
                return;
            }
            
            // Capture image
            BOOL success;
            
            UIView* rendered;
            UIScrollView* scrollView;
            bool isScrollView = snapshotContentContainer && [view isKindOfClass:[RCTScrollView class]];
            if (isScrollView) {
                RCTScrollView* rctScrollView = (RCTScrollView *)view;
                scrollView = rctScrollView.scrollView;
                rendered = scrollView;
            }
            else {
                rendered = view;
            }

            CGSize size = CGSizeMake(0, 0);
            if (size.width < 0.1 || size.height < 0.1) {
                size = isScrollView ? scrollView.contentSize : view.bounds.size;
            }
            if (size.width < 0.1 || size.height < 0.1) {
                reject(RCTErrorUnspecified, [NSString stringWithFormat:@"The content size must not be zero or negative. Got: (%g, %g)", size.width, size.height], nil);
                return;
            }
            
            CGPoint savedContentOffset;
            CGRect savedFrame;
            if (isScrollView) {
                // Save scroll & frame and set it temporarily to the full content size
                savedContentOffset = scrollView.contentOffset;
                savedFrame = scrollView.frame;
                scrollView.contentOffset = CGPointZero;
                scrollView.frame = CGRectMake(0, 0, scrollView.contentSize.width, scrollView.contentSize.height);
            }
            
            UIGraphicsBeginImageContextWithOptions(size, NO, 0);
            
            success = [rendered drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:YES];
            UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
            if (isScrollView) {
                // Restore scroll & frame
                scrollView.contentOffset = savedContentOffset;
                scrollView.frame = savedFrame;
            }
            
            if (!success) {
                reject(RCTErrorUnspecified, @"The view cannot be captured. drawViewHierarchyInRect was not successful. This is a potential technical or security limitation.", nil);
                return;
            }
            
            if (!image) {
                reject(RCTErrorUnspecified, @"Failed to capture view snapshot. UIGraphicsGetImageFromCurrentImageContext() returned nil!", nil);
                return;
            }
    
            if (lastImage == nil) {
                lastImage = image;
            } else {
                CGSize size = CGSizeMake(lastImage.size.width, lastImage.size.height + image.size.height);
                UIGraphicsBeginImageContext(size);
                [lastImage drawInRect:CGRectMake(0, 0, size.width, lastImage.size.height)];
                [image drawInRect:CGRectMake(0, lastImage.size.height, size.width, image.size.height)];
                UIImage *togetherImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                lastImage = togetherImage;
            }
        }
        
        UIColor* color = [self colorWithHexString:(backgroundColor != nil ? backgroundColor : @"#f7f7f7") alpha:1.0];
        lastImage = [self setBackgroundColor:lastImage withColor:color];

        if (saveToPhotosAlbum) {
            UIImageWriteToSavedPhotosAlbum(lastImage, self, @selector(image:didFinishSavingWithError:contextInfo:), nil);
//            [self loadImageFinished:lastImage];
        }

        // Convert image to data (on a background thread)
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSData *data;
            if ([format isEqualToString:@"jpg"]) {
                CGFloat quality = [RCTConvert CGFloat:options[@"quality"]];
                data = UIImageJPEGRepresentation(lastImage, quality);
            }
            else {
                data = UIImagePNGRepresentation(lastImage);
            }
            
            NSError *error = nil;
            NSString *res = nil;
            if ([result isEqualToString:@"base64"]) {
                // Return as a base64 raw string
                res = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
            }
            else if ([result isEqualToString:@"data-uri"]) {
                // Return as a base64 data uri string
                NSString *base64 = [data base64EncodedStringWithOptions: NSDataBase64Encoding64CharacterLineLength];
                NSString *imageFormat = ([format isEqualToString:@"jpg"]) ? @"jpeg" : format;
                res = [NSString stringWithFormat:@"data:image/%@;base64,%@", imageFormat, base64];
            }
            else {
                // Save to a temp file
                NSString *path = RCTTempFilePath(format, &error);
                if (path && !error) {
                    if ([data writeToFile:path options:(NSDataWritingOptions)0 error:&error]) {
                        res = path;
                    }
                }
            }
            
            if (res && !error) {
                resolve(res);
                return;
            }
            
            // If we reached here, something went wrong
            if (error) reject(RCTErrorUnspecified, error.localizedDescription, error);
            else reject(RCTErrorUnspecified, @"viewshot unknown error", nil);
        });
    }];
}

//- (void)loadImageFinished:(UIImage *)image
//{
//    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//        // 写入图片到相册
//        PHAssetChangeRequest *req = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
//    } completionHandler:^(BOOL success, NSError * _Nullable error) {
//        NSLog(@"success = %d, error = %@", success, error);
//    }];
//}

- (UIImage *)setBackgroundColor:(UIImage *)image withColor:(UIColor *)color
{
    CGRect rect = CGRectMake(0.0f, 0.0f, image.size.width, image.size.height);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    CGContextFillRect(context, rect);

    [image drawInRect:rect];
    UIImage*newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newImage;
}

//必要实现的协议方法, 不然会崩溃
- (void)image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    NSLog(@"image = %@, error = %@, contextInfo = %@", image, error, contextInfo);
}

- (UIColor *) colorWithHexString: (NSString *)color alpha:(float)opacity
{
    NSString *cString = [[color stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    
    // String should be 6 or 8 characters
    if ([cString length] < 6) {
        return [UIColor clearColor];
    }
    
    // 判断前缀并剪切掉
    if ([cString hasPrefix:@"0X"])
        cString = [cString substringFromIndex:2];
    if ([cString hasPrefix:@"#"])
        cString = [cString substringFromIndex:1];
    if ([cString length] != 6)
        return [UIColor clearColor];
    
    // 从六位数值中找到RGB对应的位数并转换
    NSRange range;
    range.location = 0;
    range.length = 2;
    
    //R、G、B
    NSString *rString = [cString substringWithRange:range];
    
    range.location = 2;
    NSString *gString = [cString substringWithRange:range];
    
    range.location = 4;
    NSString *bString = [cString substringWithRange:range];
    
    // Scan values
    unsigned int r, g, b;
    [[NSScanner scannerWithString:rString] scanHexInt:&r];
    [[NSScanner scannerWithString:gString] scanHexInt:&g];
    [[NSScanner scannerWithString:bString] scanHexInt:&b];
    
    return [UIColor colorWithRed:((float) r / 255.0f) green:((float) g / 255.0f) blue:((float) b / 255.0f) alpha:opacity];
}

@end
