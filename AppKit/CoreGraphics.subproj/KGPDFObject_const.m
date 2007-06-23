/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

// Original - Christopher Lloyd <cjwl@objc.net>
#import "KGPDFObject_const.h"
#import <Foundation/NSString.h>

@implementation KGPDFObject_const

-initWithObjectType:(KGPDFObjectType)type {
   _objectType=type;
   return self;
}

+pdfObjectArrayMark {
   return [[[self alloc] initWithObjectType:KGPDFObjectTypeMark_array_open] autorelease];
}

+pdfObjectArrayMarkEnd {
   return [[[self alloc] initWithObjectType:KGPDFObjectTypeMark_array_close] autorelease];
}

+pdfObjectDictionaryMark {
   return [[[self alloc] initWithObjectType:KGPDFObjectTypeMark_dictionary_open] autorelease];
}

+pdfObjectDictionaryMarkEnd {
   return [[[self alloc] initWithObjectType:KGPDFObjectTypeMark_dictionary_close] autorelease];
}

+pdfObjectWithNull {
   return [[[self alloc] initWithObjectType:kKGPDFObjectTypeNull] autorelease];
}


-(KGPDFObjectType)objectType {
   return _objectType;
}

-(BOOL)checkForType:(KGPDFObjectType)type value:(void *)value {
   if(type!=_objectType)
    return NO;
   
   return YES;
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<%@ %d>",isa,_objectType];
}

@end
