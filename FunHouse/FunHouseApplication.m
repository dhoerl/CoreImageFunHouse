/*
     File: FunHouseApplication.m
 Abstract: This is a subclass of NSApplication we subclass so we can get ahold of the escape key for full screen mode swap.
  Version: 2.1
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2014 Apple Inc. All Rights Reserved.
 
 */

#import "FunHouseApplication.h"
#import "FunHouseAppDelegate.h"


@implementation FunHouseApplication

- (void)awakeFromNib
{
    // fetch textures now
    // provide a set of "standard" images used to fill in filter CIImage parameters
    // see the EffectStackController setAutomaticDefaults: method
    // a texture - used for CIGlassDistortion
    _texturepath = [NSBundle.mainBundle pathForResource:@"smoothtexture" ofType: @"tiff"];
    // a material map used for shading - used for CIShadedMaterial
    _shadingemappath = [NSBundle.mainBundle pathForResource:@"lightball" ofType: @"tiff"];
    // a material map with alpha that's not all 1 - used for CIRippleTransition
    _alphaemappath = [NSBundle.mainBundle pathForResource:@"restrictedshine" ofType: @"tiff"];
    // color ramp - a width "n" height 1 image - used for CIColorMap
    _ramppath = [NSBundle.mainBundle pathForResource:@"colormap" ofType: @"tiff"];
    // mask (grayscale image) used for CIDisintegrateWithMaskTransition
    _maskpath = [NSBundle.mainBundle pathForResource:@"mask" ofType: @"tiff"];
}

// this procedure allows us to intercept the escape key (for full screen zoom)
- (void)sendEvent:(NSEvent *)event
{
    if (event.type == NSEventTypeKeyDown)
    {
        NSString *str = event.characters;
        if ([str characterAtIndex:0] == 0x1B) // escape
        {
            [(FunHouseAppDelegate*)[self delegate] zoomToFullScreenAction:self];
            return;
        }
    }
    [super sendEvent:event];
}

// method used to set the title of the "full screen" menu item
// (depends on the current state)
- (void)setFullScreenMenuTitle:(BOOL)inFullScreen
{
    [zoomToFullScreenMenuItem setTitle:inFullScreen ? @"Exit Full Screen" : @"Zoom To Full Screen"];
}

// accessors for default images (and their paths) for filters
// load the images only on demand to keep launch time down
- (CIImage *)defaultTexture
{
    if (_texture == NULL)
        _texture = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:self.texturepath]];
    return _texture;
}

- (NSString *)defaultTexturePath
{
    return _texturepath;
}

- (CIImage *)defaultShadingEMap
{
    if(_shadingemap == NULL)
        _shadingemap = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:_shadingemappath]];
    return _shadingemap;
}

- (NSString *)defaultShadingEMapPath
{
    return _shadingemappath;
}

- (CIImage *)defaultAlphaEMap
{
    if(_alphaemap == NULL)
        _alphaemap = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:_alphaemappath]];
    return _alphaemap;
}

- (NSString *)defaultAlphaEMapPath
{
    return _alphaemappath;
}

- (CIImage *)defaultRamp
{
    if(_ramp == NULL)
        _ramp = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:_ramppath]];
    return _ramp;
}

- (NSString *)defaultRampPath
{
    return _ramppath;
}

- (CIImage *)defaultMask
{
    if(_mask == NULL)
        _mask = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:_maskpath]];
    return _mask;
}

- (NSString *)defaultMaskPath
{
    return _maskpath;
}

@end
