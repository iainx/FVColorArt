//
//  FVColorArt.m
//  CoverArtPlayground
//
//  Created by iain on 29/07/2014.
//  Copyright (c) 2014 False Victories. All rights reserved.
//

// Based on code from Panic Inc.

//  Created by Aaron Brethorst on 12/11/12.
//
// Copyright (C) 2012 Panic Inc. Code by Wade Cosgrove. All rights reserved.
//
// Redistribution and use, with or without modification, are permitted provided that the following conditions are met:
//
// - Redistributions must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
//
// - Neither the name of Panic Inc nor the names of its contributors may be used to endorse or promote works derived from this software without specific prior written permission from Panic Inc.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL PANIC INC BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <QuartzCore/QuartzCore.h>
#import "FVColorArt.h"

@interface FVColorArt ()

@property (readwrite, nonatomic) NSImage *pixelatedImage;
@property (readwrite, strong) NSColor *backgroundColor;
@property (readwrite, strong) NSColor *primaryColor;
@property (readwrite, strong) NSColor *secondaryColor;
@property (readwrite, strong) NSColor *detailColor;

@end

// We squash the 8bit RGBA values into 1 32bit value
// Then we shift that into a 64bit value where the most significant 32 bits are the RGBA values
// and the lower bits are the number of times that colour has appeared in the image
typedef UInt64 CountedColor;
typedef UInt32 SquashedColor;
#define SQUASH_RGBA(r, g, b, a) ((SquashedColor)((unsigned char)r << 24 | (unsigned char)g << 16 | (unsigned char)b << 8 | (unsigned char)a))
#define UNSQUASH_R(v) (v >> 24)
#define UNSQUASH_G(v) ((v & (0xFF << 16)) >> 16)
#define UNSQUASH_B(v) ((v & (0xFF << 8)) >> 8)
#define UNSQUASH_A(v) (v & 0xFF)

#define UNSQUASH_R_F(v) ((v >> 24) / 255.)
#define UNSQUASH_G_F(v) (((v & (0xFF << 16)) >> 16) / 255.)
#define UNSQUASH_B_F(v) (((v & (0xFF << 8)) >> 8) / 255.)
#define UNSQUASH_A_F(v) ((v & 0xFF) / 255.)

#define TAG(v) (((CountedColor)v) << 32)
#define UNTAG_RGBA(v) ((SquashedColor)(v >> 32))
#define UNTAG_COUNT(v) ((UInt32)v)

#define LUMINENCE_FROM_RGBA(v) (0.2126 * UNSQUASH_R_F(v) + 0.7152 * UNSQUASH_G_F(v) + 0.0722 * UNSQUASH_B_F(v))

#define GET_PIXEL_AT_XY(data, x, y, rowSpan) (data + (x * 4) + (y * rowSpan))

@implementation FVColorArt

static CGFloat pixelSize = 10.0;
- (NSBitmapImageRep *)RGBABitmapImageRepWithCImage:(CIImage *)ciImage
{
    int width = [ciImage extent].size.width;
    int rows = [ciImage extent].size.height;
    int rowBytes = (width * 4);
    
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                    pixelsWide:width
                                                                    pixelsHigh:rows
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bitmapFormat:0
                                                                   bytesPerRow:rowBytes
                                                                  bitsPerPixel:0];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName (kCGColorSpaceGenericRGB);
    CGContextRef context = CGBitmapContextCreate([rep bitmapData], width, rows,
                                                 8, rowBytes, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    
    CIContext* ciContext = [CIContext contextWithCGContext:context options:@{kCIContextUseSoftwareRenderer: @YES}];
    [ciContext drawImage:ciImage inRect:CGRectMake(0, 0, width, rows) fromRect:[ciImage extent]];
    ciContext = nil;
    
 	CGContextRelease( context );
	CGColorSpaceRelease( colorSpace );
    
	return rep;
}

- (void)analysisImage:(NSImage *)image
{
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:NULL hints:NULL];
    CIImage *inputImage = [[CIImage alloc] initWithCGImage:cgImage];

    CGSize size = inputImage.extent.size;
    
    if (size.width > 600 || size.height > 600) {
        CGFloat ratio;
        
        if (size.width > size.height) {
            ratio = 600.0 / size.width;
        } else {
            ratio = 600.0 / size.height;
        }
        inputImage = [inputImage imageByApplyingTransform:CGAffineTransformMakeScale(ratio, ratio)];
    }

    // Square the image
    CGRect squaredRect;
    
    CGRect extent = inputImage.extent;
    if (extent.size.width > extent.size.height) {
        CGFloat midX = NSMidX(extent);
        squaredRect = CGRectMake(midX - (extent.size.width / 2), 0, extent.size.width, extent.size.height);
    } else {
        CGFloat midY = NSMidY(extent);
        squaredRect = CGRectMake(0, midY - (extent.size.height / 2), extent.size.width, extent.size.height);
    }
    
    inputImage = [inputImage imageByCroppingToRect:squaredRect];
    
    [self analyseCIImage:inputImage];
}

