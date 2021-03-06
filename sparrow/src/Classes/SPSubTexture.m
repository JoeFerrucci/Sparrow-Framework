//
//  SPSubTexture.m
//  Sparrow
//
//  Created by Daniel Sperl on 27.06.09.
//  Copyright 2011-2015 Gamua. All rights reserved.
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the Simplified BSD License.
//

#import "SparrowClass.h"
#import "SPContext.h"
#import "SPMacros.h"
#import "SPMatrix.h"
#import "SPPoint.h"
#import "SPRectangle.h"
#import "SPGLTexture.h"
#import "SPSubTexture.h"
#import "SPVertexData.h"

// --- c functions ---

static GLKVector2 transformVector2WithMatrix3(const GLKMatrix3 *glkMatrix, const GLKVector2 vector)
{
    return (GLKVector2) {{
        glkMatrix->m00*vector.x + glkMatrix->m10*vector.y + glkMatrix->m20,
        glkMatrix->m11*vector.y + glkMatrix->m01*vector.x + glkMatrix->m21
    }};
}

// --- class implementation ------------------------------------------------------------------------

@implementation SPSubTexture
{
    SPTexture *_parent;
    SPRectangle *_region;
    SPRectangle *_frame;
    BOOL _rotated;
    float _width;
    float _height;
    SPMatrix *_transformationMatrix;
}

@synthesize frame = _frame;

#pragma mark Initialization

- (instancetype)initWithRegion:(SPRectangle *)region ofTexture:(SPTexture *)texture
{
    return [self initWithRegion:region frame:nil ofTexture:texture];
}

- (instancetype)initWithRegion:(SPRectangle *)region frame:(SPRectangle *)frame
                     ofTexture:(SPTexture *)texture
{
    return [self initWithRegion:region frame:frame rotated:NO ofTexture:texture];
}

- (instancetype)initWithRegion:(SPRectangle *)region frame:(SPRectangle *)frame
                       rotated:(BOOL)rotated ofTexture:(SPTexture *)parent
{
    if ((self = [super init]))
    {
        _parent = [parent retain];
        _region = region ? [region copy] : [[SPRectangle alloc] initWithX:0 y:0 width:parent.width height:parent.height];
        _frame = [frame copy];
        _rotated = rotated;
        _width  = rotated ? _region.height : _region.width;
        _height = rotated ? _region.width  : _region.height;
        _transformationMatrix = [[SPMatrix alloc] init];

        if (rotated)
        {
            [_transformationMatrix translateXBy:0 yBy:-1];
            [_transformationMatrix rotateBy:PI / 2.0f];
        }
        
        if (_frame && (_frame.x > 0 || _frame.y > 0 ||
                       _frame.right < _width || _frame.bottom < _height))
        {
            SPLog(@"Warning: frames inside the texture's region are unsupported.");
        }

        [_transformationMatrix scaleXBy:_region.width  / parent.width
                                    yBy:_region.height / parent.height];

        [_transformationMatrix translateXBy:_region.x  / parent.width
                                        yBy:_region.y  / parent.height];
    }
    return self;
}

- (instancetype)init
{
    [self release];
    return nil;
}

- (void)dealloc
{
    [_parent release];
    [_region release];
    [_frame release];
    [_transformationMatrix release];
    
    [super dealloc];
}

+ (instancetype)textureWithRegion:(SPRectangle *)region ofTexture:(SPTexture *)texture
{
    return [[[self alloc] initWithRegion:region ofTexture:texture] autorelease];
}

#pragma mark SPTexture

- (void)adjustVertexData:(SPVertexData *)vertexData atIndex:(NSInteger)index numVertices:(NSInteger)count
{
    SPVertex *vertices = vertexData.vertices;
    NSInteger stride = sizeof(SPVertex) - sizeof(GLKVector2);

    [self adjustTexCoords:&vertices[index].texCoords numVertices:count stride:stride];
    [self adjustPositions:&vertices[index].position  numVertices:count stride:stride];
}

- (void)adjustTexCoords:(void *)data numVertices:(NSInteger)count stride:(NSInteger)stride
{
    SPTexture *texture = self;
    SPMatrix *matrix = [[SPMatrix alloc] init];

    do
    {
        SPSubTexture *subTexture = (SPSubTexture *)texture;
        [matrix appendMatrix:subTexture->_transformationMatrix];
        texture = subTexture->_parent;
    }
    while ([texture isKindOfClass:[SPSubTexture class]]);

    const GLKMatrix3 glkMatrix = matrix.convertToGLKMatrix3;
    const size_t step = sizeof(GLKVector2) + stride;

    for (int i=0; i<count; ++i)
    {
        GLKVector2 *currentCoord = (GLKVector2 *)data;
        *currentCoord = transformVector2WithMatrix3(&glkMatrix, *currentCoord);
        data += step;
    }

    [matrix release];
}

- (void)adjustPositions:(void *)data numVertices:(NSInteger)count stride:(NSInteger)stride
{
    if (_frame)
    {
        if (count != 4)
            [NSException raise:SPExceptionInvalidOperation
                        format:@"Textures with a frame can only be used on quads"];

        const float deltaRight  = _frame.width  + _frame.x - _width;
        const float deltaBottom = _frame.height + _frame.y - _height;

        const size_t step = sizeof(GLKVector2) + stride;
        GLKVector2 *pos = NULL;

        // top left
        pos = (GLKVector2 *)data;
        pos->x -= _frame.x;
        pos->y -= _frame.y;

        // top right
        pos = (GLKVector2 *)(data + step);
        pos->x -= deltaRight;
        pos->y -= _frame.y;

        // bottom left
        pos = (GLKVector2 *)(data + 2*step);
        pos->x -= _frame.x;
        pos->y -= deltaBottom;

        // bottom right
        pos = (GLKVector2 *)(data + 3*step);
        pos->x -= deltaRight;
        pos->y -= deltaBottom;
    }
}

- (float)width
{
    return _width;
}

- (float)height
{
    return _height;
}

- (float)nativeWidth
{
    return _width * self.scale;
}

- (float)nativeHeight
{
    return _height * self.scale;
}

- (SPGLTexture *)root
{
    return _parent.root;
}

- (uint)name
{
    return _parent.name;
}

- (BOOL)premultipliedAlpha
{
    return _parent.premultipliedAlpha;
}

- (SPTextureFormat)format
{
    return _parent.format;
}

- (BOOL)mipmaps
{
    return _parent.mipmaps;
}

- (float)scale
{
    return _parent.scale;
}

- (void)setRepeat:(BOOL)value
{
    _parent.repeat = value;
}

- (BOOL)repeat
{
    return _parent.repeat;
}

- (SPTextureSmoothing)smoothing
{
    return _parent.smoothing;
}

- (void)setSmoothing:(SPTextureSmoothing)value
{
    _parent.smoothing = value;
}

#pragma mark Properties

- (SPRectangle *)clipping
{
    SPPoint *topLeft      = [_transformationMatrix transformPointWithX:0.0f y:0.0f];
    SPPoint *bottomRight  = [_transformationMatrix transformPointWithX:1.0f y:1.0f];
    SPRectangle *clipping = [SPRectangle rectangleWithX:topLeft.x y:topLeft.y
                                                  width:bottomRight.x - topLeft.x
                                                 height:bottomRight.y - topLeft.y];
    [clipping normalize];
    return clipping;
}

@end
