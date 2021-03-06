/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import "KGContext_gdi.h"
#import "KGLayer_gdi.h"
#import "Win32Window.h"
#import "Win32DeviceContextPrinter.h"
#import "KGDeviceContext_gdi_ddb.h"
#import "KGDeviceContext_gdiDIBSection.h"
#import "KGSurface_DIBSection.h"
#import "Win32DeviceContextWindow.h"
#import <CoreGraphics/KGGraphicsState.h>
#import <AppKit/KGDeviceContext_gdi.h>
#import <CoreGraphics/O2MutablePath.h>
#import <CoreGraphics/O2Color.h>
#import <CoreGraphics/O2ColorSpace.h>
#import <CoreGraphics/KGDataProvider.h>
#import <CoreGraphics/KGShading.h>
#import <CoreGraphics/KGFunction.h>
#import <CoreGraphics/KGContext_builtin.h>
#import "KGFont_gdi.h"
#import <CoreGraphics/KGImage.h>
#import <CoreGraphics/KGClipPhase.h>
#import <AppKit/Win32Font.h>
#import <AppKit/NSRaise.h>

static inline int float2int(float coord){
   return floorf(coord);
}

static inline BOOL transformIsFlipped(CGAffineTransform matrix){
   return (matrix.d<0)?YES:NO;
}

static NSRect Win32TransformRect(CGAffineTransform matrix,NSRect rect) {
   NSPoint point1=CGPointApplyAffineTransform(rect.origin,matrix);
   NSPoint point2=CGPointApplyAffineTransform(NSMakePoint(NSMaxX(rect),NSMaxY(rect)),matrix);

   if(point2.y<point1.y){
    float temp=point2.y;
    point2.y=point1.y;
    point1.y=temp;
   }

  return NSMakeRect(point1.x,point1.y,point2.x-point1.x,point2.y-point1.y);
}

static inline void GrayAToRGBA(float *input,float *output){
   output[0]=input[0];
   output[1]=input[0];
   output[2]=input[0];
   output[3]=input[1];
}

static inline void RGBAToRGBA(float *input,float *output){
   output[0]=input[0];
   output[1]=input[1];
   output[2]=input[2];
   output[3]=input[3];
}

static inline void CMYKAToRGBA(float *input,float *output){
   float white=1-input[3];
   
   output[0]=(input[0]>white)?0:white-input[0];
   output[1]=(input[1]>white)?0:white-input[1];
   output[2]=(input[2]>white)?0:white-input[2];
   output[3]=input[4];
}

static RECT NSRectToRECT(NSRect rect) {
   RECT result;

   if(rect.size.height<0)
    rect=NSZeroRect;
   if(rect.size.width<0)
    rect=NSZeroRect;

   result.top=float2int(rect.origin.y);
   result.left=float2int(rect.origin.x);
   result.bottom=float2int(rect.origin.y+rect.size.height);
   result.right=float2int(rect.origin.x+rect.size.width);

   return result;
}

@implementation KGContext_gdi

+(BOOL)canInitWithWindow:(CGWindow *)window {
   return YES;
}

+(BOOL)canInitBackingWithContext:(KGContext *)context deviceDictionary:(NSDictionary *)deviceDictionary {
   NSString *name=[deviceDictionary objectForKey:@"CGContext"];
   
   if(name==nil || [name isEqual:@"GDI"])
    return YES;
    
   return NO;
}

-initWithGraphicsState:(KGGraphicsState *)state deviceContext:(KGDeviceContext_gdi *)deviceContext {
   [self initWithGraphicsState:state];
   _deviceContext=[deviceContext retain];
   _dc=[_deviceContext dc];
   _gdiFont=nil;

   return self;
}

-initWithHWND:(HWND)handle {
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextWindow alloc] initWithWindowHandle:handle] autorelease];
   NSSize                  size=[deviceContext pixelSize];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithPrinterDC:(HDC)printer auxiliaryInfo:(NSDictionary *)auxiliaryInfo {
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextPrinter alloc] initWithDC:printer] autorelease];
   NSSize                  pointSize=[deviceContext pointSize];
   NSSize                  pixelsPerInch=[deviceContext pixelsPerInch];
   CGAffineTransform       flip={1,0,0,-1,0, pointSize.height};
   CGAffineTransform       scale=CGAffineTransformConcat(flip,CGAffineTransformMakeScale(pixelsPerInch.width/72.0,pixelsPerInch.height/72.0));
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:scale] autorelease];
      
   if([self initWithGraphicsState:initialState deviceContext:deviceContext]==nil)
    return nil;
   
   NSString *title=[auxiliaryInfo objectForKey:kCGPDFContextTitle];
   
   if(title==nil)
    title=@"Untitled";

   [[self deviceContext] beginPrintingWithDocumentName:title];
   
   return self;
}

