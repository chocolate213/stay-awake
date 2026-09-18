#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>

typedef struct {
    UInt8 red;
    UInt8 green;
    UInt8 blue;
    UInt8 alpha;
} Pixel;

static CGImageRef CreatePreparedIconImage(NSURL *sourceURL, size_t pixels) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)sourceURL, NULL);
    if (!source) {
        return NULL;
    }

    CGImageRef sourceImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!sourceImage) {
        return NULL;
    }

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    Pixel *buffer = calloc(pixels * pixels, sizeof(Pixel));
    CGContextRef context = CGBitmapContextCreate(buffer, pixels, pixels, 8, pixels * sizeof(Pixel), space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!buffer || !context) {
        CGImageRelease(sourceImage);
        free(buffer);
        if (context) CGContextRelease(context);
        return NULL;
    }

    size_t sourceWidth = CGImageGetWidth(sourceImage);
    size_t sourceHeight = CGImageGetHeight(sourceImage);
    size_t side = MIN(sourceWidth, sourceHeight);
    CGRect crop = CGRectMake((CGFloat)(sourceWidth - side) / 2.0, (CGFloat)(sourceHeight - side) / 2.0, side, side);
    CGImageRef croppedImage = CGImageCreateWithImageInRect(sourceImage, crop);
    CGImageRelease(sourceImage);
    if (!croppedImage) {
        CGContextRelease(context);
        free(buffer);
        return NULL;
    }

    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    // Inset the Composer render within the legacy macOS icon canvas.
    CGFloat artworkScale = 0.82;
    CGFloat drawSize = (CGFloat)pixels * artworkScale;
    CGFloat drawOrigin = ((CGFloat)pixels - drawSize) / 2.0;
    CGRect drawRect = CGRectMake(drawOrigin, drawOrigin, drawSize, drawSize);
    CGContextDrawImage(context, drawRect, croppedImage);
    CGImageRelease(croppedImage);

    CGImageRef outputImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    free(buffer);
    return outputImage;
}

static BOOL WritePNG(CGImageRef image, NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.png"), 1, NULL);
    if (!destination) {
        return NO;
    }

    CGImageDestinationAddImage(destination, image, NULL);
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return success;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: prepare_app_icon SOURCE_PNG OUTPUT_ICONSET_DIR\n");
            return 64;
        }

        NSURL *sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSString *outputDir = [NSString stringWithUTF8String:argv[2]];

        NSFileManager *fileManager = NSFileManager.defaultManager;
        [fileManager removeItemAtPath:outputDir error:nil];
        if (![fileManager createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:nil]) {
            fprintf(stderr, "failed to create iconset directory\n");
            return 1;
        }

        NSDictionary<NSString *, NSNumber *> *files = @{
            @"icon_16x16.png": @16,
            @"icon_16x16@2x.png": @32,
            @"icon_32x32.png": @32,
            @"icon_32x32@2x.png": @64,
            @"icon_128x128.png": @128,
            @"icon_128x128@2x.png": @256,
            @"icon_256x256.png": @256,
            @"icon_256x256@2x.png": @512,
            @"icon_512x512.png": @512,
            @"icon_512x512@2x.png": @1024,
        };

        for (NSString *filename in files) {
            size_t pixels = (size_t)files[filename].integerValue;
            CGImageRef image = CreatePreparedIconImage(sourceURL, pixels);
            if (!image) {
                fprintf(stderr, "failed to prepare %s\n", filename.UTF8String);
                return 1;
            }

            NSString *path = [outputDir stringByAppendingPathComponent:filename];
            BOOL success = WritePNG(image, path);
            CGImageRelease(image);

            if (!success) {
                fprintf(stderr, "failed to write %s\n", filename.UTF8String);
                return 1;
            }
        }
    }

    return 0;
}