- (void)analyseCIImage:(CIImage *)inputImage
{
    CIImage *outputImage;
    
    CGSize size = inputImage.extent.size;
    pixelSize = roundf(size.width / 50);
    if (pixelSize < 1) {
        NSLog(@"Unusable pixel size: %f for %@", pixelSize, NSStringFromSize(size));
        return;
    }
    
    if (pixelSize > 1.0) {
        CIFilter *filter = [CIFilter filterWithName:@"CIPixellate"];
        [filter setDefaults];
        [filter setValue:inputImage forKey:kCIInputImageKey];
        
        [filter setValue:[CIVector vectorWithX:0 Y:0] forKey:kCIInputCenterKey];
        [filter setValue:@(pixelSize) forKey:@"inputScale"];
        outputImage = [filter valueForKey:kCIOutputImageKey];
        
        outputImage = [outputImage imageByCroppingToRect:[inputImage extent]];
    } else {
        outputImage = inputImage;
    }
    
    NSBitmapImageRep *rep = [self RGBABitmapImageRepWithCImage:outputImage];
    
    [self.pixelatedImage addRepresentation:rep];
}

#define GET_PIXEL_AT_XY(data, x, y, rowSpan) (data + (x * 4) + (y * rowSpan))
- (void)coloursFromImageRep:(NSBitmapImageRep *)rep
{
    unsigned char *bitmapData = [rep bitmapData];
    NSInteger bytesPerRow = [rep bytesPerRow];
    
    CountedColor *backgroundColors, *imageColors;
    NSUInteger backgroundCount, imageCount;

    [self generateBackgroundColors:&backgroundColors
                   backgroundCount:&backgroundCount
                     forBitmapData:bitmapData
                             width:[rep pixelsWide]
                            height:[rep pixelsHigh]
                           rowSpan:bytesPerRow];
    
    // We find the background colour first before generating the foregroundColors array
    // because this allows the foregroundColors to filter out any that we know won't be used
    // saving a bit of time for the sorting
    SquashedColor backgroundRGBA;
    self.backgroundColor = [self backgroundColorFromColors:backgroundColors count:backgroundCount rgba:&backgroundRGBA];

	NSColor *primaryColor = nil;
	NSColor *secondaryColor = nil;
	NSColor *detailColor = nil;
    
    if (self.backgroundColor == nil) {
        return;
    }

    [self generateForegroundColors:&imageColors
                   foregroundCount:&imageCount
                     forBitmapData:bitmapData
                        pixelsWide:[rep pixelsWide]
                        pixelsHigh:[rep pixelsHigh]
                           rowSpan:bytesPerRow
                withBackgroundRGBA:backgroundRGBA];
    
    [self findPrimaryColor:&primaryColor
            secondaryColor:&secondaryColor
               detailColor:&detailColor
                fromColors:imageColors
                     count:imageCount
       withBackgroundColor:backgroundRGBA];
    
    free(backgroundColors);
    free(imageColors);
    
    BOOL darkBackground = isDarkColor(backgroundRGBA);
	if ( primaryColor == nil )
	{
		//NSLog(@"missed primary");
		if ( darkBackground )
			primaryColor = [NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1];
		else
			primaryColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
	}
    
	if ( secondaryColor == nil )
	{
	//	NSLog(@"missed secondary");
		if ( darkBackground )
			secondaryColor = [NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1];
		else
			secondaryColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
	}
    
	if ( detailColor == nil )
	{
	//	NSLog(@"missed detail");
		if ( darkBackground )
			detailColor = [NSColor colorWithCalibratedRed:1 green:1 blue:1 alpha:1];
		else
			detailColor = [NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1];
	}
    
    self.primaryColor = primaryColor;
	self.secondaryColor = secondaryColor;
    self.detailColor = detailColor;
}


