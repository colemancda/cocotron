//
//  NSOpenGLDrawable_X11.m
//  AppKit
//
//  Created by Johannes Fortmann on 02.01.09.
//  Copyright 2009 -. All rights reserved.
//

#import <AppKit/NSOpenGLDrawable_X11.h>
#import <AppKit/X11Display.h>
#import <AppKit/X11Window.h>
#import <AppKit/NSWindow-Private.h>

#include <X11/X.h>
#include <X11/Xlib.h>
#include <GL/gl.h>
#include <GL/glx.h>
#include <GL/glu.h>

void CGLDestroyContext(void *glContext)
{
   glXDestroyContext([(X11Display*)[NSDisplay currentDisplay] display], glContext);
}

@implementation NSOpenGLDrawable(X11)

+allocWithZone:(NSZone *)zone {
   return NSAllocateObject([NSOpenGLDrawable_X11 class],0,NULL);
}

@end

@implementation NSOpenGLDrawable_X11

-initWithPixelFormat:(NSOpenGLPixelFormat *)pixelFormat view:(NSView *)view {
   if(self = [super init]) {
      _format=[pixelFormat retain];
      _dpy=[(X11Display*)[NSDisplay currentDisplay] display];
      
      GLint                   att[] = {
         GLX_RGBA,
         GLX_DEPTH_SIZE, 15,
         None
      };
      _vi = glXChooseVisual(_dpy, 0, att);
      
      if(!_vi) {
         [self release];
         return nil;
      }
      
      Colormap cmap = XCreateColormap(_dpy, DefaultRootWindow(_dpy), _vi->visual, AllocNone);

      XSetWindowAttributes xattr;
      xattr.colormap=cmap;
      xattr.event_mask = ExposureMask | KeyPressMask;
      _window = XCreateWindow(_dpy, DefaultRootWindow(_dpy), 0, 0, 100, 100, 0, _vi->depth, InputOutput, _vi->visual, CWColormap | CWEventMask, &xattr);
      XSetWindowBackgroundPixmap(_dpy, _window, None);
      [X11Window removeDecorationForWindow:_window onDisplay:_dpy];
      
      [self updateWithView:view];
      XMapWindow(_dpy, _window);

   }
   return self;
}

-(void)dealloc {
   if(_window)
      XDestroyWindow(_dpy, _window);
   [_format release];
   [super dealloc];
}

-(void *)createGLContext {
   GLXContext glc;

   if(!_vi)
      return NULL;
   glc = glXCreateContext(_dpy, _vi, NULL, GL_TRUE);

   return glc;
}

-(void)invalidate {
}

-(void)updateWithView:(NSView *)view {
   NSRect frame=[view frame];
   frame=[[view superview] convertRect:frame toView:nil];

   X11Window *wnd=(X11Window*)[[view window] platformWindow];
   NSRect wndFrame=[wnd frame];
   
   frame.origin.y=wndFrame.size.height-(frame.origin.y+frame.size.height);
   
   XMoveResizeWindow(_dpy, _window, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
   Window viewWindow=[(X11Window*)[[view window] platformWindow] drawable];
   if(_lastParent!=viewWindow) {
      XReparentWindow(_dpy, _window, viewWindow, frame.origin.x, frame.origin.y);
      _lastParent=viewWindow;
   }
}

-(void)makeCurrentWithGLContext:(void *)glContext {
   glXMakeCurrent(_dpy, _window, (GLXContext)glContext);
}

-(void)swapBuffers {
   glXSwapBuffers(_dpy, _window);
}

@end
