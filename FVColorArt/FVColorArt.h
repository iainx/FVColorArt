//
//  FVColorArt.h
//  CoverArtPlayground
//
//  Created by iain on 29/07/2014.
//  Copyright (c) 2014 False Victories. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FVColorArt : NSObject

@property (readonly, strong) NSColor *backgroundColor;
@property (readonly, strong) NSColor *primaryColor;
@property (readonly, strong) NSColor *secondaryColor;
@property (readonly, strong) NSColor *detailColor;

- (void)analysisImage:(NSImage *)image;

@end