static NSColor *
colorFromSquashedRGBA(SquashedColor rgba)
{
    NSColor *color = [NSColor colorWithCalibratedRed:UNSQUASH_R(rgba) / 255.
                                               green:UNSQUASH_G(rgba) / 255.
                                                blue:UNSQUASH_B(rgba) / 255.
                                               alpha:UNSQUASH_A(rgba) / 255.];
    return color;
}

static int
compare_tagged_ints_reversed (const void *a_pointer,
                              const void *b_pointer)
{
    CountedColor tagged_a = *(CountedColor *)a_pointer;
    CountedColor tagged_b = *(CountedColor *)b_pointer;
    UInt32 a = UNTAG_COUNT(tagged_a);
    UInt32 b = UNTAG_COUNT(tagged_b);
    
    // Returns inverted as we want to sort biggest first
    if (a < b) {
        return 1;
    } else if (a > b) {
        return -1;
    } else {
        return 0;
    }
}

static void
fillArrayFromMapTable(NSMapTable *mapTable,
                      CountedColor **array)
{
    int count = 0;
    void *key, *value;
    NSMapEnumerator mapEnumerator = NSEnumerateMapTable(mapTable);
    while (NSNextMapEnumeratorPair(&mapEnumerator, &key, &value)) {
        (*array)[count++] = (CountedColor)value;
    }

    qsort(*array, count, sizeof(CountedColor), compare_tagged_ints_reversed);
}

static void
insertIntoMapOrIncrement(NSMapTable *mapTable,
                         SquashedColor key)
{
    UInt64 key64 = (UInt64)key;
    void *value;
    
    value = NSMapGet(mapTable, (const void *)key64);
    if (value == NULL) {
        // Create a CountedColor with an initial value of 1
        CountedColor taggedValue = TAG(key) + 1;
        
        NSMapInsert(mapTable, (const void *)key64, (const void *)taggedValue);
    } else {
        CountedColor taggedValue = (CountedColor)value;
        taggedValue++;
        
        NSMapInsert(mapTable, (const void *)key64, (const void *)taggedValue);
    }
}

- (void)generateBackgroundColors:(CountedColor **)backgroundColors
                 backgroundCount:(NSUInteger *)backgroundCount
                   forBitmapData:(unsigned char *)bitmapData
                           width:(NSInteger)pixelsWide
                          height:(NSInteger)pixelsHigh
                         rowSpan:(NSInteger)rowSpan
{
    *backgroundCount = 0;

    NSMapTable *backgroundMap = NSCreateMapTable(NSIntegerMapKeyCallBacks,
                                                 NSIntegerMapValueCallBacks,
                                                 pixelsHigh / pixelSize);
    
    // Only doing the left edge, means X is always 0
    for (NSUInteger y = 0; y < pixelsHigh; y += pixelSize) {
        unsigned char r, g, b, a;
        unsigned char *pixel = GET_PIXEL_AT_XY(bitmapData, 0, y, rowSpan);
        
        r = *(pixel);
        g = *(pixel + 1);
        b = *(pixel + 2);
        a = *(pixel + 3);
        
        if (a != 255) {
            continue;
        }
        
        // Squash the rgba values into one value
        // assuming 8bpp
        SquashedColor squashed = SQUASH_RGBA(r, g, b, a);
        insertIntoMapOrIncrement(backgroundMap, squashed);
    }
    
    *backgroundCount = NSCountMapTable(backgroundMap);
    
    CountedColor *backgroundArray;
    
    backgroundArray = malloc(sizeof(CountedColor) * (*backgroundCount));
    fillArrayFromMapTable(backgroundMap, &backgroundArray);
    NSFreeMapTable(backgroundMap);
    
    *backgroundColors = backgroundArray;
}

