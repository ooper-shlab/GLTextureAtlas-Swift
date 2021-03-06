//
//  PVRTexture.swift
//  GLTextureAtlas
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/27.
//
//
/*
     File: PVRTexture.h
     File: PVRTexture.m
 Abstract: The PVRTexture class is responsible for loading .pvr files generated by texturetool.
  Version: 1.6

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

import UIKit
import OpenGLES.ES1.gl
import OpenGLES.ES1.glext

@objc(PVRTexture)
class PVRTexture: NSObject {
    var _imageData: [Data] = []
    
    //GLuint _name;
    fileprivate(set) var width: UInt32 = 0
    fileprivate(set) var height: UInt32 = 0
    fileprivate(set) var internalFormat: GLenum = GLenum(GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG)
    fileprivate(set) var hasAlpha: Bool = false
    
    //@property (readonly) GLuint name;
    fileprivate(set) var name: GLuint = 0
    
    fileprivate let PVR_TEXTURE_FLAG_TYPE_MASK: UInt32 = 0xff
    
    fileprivate let gPVRTexIdentifier: FourCharCode = "PVR!"
    
    fileprivate let kPVRTextureFlagTypePVRTC_2: UInt32 = 24
    fileprivate let kPVRTextureFlagTypePVRTC_4: UInt32 = 25
    
    struct PVRTexHeader {
        var headerLength: UInt32 = 0
        var height: UInt32 = 0
        var width: UInt32 = 0
        var numMipmaps: UInt32 = 0
        var flags: UInt32 = 0
        var dataLength: UInt32 = 0
        var bpp: UInt32 = 0
        var bitmaskRed: UInt32 = 0
        var bitmaskGreen: UInt32 = 0
        var bitmaskBlue: UInt32 = 0
        var bitmaskAlpha: UInt32 = 0
        var pvrTag: UInt32 = 0
        var numSurfs: UInt32 = 0
    }
    
    
    //@synthesize name = _name;
    
    
    fileprivate func unpackPVRData(_ data: Data) -> Bool {
        var success = false
        var header: UnsafeMutablePointer<PVRTexHeader>? = nil
        var flags: UInt32 = 0
        var pvrTag: UInt32 = 0
        var dataLength: UInt32 = 0
        var dataOffset: UInt32 = 0
        var dataSize: UInt32 = 0
        var blockSize: UInt32 = 0
        var widthBlocks: UInt32 = 0
        var heightBlocks: UInt32 = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        var bpp: UInt32 = 0
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        var formatFlags: UInt32 = 0
        
        header = UnsafeMutablePointer(mutating: (data as NSData).bytes.bindMemory(to: PVRTexture.PVRTexHeader.self, capacity: data.count))
        
        pvrTag = FourCharCode(networkOrder: (header?.pointee.pvrTag)!)
        
        guard gPVRTexIdentifier == pvrTag else {
            return false
        }
        
        flags = CFSwapInt32LittleToHost((header?.pointee.flags)!)
        formatFlags = flags & PVR_TEXTURE_FLAG_TYPE_MASK
        
        if formatFlags == kPVRTextureFlagTypePVRTC_4 || formatFlags == kPVRTextureFlagTypePVRTC_2 {
            _imageData.removeAll()
            
            if formatFlags == kPVRTextureFlagTypePVRTC_4 {
                internalFormat = GL_COMPRESSED_RGBA_PVRTC_4BPPV1_IMG.ui
            } else if formatFlags == kPVRTextureFlagTypePVRTC_2 {
                internalFormat = GL_COMPRESSED_RGBA_PVRTC_2BPPV1_IMG.ui
            }
            
            width = CFSwapInt32LittleToHost((header?.pointee.width)!)
            self.width = width
            height = CFSwapInt32LittleToHost((header?.pointee.height)!)
            self.height = height
            
            if CFSwapInt32LittleToHost((header?.pointee.bitmaskAlpha)!) != 0 {
                hasAlpha = true
            } else {
                hasAlpha = false
            }
            
            dataLength = CFSwapInt32LittleToHost((header?.pointee.dataLength)!)
            
            bytes = UnsafeMutablePointer(mutating: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count)) + MemoryLayout<PVRTexHeader>.stride
            
            // Calculate the data size for each texture level and respect the minimum number of blocks
            while dataOffset < dataLength {
                if formatFlags == kPVRTextureFlagTypePVRTC_4 {
                    blockSize = 4 * 4 // Pixel by pixel block size for 4bpp
                    widthBlocks = width / 4
                    heightBlocks = height / 4
                    bpp = 4
                } else {
                    blockSize = 8 * 4 // Pixel by pixel block size for 2bpp
                    widthBlocks = width / 8
                    heightBlocks = height / 4
                    bpp = 2
                }
                
                // Clamp to minimum number of blocks
                if widthBlocks < 2 {
                    widthBlocks = 2
                }
                if heightBlocks < 2 {
                    heightBlocks = 2
                }
                
                dataSize = widthBlocks * heightBlocks * ((blockSize  * bpp) / 8)
                
                _imageData.append(Data(bytes: UnsafePointer<UInt8>(bytes! + dataOffset.l), count: dataSize.l))
                
                dataOffset += dataSize
                
                width = max(width >> 1, 1)
                height = max(height >> 1, 1)
            }
            
            success = true
        }
        
        return success
    }
    
    
    fileprivate func createGLTexture() -> Bool {
        var width = self.width
        var height = self.height
        
        /*if ([_imageData count] > 0)
        {
        if (_name != 0)
        glDeleteTextures(1, &_name);
        
        glGenTextures(1, &_name);
        glBindTexture(GL_TEXTURE_2D, _name);
        }*/
        
        for (i, data) in _imageData.enumerated() {
            glCompressedTexImage2D(GL_TEXTURE_2D.ui, i.i, internalFormat, width.i, height.i, 0, data.count.i, (data as NSData).bytes)
            
            let err = glGetError()
            guard err == GL_NO_ERROR.ui else {
                NSLog("Error uploading compressed texture level: \(i). glError: 0x%04X", err)
                return false
            }
            
            width = max(width >> 1, 1)
            height = max(height >> 1, 1)
        }
        
        _imageData.removeAll()
        
        return true
    }
    
    
    init?(contentsOfFile path: String) {
        super.init()
        let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        
        //_name = 0;
        
        if data == nil || !self.unpackPVRData(data!) || !self.createGLTexture() {
            return nil
        }
        
    }
    
    
    convenience init?(contentsOfURL url: URL) {
        guard url.isFileURL else {
            return nil
        }
        
        self.init(contentsOfFile: url.path)
    }
    
    
    //+ (id)pvrTextureWithContentsOfFile:(NSString *)path
    //{
    //	return [[[self alloc] initWithContentsOfFile:path] autorelease];
    //}
    //
    //
    //+ (id)pvrTextureWithContentsOfURL:(NSURL *)url
    //{
    //	if (![url isFileURL])
    //		return nil;
    //
    //	return [PVRTexture pvrTextureWithContentsOfFile:[url path]];
    //}
    //
    //
    //- (void)dealloc
    //{
    //	[_imageData release];
    //
    //	/*if (_name != 0)
    //		glDeleteTextures(1, &_name);*/
    //
    //	[super dealloc];
    //}
    
}