-initWithSize:(NSSize)size window:(CGWindow *)window {
   HWND                    handle=[(Win32Window *)window windowHandle];
   KGDeviceContext_gdi    *deviceContext=[[[Win32DeviceContextWindow alloc] initWithWindowHandle:handle] autorelease];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-initWithSize:(NSSize)size context:(KGContext *)otherX {
   KGContext_gdi          *other=(KGContext_gdi *)otherX;
 //  KGDeviceContext_gdi    *deviceContext=[[[KGDeviceContext_gdi_ddb alloc] initWithSize:size deviceContext:[other deviceContext]] autorelease];
   KGDeviceContext_gdi    *deviceContext=[[[KGDeviceContext_gdiDIBSection alloc] initWithWidth:size.width height:size.height deviceContext:[other deviceContext]] autorelease];
   CGAffineTransform       flip={1,0,0,-1,0,size.height};
   KGGraphicsState        *initialState=[[[KGGraphicsState alloc] initWithDeviceTransform:flip] autorelease];

   return [self initWithGraphicsState:initialState deviceContext:deviceContext];
}

-(void)dealloc {
   [_deviceContext release];
   [_gdiFont release];
   [super dealloc];
}

-(KGSurface *)createSurfaceWithWidth:(size_t)width height:(size_t)height {
   return [[KGSurface_DIBSection alloc] initWithWidth:width height:height compatibleWithDeviceContext:[self deviceContext]];
}

-(NSSize)pointSize {
   return [[self deviceContext] pointSize];
}

-(HDC)dc {
   return _dc;
}

-(HWND)windowHandle {
   return [[[self deviceContext] windowDeviceContext] windowHandle];
}

-(HFONT)fontHandle {
   return [_gdiFont fontHandle];
}

-(KGDeviceContext_gdi *)deviceContext {
   return _deviceContext;
}

-(void)establishFontStateInDevice {
   KGGraphicsState *gState=[self currentState];
   [_gdiFont release];
   _gdiFont=[(KGFont_gdi *)[gState font] createGDIFontSelectedInDC:_dc pointSize:[gState pointSize]];
}

-(void)establishFontState {
   [self establishFontStateInDevice];
}

-(void)setFont:(KGFont *)font {
   [super setFont:font];
   [self establishFontState];
}

-(void)setFontSize:(float)size {
   [super setFontSize:size];
   [self establishFontState];
}

-(void)selectFontWithName:(const char *)name size:(float)size encoding:(int)encoding {
   [super selectFontWithName:name size:size encoding:encoding];
   [self establishFontState];
}

-(void)restoreGState {
   [super restoreGState];
   [self establishFontStateInDevice];
}


-(void)deviceClipReset {
   [_deviceContext clipReset];
}

-(void)deviceClipToNonZeroPath:(O2Path *)path {
   KGGraphicsState *state=[self currentState];
   [_deviceContext clipToNonZeroPath:path withTransform:CGAffineTransformInvert(state->_userSpaceTransform) deviceTransform:state->_deviceSpaceTransform];
}

-(void)deviceClipToEvenOddPath:(O2Path *)path {
   KGGraphicsState *state=[self currentState];
   [_deviceContext clipToEvenOddPath:path withTransform:CGAffineTransformInvert(state->_userSpaceTransform) deviceTransform:state->_deviceSpaceTransform];
}

-(void)deviceClipToMask:(KGImage *)mask inRect:(NSRect)rect {
// do nothing, see image drawing for how clip masks are used (1x1 alpha mask)
}

-(void)drawPathInDeviceSpace:(O2Path *)path drawingMode:(int)mode state:(KGGraphicsState *)state {
   CGAffineTransform deviceTransform=state->_deviceSpaceTransform;
   O2Color *fillColor=state->_fillColor;
   O2Color *strokeColor=state->_strokeColor;
   XFORM current;
   XFORM userToDevice={deviceTransform.a,deviceTransform.b,deviceTransform.c,deviceTransform.d,deviceTransform.tx,
                       (deviceTransform.d<0.0)?deviceTransform.ty/*-1.0*/:deviceTransform.ty};
   
   if(!GetWorldTransform(_dc,&current))
    NSLog(@"GetWorldTransform failed");

   if(!SetWorldTransform(_dc,&userToDevice))
    NSLog(@"ModifyWorldTransform failed");

   [_deviceContext establishDeviceSpacePath:path withTransform:CGAffineTransformInvert(state->_userSpaceTransform)];
      
   {
    HBRUSH fillBrush=CreateSolidBrush(COLORREFFromColor(fillColor));
    HBRUSH oldBrush=SelectObject(_dc,fillBrush);

    if(mode==kCGPathFill || mode==kCGPathFillStroke){
     SetPolyFillMode(_dc,WINDING);
     FillPath(_dc);
    }
    if(mode==kCGPathEOFill || mode==kCGPathEOFillStroke){
     SetPolyFillMode(_dc,ALTERNATE);
     FillPath(_dc);
    }
    SelectObject(_dc,oldBrush);
    DeleteObject(fillBrush);
   }
   
   if(mode==kCGPathStroke || mode==kCGPathFillStroke || mode==kCGPathEOFillStroke){
    DWORD    style;
    LOGBRUSH logBrush={BS_SOLID,COLORREFFromColor(strokeColor),0};
    
    style=PS_GEOMETRIC;
    if(state->_dashLengthsCount==0)
     style|=PS_SOLID;
    else
     style|=PS_USERSTYLE;
     
    switch(state->_lineCap){
     case kCGLineCapButt:
      style|=PS_ENDCAP_FLAT;
      break;
     case kCGLineCapRound:
      style|=PS_ENDCAP_ROUND;
      break;
     case kCGLineCapSquare:
      style|=PS_ENDCAP_SQUARE;
      break;
    }
    
    switch(state->_lineJoin){
     case kCGLineJoinMiter:
      style|=PS_JOIN_MITER;
      break;
     case kCGLineJoinRound:
      style|=PS_JOIN_ROUND;
      break;
     case kCGLineJoinBevel:
      style|=PS_JOIN_BEVEL;
      break;
    }

    DWORD  *dashes=NULL;
    DWORD   dashesCount=state->_dashLengthsCount;
    if(dashesCount>0){
     int i;
     dashes=__builtin_alloca(dashesCount*sizeof(DWORD));
     
     for(i=0;i<dashesCount;i++)
      dashes[i]=float2int(state->_dashLengths[i]);
    }
    
    HPEN   pen=ExtCreatePen(style,float2int(state->_lineWidth),&logBrush,dashesCount,dashes);
    HPEN   oldpen=SelectObject(_dc,pen);
    
    SetMiterLimit(_dc,state->_miterLimit,NULL);
    StrokePath(_dc);
    SelectObject(_dc,oldpen);
    DeleteObject(pen);
   }
   
   if(!SetWorldTransform(_dc,&current))
    NSLog(@"SetWorldTransform failed");
}


-(void)drawPath:(CGPathDrawingMode)pathMode {

   [self drawPathInDeviceSpace:_path drawingMode:pathMode state:[self currentState] ];
   
   O2PathReset(_path);
}

-(void)showGlyphs:(const CGGlyph *)glyphs count:(unsigned)count {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   KGGraphicsState  *gState=[self currentState];
   CGAffineTransform Trm=CGAffineTransformConcat(gState->_textTransform,transformToDevice);
   NSPoint           point=CGPointApplyAffineTransform(NSMakePoint(0,0),Trm);
   
   SetTextColor(_dc,COLORREFFromColor([self fillColor]));

   ExtTextOutW(_dc,lroundf(point.x),lroundf(point.y),ETO_GLYPH_INDEX,NULL,(void *)glyphs,count,NULL);

   KGFont *font=[gState font];
   int     i,advances[count];
   CGFloat unitsPerEm=CGFontGetUnitsPerEm(font);
   
   O2FontGetGlyphAdvances(font,glyphs,count,advances);
   
   CGFloat total=0;
   
   for(i=0;i<count;i++)
    total+=advances[i];
    
   total=(total/CGFontGetUnitsPerEm(font))*gState->_pointSize;
      
   [self currentState]->_textTransform.tx+=total;
   [self currentState]->_textTransform.ty+=0;
}

-(void)showText:(const char *)text length:(unsigned)length {
   CGGlyph *encoding=[[self currentState] glyphTableForTextEncoding];
   CGGlyph  glyphs[length];
   int      i;
   
   for(i=0;i<length;i++)
    glyphs[i]=encoding[(uint8_t)text[i]];
    
   [self showGlyphs:glyphs count:length];
}

// The problem is that the GDI gradient fill is a linear/stitched filler and the
// Mac one is a sampling one. So to preserve color variation we stitch together a lot of samples

// we could use stitched linear PDF functions better, i.e. use the intervals
// we could decompose the rectangles further and just use fills if we don't have GradientFill (or ditch GradientFill altogether)
// we could test for cases where the angle is a multiple of 90 and use the _H or _V constants if we dont have transformations
// we could decompose this better to platform generalize it

static inline float axialBandIntervalFromMagnitude(KGFunction *function,float magnitude){
   if(magnitude<1)
    return 0;

   if([function isLinear])
    return 1;
   
   if(magnitude<1)
    return 1;
   if(magnitude<4)
    return magnitude;
    
   return magnitude/4; // 4== arbitrary
}

#ifndef GRADIENT_FILL_RECT_H
#define GRADIENT_FILL_RECT_H 0
#endif

-(void)drawInUserSpace:(CGAffineTransform)matrix axialShading:(KGShading *)shading {
   O2ColorSpaceRef colorSpace=[shading colorSpace];
   O2ColorSpaceType colorSpaceType=[colorSpace type];
   KGFunction   *function=[shading function];
   const float  *domain=[function domain];
   const float  *range=[function range];
   BOOL          extendStart=[shading extendStart];
   BOOL          extendEnd=[shading extendEnd];
   NSPoint       startPoint=CGPointApplyAffineTransform([shading startPoint],matrix);
   NSPoint       endPoint=CGPointApplyAffineTransform([shading endPoint],matrix);
   NSPoint       vector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
   float         magnitude=ceilf(sqrtf(vector.x*vector.x+vector.y*vector.y));
   float         angle=(magnitude==0)?0:(atanf(vector.y/vector.x)+((vector.x<0)?M_PI:0));
   float         bandInterval=axialBandIntervalFromMagnitude(function,magnitude);
   int           bandCount=bandInterval;
   int           i,rectIndex=0;
   float         rectWidth=(bandCount==0)?0:magnitude/bandInterval;
   float         domainInterval=(bandCount==0)?0:(domain[1]-domain[0])/bandInterval;
   GRADIENT_RECT rect[1+bandCount+1];
   int           vertexIndex=0;
   TRIVERTEX     vertices[(1+bandCount+1)*2];
   float         output[[colorSpace numberOfComponents]+1];
   float         rgba[4];
   void        (*outputToRGBA)(float *,float *);
   // should use something different here so we dont get huge numbers on printers, the clip bbox?
   int           hRes=GetDeviceCaps(_dc,HORZRES);
   int           vRes=GetDeviceCaps(_dc,VERTRES);
   float         maxHeight=MAX(hRes,vRes)*2;

   typedef WINGDIAPI BOOL WINAPI (*gradientType)(HDC,PTRIVERTEX,ULONG,PVOID,ULONG,ULONG);
   HANDLE        library=LoadLibrary("MSIMG32");
   gradientType  gradientFill=(gradientType)GetProcAddress(library,"GradientFill");
          
   if(gradientFill==NULL){
    NSLog(@"Unable to locate GradientFill");
    return;
   }

   switch(colorSpaceType){

    case O2ColorSpaceDeviceGray:
     outputToRGBA=GrayAToRGBA;
     break;
     
    case O2ColorSpaceDeviceRGB:
    case O2ColorSpacePlatformRGB:
     outputToRGBA=RGBAToRGBA;
     break;
     
    case O2ColorSpaceDeviceCMYK:
     outputToRGBA=CMYKAToRGBA;
     break;
     
    default:
     NSLog(@"axial shading can't deal with colorspace %@",colorSpace);
     return;
   }
      
   if(extendStart){
    [function evaluateInput:domain[0] output:output];
    outputToRGBA(output,rgba);
    
    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(-maxHeight);
    vertices[vertexIndex].y=float2int(-maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
 // the degenerative case for magnitude==0 is to fill the whole area with the extend
    if(magnitude!=0)
     vertices[vertexIndex].x=float2int(0);
    else {
     vertices[vertexIndex].x=float2int(maxHeight);
     extendEnd=NO;
    }
    vertices[vertexIndex].y=float2int(maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   for(i=0;i<bandCount;i++){
    float x0=domain[0]+i*domainInterval;
    float x1=domain[0]+(i+1)*domainInterval;
   
    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(i*rectWidth);
    vertices[vertexIndex].y=float2int(-maxHeight);
    [function evaluateInput:x0 output:output];
    outputToRGBA(output,rgba);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
    vertices[vertexIndex].x=float2int((i+1)*rectWidth);
    vertices[vertexIndex].y=float2int(maxHeight);
    [function evaluateInput:x1 output:output];
    outputToRGBA(output,rgba);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   if(extendEnd){
    [function evaluateInput:domain[1] output:output];
    outputToRGBA(output,rgba);

    rect[rectIndex].UpperLeft=vertexIndex;
    vertices[vertexIndex].x=float2int(i*rectWidth);
    vertices[vertexIndex].y=float2int(-maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;
    
    rect[rectIndex].LowerRight=vertexIndex;
    vertices[vertexIndex].x=float2int(maxHeight);
    vertices[vertexIndex].y=float2int(maxHeight);
    vertices[vertexIndex].Red=rgba[0]*0xFFFF;
    vertices[vertexIndex].Green=rgba[1]*0xFFFF;
    vertices[vertexIndex].Blue=rgba[2]*0xFFFF;
    vertices[vertexIndex].Alpha=rgba[3]*0xFFFF;
    vertexIndex++;

    rectIndex++;
   }
   
   if(rectIndex==0)
    return;
   
   {
    XFORM current;
    XFORM translate={1,0,0,1,startPoint.x,startPoint.y};
    XFORM rotate={cos(angle),sin(angle),-sin(angle),cos(angle),0,0};
     
    if(!GetWorldTransform(_dc,&current))
     NSLog(@"GetWorldTransform failed");
     
    if(!ModifyWorldTransform(_dc,&rotate,MWT_RIGHTMULTIPLY))
     NSLog(@"ModifyWorldTransform failed");
    if(!ModifyWorldTransform(_dc,&translate,MWT_RIGHTMULTIPLY))
     NSLog(@"ModifyWorldTransform failed");
    
    if(!gradientFill(_dc,vertices,vertexIndex,rect,rectIndex,GRADIENT_FILL_RECT_H))
     NSLog(@"GradientFill failed");

    if(!SetWorldTransform(_dc,&current))
     NSLog(@"GetWorldTransform failed");
   }
   
}

static int appendCircle(NSPoint *cp,int position,float x,float y,float radius,CGAffineTransform matrix){
   int i;
   
   O2MutablePathEllipseToBezier(cp+position,x,y,radius,radius);
   for(i=0;i<13;i++)
    cp[position+i]=CGPointApplyAffineTransform(cp[position+i],matrix);
    
   return position+13;
}

static void appendCircleToDC(HDC dc,NSPoint *cp){
   POINT   cPOINT[13];
   int     i,count=13;

   for(i=0;i<count;i++){
    cPOINT[i].x=float2int(cp[i].x);
    cPOINT[i].y=float2int(cp[i].y);
   }
   
   MoveToEx(dc,cPOINT[0].x,cPOINT[0].y,NULL);      
   PolyBezierTo(dc,cPOINT+1,count-1);
}

static void appendCircleToPath(HDC dc,float x,float y,float radius,CGAffineTransform matrix){
   NSPoint cp[13];
   
   appendCircle(cp,0,x,y,radius,matrix);
   appendCircleToDC(dc,cp);
}

static inline float numberOfRadialBands(KGFunction *function,NSPoint startPoint,NSPoint endPoint,float startRadius,float endRadius,CGAffineTransform matrix){
   NSPoint startRadiusPoint=NSMakePoint(startRadius,0);
   NSPoint endRadiusPoint=NSMakePoint(endRadius,0);
   
   startPoint=CGPointApplyAffineTransform(startPoint,matrix);
   endPoint=CGPointApplyAffineTransform(endPoint,matrix);
   
   startRadiusPoint=CGPointApplyAffineTransform(startRadiusPoint,matrix);
   endRadiusPoint=CGPointApplyAffineTransform(endRadiusPoint,matrix);
{
   NSPoint lineVector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
   float   lineMagnitude=ceilf(sqrtf(lineVector.x*lineVector.x+lineVector.y*lineVector.y));
   NSPoint radiusVector=NSMakePoint(endRadiusPoint.x-startRadiusPoint.x,endRadiusPoint.y-startRadiusPoint.y);
   float   radiusMagnitude=ceilf(sqrtf(radiusVector.x*radiusVector.x+radiusVector.y*radiusVector.y))*2;
   float   magnitude=MAX(lineMagnitude,radiusMagnitude);

   return magnitude;
}
}

// FIX, still lame
static BOOL controlPointsOutsideClip(HDC dc,NSPoint cp[13]){
   NSRect clipRect,cpRect;
   RECT   gdiRect;
   int    i;
   
   if(!GetClipBox(dc,&gdiRect)){
    NSLog(@"GetClipBox failed");
    return NO;
   }
   clipRect.origin.x=gdiRect.left;
   clipRect.origin.y=gdiRect.top;
   clipRect.size.width=gdiRect.right-gdiRect.left;
   clipRect.size.height=gdiRect.bottom-gdiRect.top;
   
   clipRect.origin.x-=clipRect.size.width;
   clipRect.origin.y-=clipRect.size.height;
   clipRect.size.width*=3;
   clipRect.size.height*=3;
   
   for(i=0;i<13;i++)
    if(cp[i].x>50000 || cp[i].x<-50000 || cp[i].y>50000 || cp[i].y<-50000)
     return YES;
     
   for(i=0;i<13;i++)
    if(NSPointInRect(cp[i],clipRect))
     return NO;
     
   return YES;
}


static void extend(HDC dc,int i,int direction,float bandInterval,NSPoint startPoint,NSPoint endPoint,float startRadius,float endRadius,CGAffineTransform matrix){
// - some edge cases of extend are either slow or don't fill bands accurately but these are undesirable gradients

    {
     NSPoint lineVector=NSMakePoint(endPoint.x-startPoint.x,endPoint.y-startPoint.y);
     float   lineMagnitude=ceilf(sqrtf(lineVector.x*lineVector.x+lineVector.y*lineVector.y));
     
     if((lineMagnitude+startRadius)<endRadius){
      BeginPath(dc);
      if(direction<0)
       appendCircleToPath(dc,startPoint.x,startPoint.y,startRadius,matrix);
      else {
       NSPoint point=CGPointApplyAffineTransform(endPoint,matrix);

       appendCircleToPath(dc,endPoint.x,endPoint.y,endRadius,matrix);
       // FIX, lame
       appendCircleToPath(dc,point.x,point.y,1000000,CGAffineTransformIdentity);
      }
      EndPath(dc);
      FillPath(dc);
      return;
     }
     
     if((lineMagnitude+endRadius)<startRadius){
      BeginPath(dc);
      if(direction<0){
       NSPoint point=CGPointApplyAffineTransform(startPoint,matrix);
       
       appendCircleToPath(dc,startPoint.x,startPoint.y,startRadius,matrix);
       // FIX, lame
       appendCircleToPath(dc,point.x,point.y,1000000,CGAffineTransformIdentity);
      }
      else {
       appendCircleToPath(dc,endPoint.x,endPoint.y,endRadius,matrix);
      }
      EndPath(dc);
      FillPath(dc);
      return;
     }
    }

    for(;;i+=direction){
     float position,x,y,radius;
     RECT  check;
     NSPoint cp[13];
   
     BeginPath(dc);

     position=(float)i/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircle(cp,0,x,y,radius,matrix);
     appendCircleToDC(dc,cp);
    
     position=(float)(i+direction)/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircle(cp,0,x,y,radius,matrix);
     appendCircleToDC(dc,cp);
     
     EndPath(dc);

     FillPath(dc);
     
     if(radius<=0)
      break;
 
     if(controlPointsOutsideClip(dc,cp))
      break;
    }
}

-(void)drawInUserSpace:(CGAffineTransform)matrix radialShading:(KGShading *)shading {
/* - band interval needs to be improved
    - does not factor resolution/scaling can cause banding
    - does not factor color sampling rate, generates multiple bands for same color
 */
   O2ColorSpaceRef colorSpace=[shading colorSpace];
   O2ColorSpaceType colorSpaceType=[colorSpace type];
   KGFunction   *function=[shading function];
   const float  *domain=[function domain];
   const float  *range=[function range];
   BOOL          extendStart=[shading extendStart];
   BOOL          extendEnd=[shading extendEnd];
   float         startRadius=[shading startRadius];
   float         endRadius=[shading endRadius];
   NSPoint       startPoint=[shading startPoint];
   NSPoint       endPoint=[shading endPoint];
   float         bandInterval=numberOfRadialBands(function,startPoint,endPoint,startRadius,endRadius,matrix);
   int           i,bandCount=bandInterval;
   float         domainInterval=(bandCount==0)?0:(domain[1]-domain[0])/bandInterval;
   float         output[[colorSpace numberOfComponents]+1];
   float         rgba[4];
   void        (*outputToRGBA)(float *,float *);

   switch(colorSpaceType){

    case O2ColorSpaceDeviceGray:
     outputToRGBA=GrayAToRGBA;
     break;
     
    case O2ColorSpaceDeviceRGB:
    case O2ColorSpacePlatformRGB:
     outputToRGBA=RGBAToRGBA;
     break;
     
    case O2ColorSpaceDeviceCMYK:
     outputToRGBA=CMYKAToRGBA;
     break;
     
    default:
     NSLog(@"radial shading can't deal with colorspace %@",colorSpace);
     return;
   }

   if(extendStart){
    HBRUSH brush;

    [function evaluateInput:domain[0] output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(rgba[0]*255,rgba[1]*255,rgba[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    extend(_dc,0,-1,bandInterval,startPoint,endPoint,startRadius,endRadius,matrix);
    DeleteObject(brush);
   }
   
   for(i=0;i<bandCount;i++){
    HBRUSH brush;
    float position,x,y,radius;
    float x0=((domain[0]+i*domainInterval)+(domain[0]+(i+1)*domainInterval))/2; // midpoint color between edges
    
    BeginPath(_dc);

    position=(float)i/bandInterval;
    x=startPoint.x+position*(endPoint.x-startPoint.x);
    y=startPoint.y+position*(endPoint.y-startPoint.y);
    radius=startRadius+position*(endRadius-startRadius);
    appendCircleToPath(_dc,x,y,radius,matrix);
    
    if(i+1==bandCount)
     appendCircleToPath(_dc,endPoint.x,endPoint.y,endRadius,matrix);
    else {
     position=(float)(i+1)/bandInterval;
     x=startPoint.x+position*(endPoint.x-startPoint.x);
     y=startPoint.y+position*(endPoint.y-startPoint.y);
     radius=startRadius+position*(endRadius-startRadius);
     appendCircleToPath(_dc,x,y,radius,matrix);
    }

    EndPath(_dc);

    [function evaluateInput:x0 output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(output[0]*255,output[1]*255,output[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    FillPath(_dc);
    DeleteObject(brush);
   }
   
   if(extendEnd){
    HBRUSH brush;
    
    [function evaluateInput:domain[1] output:output];
    outputToRGBA(output,rgba);
    brush=CreateSolidBrush(RGB(rgba[0]*255,rgba[1]*255,rgba[2]*255));
    SelectObject(_dc,brush);
    SetPolyFillMode(_dc,ALTERNATE);
    extend(_dc,i,1,bandInterval,startPoint,endPoint,startRadius,endRadius,matrix);

    DeleteObject(brush);
   }
}

-(void)drawShading:(KGShading *)shading {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];

  if([shading isAxial])
   [self drawInUserSpace:transformToDevice axialShading:shading];
  else
   [self drawInUserSpace:transformToDevice radialShading:shading];
}

#if 1

static void sourceOverImage(KGImage *image,KGRGBA8888 *resultBGRX,int width,int height,float fraction){
   KGRGBA8888 *span=__builtin_alloca(width*sizeof(KGRGBA8888));
   int y,coverage=RI_INT_CLAMP(fraction*256,0,256);
   
   for(y=0;y<height;y++){
    KGRGBA8888 *direct=image->_read_lRGBA8888_PRE(image,0,y,span,width);
    KGRGBA8888 *combine=resultBGRX+width*y;
    
    if(direct!=NULL){
     int x;
     
     for(x=0;x<width;x++)
      span[x]=direct[x];
    }
    
    KGBlendSpanNormal_8888_coverage(span,combine,coverage,width);
   }
}

void CGGraphicsSourceOver_rgba32_onto_bgrx32(unsigned char *sourceRGBA,unsigned char *resultBGRX,int width,int height,float fraction) {
   int sourceIndex=0;
   int sourceLength=width*height*4;
   int destinationReadIndex=0;
   int destinationWriteIndex=0;

   fraction *= 256.0/255.0;
   while(sourceIndex<sourceLength){
    unsigned srcr=sourceRGBA[sourceIndex++];
    unsigned srcg=sourceRGBA[sourceIndex++];
    unsigned srcb=sourceRGBA[sourceIndex++];
    unsigned srca=sourceRGBA[sourceIndex++]*fraction;

    unsigned dstb=resultBGRX[destinationReadIndex++];
    unsigned dstg=resultBGRX[destinationReadIndex++];
    unsigned dstr=resultBGRX[destinationReadIndex++];
    unsigned dsta=256-srca;

    destinationReadIndex++;

    dstr=(srcr*srca+dstr*dsta)>>8;
    dstg=(srcg*srca+dstg*dsta)>>8;
    dstb=(srcb*srca+dstb*dsta)>>8;

    resultBGRX[destinationWriteIndex++]=dstb;
    resultBGRX[destinationWriteIndex++]=dstg;
    resultBGRX[destinationWriteIndex++]=dstr;
    destinationWriteIndex++; // skip x
   }
}

void CGGraphicsSourceOver_bgra32_onto_bgrx32(unsigned char *sourceBGRA,unsigned char *resultBGRX,int width,int height,float fraction) {
   int sourceIndex=0;
   int sourceLength=width*height*4;
   int destinationReadIndex=0;
   int destinationWriteIndex=0;

   fraction *= 256.0/255.0;
   while(sourceIndex<sourceLength){
    unsigned srcb=sourceBGRA[sourceIndex++];
    unsigned srcg=sourceBGRA[sourceIndex++];
    unsigned srcr=sourceBGRA[sourceIndex++];
    unsigned srca=sourceBGRA[sourceIndex++]*fraction;

    unsigned dstb=resultBGRX[destinationReadIndex++];
    unsigned dstg=resultBGRX[destinationReadIndex++];
    unsigned dstr=resultBGRX[destinationReadIndex++];
    unsigned dsta=256-srca;

    destinationReadIndex++;

    dstr=(srcr*srca+dstr*dsta)>>8;
    dstg=(srcg*srca+dstg*dsta)>>8;
    dstb=(srcb*srca+dstb*dsta)>>8;

    resultBGRX[destinationWriteIndex++]=dstb;
    resultBGRX[destinationWriteIndex++]=dstg;
    resultBGRX[destinationWriteIndex++]=dstr;
    destinationWriteIndex++; // skip x
   }
}

-(void)drawBitmapImage:(KGImage *)image inRect:(NSRect)rect ctm:(CGAffineTransform)ctm fraction:(float)fraction  {
   int            width=[image width];
   int            height=[image height];
   const unsigned int *data=[image directBytes];
   HDC            sourceDC=_dc;
   HDC            combineDC;
   int            combineWidth=width;
   int            combineHeight=height;
   NSPoint        point=CGPointApplyAffineTransform(rect.origin,ctm);
   HBITMAP        bitmap;
   BITMAPINFO     info;
   void          *bits;
   KGRGBA8888    *combineBGRX;
   unsigned char *imageRGBA=(void *)data;

   if(transformIsFlipped(ctm))
    point.y-=rect.size.height;

   if((combineDC=CreateCompatibleDC(sourceDC))==NULL){
    NSLog(@"CreateCompatibleDC failed");
    return;
   }

   info.bmiHeader.biSize=sizeof(BITMAPINFO);
   info.bmiHeader.biWidth=combineWidth;
   info.bmiHeader.biHeight=-combineHeight;
   info.bmiHeader.biPlanes=1;
   info.bmiHeader.biBitCount=32;
   info.bmiHeader.biCompression=BI_RGB;
   info.bmiHeader.biSizeImage=0;
   info.bmiHeader.biXPelsPerMeter=0;
   info.bmiHeader.biYPelsPerMeter=0;
   info.bmiHeader.biClrUsed=0;
   info.bmiHeader.biClrImportant=0;

   if((bitmap=CreateDIBSection(sourceDC,&info,DIB_RGB_COLORS,&bits,NULL,0))==NULL){
    NSLog(@"CreateDIBSection failed");
    return;
   }
   combineBGRX=bits;
   SelectObject(combineDC,bitmap);

   StretchBlt(combineDC,0,0,combineWidth,combineHeight,sourceDC,point.x,point.y,rect.size.width,rect.size.height,SRCCOPY);
   GdiFlush();

#if 1
   if((CGImageGetAlphaInfo(image)==kCGImageAlphaPremultipliedFirst) && ([image bitmapInfo]&kCGBitmapByteOrderMask)==kCGBitmapByteOrder32Little)
    CGGraphicsSourceOver_bgra32_onto_bgrx32(imageRGBA,(unsigned char *)combineBGRX,width,height,fraction);
   else
    CGGraphicsSourceOver_rgba32_onto_bgrx32(imageRGBA,(unsigned char *)combineBGRX,width,height,fraction);
#else
   sourceOverImage(image,combineBGRX,width,height,fraction);
#endif

   StretchBlt(sourceDC,point.x,point.y,rect.size.width,rect.size.height,combineDC,0,0,combineWidth,combineHeight,SRCCOPY);

   DeleteObject(bitmap);
   DeleteDC(combineDC);
}

#else
// a work in progress
static void zeroBytes(void *bytes,int size){
   int i;
   
   for(i=0;i<size;i++)
    ((char *)bytes)[i]=0;
}

-(void)drawBitmapImage:(KGImage *)image inRect:(NSRect)rect ctm:(CGAffineTransform)ctm fraction:(float)fraction  {
   int            width=[image width];
   int            height=[image height];
   const unsigned char *bytes=[image bytes];
   HDC            sourceDC;
   BITMAPV4HEADER header;
   HBITMAP        bitmap;
   HGDIOBJ        oldBitmap;
   BLENDFUNCTION  blendFunction;
   
   if((sourceDC=CreateCompatibleDC(_dc))==NULL){
    NSLog(@"CreateCompatibleDC failed");
    return;
   }
   
   zeroBytes(&header,sizeof(header));
 
   header.bV4Size=sizeof(BITMAPINFOHEADER);
   header.bV4Width=width;
   header.bV4Height=height;
   header.bV4Planes=1;
   header.bV4BitCount=32;
   header.bV4V4Compression=BI_RGB;
   header.bV4SizeImage=width*height*4;
   header.bV4XPelsPerMeter=0;
   header.bV4YPelsPerMeter=0;
   header.bV4ClrUsed=0;
   header.bV4ClrImportant=0;
#if 0
   header.bV4RedMask=0xFF000000;
   header.bV4GreenMask=0x00FF0000;
   header.bV4BlueMask=0x0000FF00;
   header.bV4AlphaMask=0x000000FF;
#else
//   header.bV4RedMask=  0x000000FF;
//   header.bV4GreenMask=0x0000FF00;
//   header.bV4BlueMask= 0x00FF0000;
//   header.bV4AlphaMask=0xFF000000;
#endif
   header.bV4CSType=0;
  // header.bV4Endpoints;
  // header.bV4GammaRed;
  // header.bV4GammaGreen;
  // header.bV4GammaBlue;
   
   {
    char *bits;
    int  i;
    
   if((bitmap=CreateDIBSection(sourceDC,&header,DIB_RGB_COLORS,&bits,NULL,0))==NULL){
    NSLog(@"CreateDIBSection failed");
    return;
   }
   for(i=0;i<width*height*4;i++){
    bits[i]=0x00;
   }
   }
   if((oldBitmap=SelectObject(sourceDC,bitmap))==NULL)
    NSLog(@"SelectObject failed");

   rect=Win32TransformRect(ctm,rect);

   blendFunction.BlendOp=AC_SRC_OVER;
   blendFunction.BlendFlags=0;
   blendFunction.SourceConstantAlpha=0xFF;
   blendFunction.BlendOp=AC_SRC_ALPHA;
   {
    typedef WINGDIAPI BOOL WINAPI (*alphaType)(HDC,int,int,int,int,HDC,int,int,int,int,BLENDFUNCTION);

    HANDLE library=LoadLibrary("MSIMG32");
    alphaType alphaBlend=(alphaType)GetProcAddress(library,"AlphaBlend");

    if(alphaBlend==NULL)
     NSLog(@"Unable to get AlphaBlend",alphaBlend);
    else {
     if(!alphaBlend(_dc,rect.origin.x,rect.origin.y,rect.size.width,rect.size.height,sourceDC,0,0,width,height,blendFunction))
      NSLog(@"AlphaBlend failed");
    }
   }

   DeleteObject(bitmap);s
   SelectObject(sourceDC,oldBitmap);
   DeleteDC(sourceDC);
}
#endif

-(void)drawImage:(KGImage *)image inRect:(NSRect)rect {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   KGGraphicsState *gState=[self currentState];
   KGClipPhase     *phase=[[gState clipPhases] lastObject];
   
/* The NSImage drawing methods which take a fraction use a 1x1 alpha mask to set the fraction.
   We don't do alpha masks yet but the rough fraction code already existed so we check for this
   special case and generate a fraction from the 1x1 mask. Any other case is ignored.
 */
   float fraction=1.0;

   if(phase!=nil && [phase phaseType]==KGClipPhaseMask){
    KGImage *mask=[phase object];
    
    if([mask width]==1 && [mask height]==1){
     uint8_t byte=255;
     
     if([[mask dataProvider] getBytes:&byte range:NSMakeRange(0,1)]==1)
      fraction=(float)byte/255.0f;
    }
   }
   
   [self drawBitmapImage:image inRect:rect ctm:transformToDevice fraction:fraction];
}

-(void)drawDeviceContext:(KGDeviceContext_gdi *)deviceContext inRect:(NSRect)rect ctm:(CGAffineTransform)ctm {
   rect.origin=CGPointApplyAffineTransform(rect.origin,ctm);

   if(transformIsFlipped(ctm))
    rect.origin.y-=rect.size.height;

   BitBlt([self dc],rect.origin.x,rect.origin.y,rect.size.width,rect.size.height,[deviceContext dc],0,0,SRCCOPY);
}

-(void)drawLayer:(KGLayer *)layer inRect:(NSRect)rect {
   KGContext *context=[layer context];
   
   if(![context isKindOfClass:[KGContext_gdi class]]){
    NSLog(@"layer class is not right %@!=%@",[context class],[self class]);
    return;
   }
   KGDeviceContext_gdi *deviceContext=[(KGContext_gdi *)context deviceContext];
   
   [self drawDeviceContext:deviceContext inRect:rect ctm:[self currentState]->_deviceSpaceTransform];
}

-(void)copyBitsInRect:(NSRect)rect toPoint:(NSPoint)point gState:(int)gState {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   NSRect  srcRect=Win32TransformRect(transformToDevice,rect);
   NSRect  dstRect=Win32TransformRect(transformToDevice,NSMakeRect(point.x,point.y,rect.size.width,rect.size.height));
   NSRect  scrollRect=NSUnionRect(srcRect,dstRect);
   int     dx=dstRect.origin.x-srcRect.origin.x;
   int     dy=dstRect.origin.y-srcRect.origin.y;
   RECT    winScrollRect=NSRectToRECT(scrollRect);

   ScrollDC(_dc,dx,dy,&winScrollRect,&winScrollRect,NULL,NULL);
}

-(KGLayer *)layerWithSize:(NSSize)size unused:(NSDictionary *)unused {
   return [[[KGLayer_gdi alloc] initRelativeToContext:self size:size unused:unused] autorelease];
}

-(void)close {
   [[self deviceContext] endPrinting];
}

-(void)beginPage:(const NSRect *)mediaBox {
   [[self deviceContext] beginPage];
}

-(void)endPage {
   [[self deviceContext] endPage];
}

-(BOOL)getImageableRect:(NSRect *)rect {
   KGDeviceContext_gdi *deviceContext=[self deviceContext];
   if(deviceContext==nil)
    return NO;
    
   *rect=[deviceContext imageableRect];
   return YES;
}

-(void)drawBackingContext:(KGContext *)other size:(NSSize)size {
   KGDeviceContext_gdi *deviceContext=nil;

   if([other isKindOfClass:[KGContext_gdi class]])
    deviceContext=[(KGContext_gdi *)other deviceContext];
   else {
    KGSurface *surface=[other surface];
    
    if([surface isKindOfClass:[KGSurface_DIBSection class]])
     deviceContext=[(KGSurface_DIBSection *)surface deviceContext];
   }

   if(deviceContext!=nil)
    [self drawDeviceContext:deviceContext inRect:NSMakeRect(0,0,size.width,size.height) ctm:CGAffineTransformIdentity];
}

-(void)flush {
   GdiFlush();
}

-(NSData *)captureBitmapInRect:(NSRect)rect {
   CGAffineTransform transformToDevice=[self userSpaceToDeviceSpaceTransform];
   NSPoint           pt = CGPointApplyAffineTransform(rect.origin, transformToDevice);
   int               width = rect.size.width;
   int               height = rect.size.height;
   unsigned long     bmSize = 4*width*height;
   void             *bmBits;
   HBITMAP           bmHandle;
   BITMAPFILEHEADER  bmFileHeader = {0, 0, 0, 0, 0};
   BITMAPINFO        bmInfo;

   if (transformIsFlipped(transformToDevice))
      pt.y -= rect.size.height;

   HDC destDC = CreateCompatibleDC(_dc);
   if (destDC == NULL)
   {
      NSLog(@"CreateCompatibleDC failed");
      return nil;
   }

   bmInfo.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
   bmInfo.bmiHeader.biWidth=width;
   bmInfo.bmiHeader.biHeight=height;
   bmInfo.bmiHeader.biPlanes=1;
   bmInfo.bmiHeader.biBitCount=32;
   bmInfo.bmiHeader.biCompression=BI_RGB;
   bmInfo.bmiHeader.biSizeImage=0;
   bmInfo.bmiHeader.biXPelsPerMeter=0;
   bmInfo.bmiHeader.biYPelsPerMeter=0;
   bmInfo.bmiHeader.biClrUsed=0;
   bmInfo.bmiHeader.biClrImportant=0;

   bmHandle = CreateDIBSection(_dc, &bmInfo, DIB_RGB_COLORS, &bmBits, NULL, 0);
   if (bmHandle == NULL)
   {
      NSLog(@"CreateDIBSection failed");
      return nil;
   }

   SelectObject(destDC, bmHandle);
   BitBlt(destDC, 0, 0, width, height, _dc, pt.x, pt.y, SRCCOPY);
   GdiFlush();

   ((char *)&bmFileHeader)[0] = 'B';
   ((char *)&bmFileHeader)[1] = 'M';
   bmFileHeader.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
   bmFileHeader.bfSize = bmFileHeader.bfOffBits + bmSize;

   NSMutableData *result = [NSMutableData dataWithBytes:&bmFileHeader length:sizeof(BITMAPFILEHEADER)];
   [result appendBytes:&bmInfo.bmiHeader length:sizeof(BITMAPINFOHEADER)];
   [result appendBytes:bmBits length:bmSize];
   
   DeleteObject(bmHandle);
   DeleteDC(destDC);

   return result;
}

@end