- (void)generateForegroundColors:(CountedColor **)foregroundColors
                 foregroundCount:(NSUInteger *)foregroundCount
                   forBitmapData:(unsigned char *)bitmapData
                      pixelsWide:(NSInteger)pixelsWide
                      pixelsHigh:(NSInteger)pixelsHigh
                         rowSpan:(NSInteger)rowSpan
              withBackgroundRGBA:(SquashedColor)backgroundRGBA
{
    BOOL backgroundIsDark = isDarkColor(backgroundRGBA);
    BOOL lookingForDarkColor = !backgroundIsDark;
    *foregroundCount = 0;
    
    NSMapTable *foregroundMap = NSCreateMapTable(NSIntegerMapKeyCallBacks,
                                                 NSIntegerMapValueCallBacks,
                                                 (pixelsWide * pixelsHigh) / (pixelSize * pixelSize));
    
    for ( NSUInteger x = 0; x < pixelsWide; x += pixelSize ) {
        for ( NSUInteger y = 0; y < pixelsHigh; y += pixelSize ) {
            unsigned char r, g, b, a;
            unsigned char *pixel = GET_PIXEL_AT_XY(bitmapData, x, y, rowSpan);
            
            r = *(pixel);
            g = *(pixel + 1);
            b = *(pixel + 2);
            a = *(pixel + 3);
            
            if (a != 255) {
                continue;
            }
     
            // Squash the rgba values into one value
            // assuming 8bpp
            SquashedColor squashed = SQUASH_RGBA(r, g, b, a);
     
            if (!isContrastingColor(backgroundRGBA, squashed)) {
                continue;
            }
            
            if (isDarkColor(squashed) != lookingForDarkColor) {
                continue;
            }
            
            SquashedColor minSatColor = colorWithMinimumSaturation(squashed, 0.15);
            insertIntoMapOrIncrement(foregroundMap, minSatColor);
        }
    }
    
    *foregroundCount = NSCountMapTable(foregroundMap);
    
    CountedColor *foregroundArray;
    
    foregroundArray = malloc(sizeof(CountedColor) * (*foregroundCount));
    fillArrayFromMapTable(foregroundMap, &foregroundArray);
    NSFreeMapTable(foregroundMap);
    
    *foregroundColors = foregroundArray;
}

- (NSColor *)backgroundColorFromColors:(CountedColor *)colors
                                 count:(NSUInteger)count
                                  rgba:(SquashedColor *)backgroundRGBA
{
    NSUInteger proposedColor = colors[0];
    SquashedColor rgba = UNTAG_RGBA(proposedColor);
    
    // Don't really want a black/white background
    if (!isBlackOrWhite(rgba)) {
        *backgroundRGBA = rgba;
        return colorFromSquashedRGBA(rgba);
    }
    
    NSUInteger proposedCount = UNTAG_COUNT(proposedColor);
    // Iterate over the colours looking for one that isn't black or white
    for (NSInteger i = 1; i < count; i++) {
        NSUInteger nextColor = colors[i];
        // Want a colour that is at least 30% as popular as the original colour
        if (((double)UNTAG_COUNT(nextColor) / (double)proposedCount) > .3) {
            rgba = UNTAG_RGBA(colors[i]);
            if (!isBlackOrWhite(rgba)) {
                *backgroundRGBA = rgba;
                return colorFromSquashedRGBA(rgba);
            }
        }
    }
 
    // Couldn't find a better colour than the original.
    *backgroundRGBA = UNTAG_RGBA(proposedColor);
	return colorFromSquashedRGBA(*backgroundRGBA);
}

- (void)findPrimaryColor:(NSColor **)primaryColor
          secondaryColor:(NSColor **)secondaryColor
             detailColor:(NSColor **)detailColor
              fromColors:(CountedColor *)colors
                   count:(NSUInteger)count
     withBackgroundColor:(SquashedColor)rgba
{
    SquashedColor pRGBA = 0, sRGBA = 0;
    
    for (NSInteger i = 0; i < count; i++) {
        SquashedColor proposedRGBA = UNTAG_RGBA(colors[i]);
        
        if (*primaryColor == nil) {
            *primaryColor = colorFromSquashedRGBA(proposedRGBA);
            pRGBA = proposedRGBA;
        } else if (*secondaryColor == nil) {
            if (isDistinctColor(pRGBA, proposedRGBA)) {
                *secondaryColor = colorFromSquashedRGBA(proposedRGBA);
                sRGBA = proposedRGBA;
            }
        } else {
            if (isDistinctColor(pRGBA, proposedRGBA) && isDistinctColor(sRGBA, proposedRGBA)) {
                *detailColor = colorFromSquashedRGBA(proposedRGBA);
                return;
            }
        }
    }
}

static bool
isBlackOrWhite(SquashedColor rgba)
{
    int r, g, b;
    
    r = UNSQUASH_R(rgba);
    g = UNSQUASH_G(rgba);
    b = UNSQUASH_B(rgba);
    
    if ( r > .91 && g > .91 && b > .91 )
        return YES; // white
    
    if ( r < .09 && g < .09 && b < .09 )
        return YES; // black
    
    return NO;
}

static bool
isDarkColor(SquashedColor rgba)
{
    CGFloat lum = LUMINENCE_FROM_RGBA(rgba);
    
	if (lum < .5) {
		return YES;
	}
    
	return NO;
}

static bool
isDistinctColor(SquashedColor rgba1, SquashedColor rgba2)
{
	CGFloat threshold = .25; //.15
    
    CGFloat r1 = UNSQUASH_R_F(rgba1), r2 = UNSQUASH_R_F(rgba2);
    CGFloat g1 = UNSQUASH_G_F(rgba1), g2 = UNSQUASH_G_F(rgba2);
    CGFloat b1 = UNSQUASH_B_F(rgba1), b2 = UNSQUASH_B_F(rgba2);
    CGFloat a1 = UNSQUASH_A_F(rgba1), a2 = UNSQUASH_A_F(rgba2);
    
	if (fabs(r1 - r2) > threshold ||
		fabs(g1 - g2) > threshold ||
		fabs(b1 - b2) > threshold ||
		fabs(a1 - a2) > threshold ) {
        // check for grays, prevent multiple gray colors
        
        if (fabs(r1 - g1) < .03 && fabs(r1 - b1) < .03) {
            if (fabs(r2 - g2) < .03 && fabs(r2 - b2) < .03) {
                return NO;
            }
        }
        
        return YES;
    }
    
	return NO;
}

static bool
isContrastingColor(SquashedColor rgba1, SquashedColor rgba2)
{
    CGFloat lum1 = LUMINENCE_FROM_RGBA(rgba1);
    CGFloat lum2 = LUMINENCE_FROM_RGBA(rgba2);
    CGFloat contrast = 0.;
    
    if ( lum1 > lum2 )
        contrast = (lum1 + 0.05) / (lum2 + 0.05);
    else
        contrast = (lum2 + 0.05) / (lum1 + 0.05);
    
    //return contrast > 3.0; //3-4.5 W3C recommends 3:1 ratio, but that filters too many colors
    //NSLog(@"contrast: %f", contrast);
    return contrast > 1.6;
}

static void
squashedRGBToHSB(SquashedColor rgba, CGFloat *h, CGFloat *s, CGFloat *br)
{
    CGFloat r, g, b;
    
    r = UNSQUASH_R_F(rgba);
    g = UNSQUASH_G_F(rgba);
    b = UNSQUASH_B_F(rgba);
    
    CGFloat maxValue = MAX(r, MAX(g, b));
    CGFloat minValue = MIN(r, MIN(g, b));
    CGFloat delta = maxValue - minValue;
    
    // Brightness is max
    *br = maxValue;
    
    *s = maxValue != 0.0 ? ((CGFloat)delta / *br) : 0.0;
    
    if (*s == 0) {
        *h = 0;
        return;
    }
    
    if (maxValue == r) {
        *h = (g - b) / delta;
    } else if (maxValue == g) {
        *h = 2 + (b - r) / delta;
    } else {
        *h = 4 + (r - g) / delta;
    }
    
    *h *= 60;
    if (*h < 0) {
        *h += 360;
    }
}

static SquashedColor
HSBToSquashedRGB(CGFloat h, CGFloat s, CGFloat br)
{
    CGFloat r = 0.0, g = 0.0, b = 0.0;
    
    if (h == 360) {
        h = 0;
    }
    
    h /= 60;
    
    if (s == 0) {
        // return Black with full alpha
        return 0xFF;
    }
    
    CGFloat f, p, q, t;
    int i = floorf(h);
    
    f = h - i;
    p = br * (1.0 - s);
    q = br * (1.0 - (s * f));
    t = br * (1.0 - (s * (1.0 - f)));
    
    switch (i) {
        case 0: r = br; g = t; b = p; break;
        case 1: r = q; g = br; b = p; break;
        case 2: r = p; g = br; b = t; break;
        case 3: r = p; g = q; b = br; break;
        case 4: r = t; g = p; b = br; break;
        case 5: r = br; g = p; b = q; break;
            
        default:
            return 0xFF;
    }
    
    return SQUASH_RGBA(r * 255, g * 255, b * 255, 255);
}

static SquashedColor
colorWithMinimumSaturation(SquashedColor rgba, CGFloat minSaturation)
{
    CGFloat h, s, b;
    
    squashedRGBToHSB(rgba, &h, &s, &b);
    
    if (s < minSaturation) {
        return HSBToSquashedRGB(h, minSaturation, b);
    }
    
    return rgba;
}

static NSString *stringFromSquashedRGBA(SquashedColor rgba)
{
    return [NSString stringWithFormat:@"%u : %u : %u : %u", UNSQUASH_R(rgba), UNSQUASH_G(rgba), UNSQUASH_B(rgba), UNSQUASH_A(rgba)];
}

@end