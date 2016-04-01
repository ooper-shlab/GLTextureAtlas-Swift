//
//  GLTextureAtlasViewController.swift
//  GLTextureAtlas
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/27.
//
//
/*
     File: GLTextureAtlasViewController.h
     File: GLTextureAtlasViewController.m
 Abstract: The GLTextureAtlasViewController class is a GLKViewController subclass that renders OpenGL scene. It demonstrates how to bind a texture atlas once, and draw multiple objects with different textures using one draw call.
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

import GLKit


private let USE_4_BIT_PVR = false //if false use 2-bit pvr

private let kAnimationSpeed: GLfloat = 0.2 // (0, 1], the bigger the faster

private let NUM_COLS = 4
private let NUM_ROWS = 4

private let NUM_IMPOSTERS = 40

private func CLAMP<T: FloatComputable>(min: T, _ x: T, _ max: T) -> T {return x < min ? min : (x > max ? max : x)}
private func DegreeToRadian<T: FloatComputable>(x: T) -> T {return x * T(M_PI) / 180.0}

// get random float in [-1,1]
private func randf<T: FloatComputable>() -> T {return T(rand() % RAND_MAX) / T(RAND_MAX) * 2.0 - 1.0}

private struct Particle {
    var x: Float = 0.0
    var y: Float = 0.0
    var z: Float = 0.0
    var t: Float = 0.0
    var v: Float = 0.0
    var tx: Float = 0.0
    var ty: Float = 0.0
    var tz: Float = 0.0
    var c: Int32 = 0
}

private var butterflies: [Particle] = Array(count: NUM_IMPOSTERS, repeatedValue: Particle())


private func comp(p1: UnsafePointer<Void>, p2: UnsafePointer<Void>) -> Int32 {
    let d = (UnsafePointer<Particle>(p1)).memory.tz - (UnsafePointer<Particle>(p2)).memory.tz
    if d < 0 {return -1}
    if d > 0 {return 1}
    return p1 > p2 ? 1 : p1 < p2 ? -1 : 0
}

@objc(GLTextureAtlasViewController)
class GLTextureAtlasViewController: GLKViewController {
    //to simulate the fly effect
    private var widthScaleIndex = 0
    private var frameCount = 0
    
    private var textureAtlas: GLuint = 0
    private var pvrTextureAtlas: PVRTexture?
    
    private var inited: Bool = false
    
    private var context: EAGLContext!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.context = EAGLContext(API: .OpenGLES1)
        
        if self.context == nil {
            NSLog("Failed to create ES context")
        }
        
        let view = self.view as! GLKView
        view.context = self.context
        
        EAGLContext.setCurrentContext(self.context)
        
        // load the texture atlas in the PVRTC format
        if USE_4_BIT_PVR {
            self.loadPVRTexture("butterfly_4")
        } else { //use 2-bit pvr
            self.loadPVRTexture("butterfly_2")
        }
        
        // precalc some random normals and velocities
        for i in 0..<NUM_IMPOSTERS {
            var x: Float = randf()
            var y: Float = randf()
            let z: Float = randf()
            if abs(x)<0.1 && abs(y)<0.1 {   //###
                x += (x>0) ? 0.1 : -0.1
                y += (y>0) ? 0.1 : -0.1
            }
            let m = 1.0/sqrt(x*x + y*y + z*z)
            butterflies[i].x = x*m
            butterflies[i].y = y*m
            butterflies[i].z = z*m
            butterflies[i].t = 0
            butterflies[i].v = randf()/2.0; butterflies[i].v += (butterflies[i].v > 0) ? 0.1 : -0.1
            butterflies[i].c = i.i % (NUM_ROWS*NUM_COLS).i
        }
        
        // enable GL states
        glEnableClientState(GL_VERTEX_ARRAY.ui)
        glEnableClientState(GL_TEXTURE_COORD_ARRAY.ui)
        glEnable(GL_TEXTURE_2D.ui)
        glEnable(GL_BLEND.ui)
        glBlendFunc(GL_SRC_ALPHA.ui, GL_ONE_MINUS_SRC_ALPHA.ui)
    }
    
    private func loadPVRTexture(name: String) {
        glGenTextures(1, &textureAtlas)
        glBindTexture(GL_TEXTURE_2D.ui, textureAtlas)
        
        // setup texture parameters
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MAG_FILTER.ui, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_MIN_FILTER.ui, GL_LINEAR)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_WRAP_S.ui, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D.ui, GL_TEXTURE_WRAP_T.ui, GL_CLAMP_TO_EDGE)
        
        pvrTextureAtlas = PVRTexture(contentsOfFile: NSBundle.mainBundle().pathForResource(name, ofType: "pvr")!)
        
        if pvrTextureAtlas == nil {
            NSLog("Failed to load \(name).pvr")
        }
        
        glBindTexture(GL_TEXTURE_2D.ui, 0)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    deinit {
        
        // release the texture atlas
        if textureAtlas != 0 {
            glDeleteTextures(1, &textureAtlas)
            textureAtlas = 0
        }
        pvrTextureAtlas = nil
        
        if EAGLContext.currentContext() === self.context {
            EAGLContext.setCurrentContext(nil)
        }
        self.context = nil
        
    }
    
    
    //MARK: - GLKView and GLKViewController delegate methods
    
    func update() {
        glMatrixMode(GL_PROJECTION.ui)
        glLoadIdentity()
        
        let fov: GLfloat = 60.0, zNear: GLfloat = 0.1, zFar: GLfloat = 1000.0, aspect: GLfloat = 1.5
        let ymax = zNear * tan(fov * M_PI.f / 360.0)
        let ymin = -ymax
        glFrustumf(ymin * aspect, ymax * aspect, ymin, ymax, zNear, zFar)
        
        glMatrixMode(GL_MODELVIEW.ui)
    }

    override func glkView(view: GLKView, drawInRect rect: CGRect) {
        struct My {
            static var s: GLfloat = 1, sz: GLfloat = 1
            static var sanim: GLfloat = 0.001, szanim: GLfloat = 0.002
            static let widthScale: [GLfloat] = [1, 0.8, 0.6, 0.4, 0.2, 0.1, 0.6, 0.8]
            
            private static let texInit: [GLfloat] = Array(count: 8, repeatedValue: 0)
            static var tex: [[GLfloat]] = Array(count: NUM_COLS*NUM_ROWS, repeatedValue: texInit)
            static var indices_all: [GLushort] = Array(count: NUM_IMPOSTERS*6, repeatedValue: 0)
            
            static var pos_tex_all: [GLfloat] = Array(count: NUM_IMPOSTERS*4*(3+2), repeatedValue: 0.0)
        }
        
        
        glClearColor(0.7, 0.9, 0.6, 1.0)
        glClear(GL_COLOR_BUFFER_BIT.ui)
        
        if !inited {
            // compute texture coordinates of each cell
            for i in 0..<NUM_COLS*NUM_ROWS {
                let row = i / NUM_COLS //y
                let col = i % NUM_COLS //x
                
                let left: GLfloat	= col.f		* (1.0/NUM_COLS.f)
                let right: GLfloat	= (col.f+1)	* (1.0/NUM_COLS.f)
                let top: GLfloat		= row.f		* (1.0/NUM_ROWS.f)
                let bottom: GLfloat	= (row.f+1)	* (1.0/NUM_ROWS.f)
                
                // the order of the texture coordinates is:
                //{left, bottom, right, bottom, left, top, right, top}
                My.tex[i][0] = left
                My.tex[i][4] = left
                My.tex[i][2] = right
                My.tex[i][6] = right
                My.tex[i][5] = top
                My.tex[i][7] = top
                My.tex[i][1] = bottom
                My.tex[i][3] = bottom
            }
            
            // build the index array
            for i in 0..<NUM_IMPOSTERS {
                // the first and last additional indices are added to create degenerated triangles
                // between consistent quads. for example, we use the compact index array 0123*34*4567
                // to draw quad 0123 and 4567 using one draw call
                My.indices_all[i*6] = i.us*4
                for j in 0..<4 {
                    My.indices_all[i*6+j+1] = i.us*4+j.us
                }
                My.indices_all[i*6+5] = i.us*4+3
            }
            
            inited = true
        }
        
        // SW transform point to find z order
        for i in 0..<NUM_IMPOSTERS {
            let ax = DegreeToRadian(butterflies[i].x*butterflies[i].t)
            let ay = DegreeToRadian(butterflies[i].y*butterflies[i].t)
            let az = DegreeToRadian(butterflies[i].z*butterflies[i].t)
            let cosx = cos(ax), sinx = sin(ax)
            let cosy = cos(ay), siny = sin(ay)
            let cosz = cos(az), sinz = sin(az)
            let p1 = (sinz * butterflies[i].y + cosz * butterflies[i].x)
            let p2 = (cosy * butterflies[i].z + siny * p1)
            let p3 = (cosz * butterflies[i].y  - sinz * butterflies[i].x)
            butterflies[i].tx = cosy * p1 - siny * butterflies[i].z
            butterflies[i].ty = sinx * p2 + cosx * p3
            butterflies[i].tz = cosx * p2 - sinx * p3
        }
        //(<#T##UnsafeMutablePointer<Void>#>, <#T##Int#>, <#T##Int#>, <#T##((UnsafePointer<Void>, UnsafePointer<Void>) -> Int32)!##((UnsafePointer<Void>, UnsafePointer<Void>) -> Int32)!##(UnsafePointer<Void>, UnsafePointer<Void>) -> Int32#>)
        qsort(&butterflies, NUM_IMPOSTERS, strideof(Particle), comp)
        
        // the interleaved array including position and texture coordinate data of all vertices
        // first position (3 floats) then tex coord (2 floats)
        // NOTE: we want every attribute to be 4-byte left aligned for best performance,
        // so if you use shorts (2 bytes), padding may be needed to achieve that.
        
        // now update the interleaved data array
        for i in 0..<NUM_IMPOSTERS {
            // in order to batch the drawcalls into a single one,
            // we have to drop usage of glMatrix/glTranslate/glRotate/glScale,
            // and do the transformations ourselves.
            
            // rotation around z
            var rotzDegree = butterflies[i].z * butterflies[i].t
            if rotzDegree >= 60.0 || rotzDegree <= -60.0 {
                butterflies[i].v *= -1.0
                rotzDegree = CLAMP(-60.0, rotzDegree, 60.0)
            }
            let rotz = DegreeToRadian(rotzDegree)
            
            // scale along x
            let ind = (i%2 == 0) ? widthScaleIndex : 7-widthScaleIndex //add some noise
            
            // compute the transformation matrix
            
            let Tz   = GLKMatrix4MakeTranslation(0.0, 0.0, -2.0)
            let S    = GLKMatrix4MakeScale(My.widthScale[ind]*0.2, 0.2, 1.0)
            let T    = GLKMatrix4MakeTranslation(butterflies[i].tx*My.s, butterflies[i].ty*My.s, butterflies[i].tz*My.sz)
            let Rz   = GLKMatrix4MakeZRotation(rotz)
            
            var M = GLKMatrix4Multiply(S, Tz)
            M = GLKMatrix4Multiply(T, M)
            M = GLKMatrix4Multiply(Rz, M)
            
            // simple quad data
            // 4D homogeneous coordinates (x,y,z,1)
            var pos: [GLKVector4] = [
                (-1,-1,0,1),	(1,-1,0,1),	(-1,1,0,1),	(1, 1,0,1),
                ].map(GLKVector4.init)
            
            // first, position
            for v in 0..<4 {
                // apply the resulting transformation matrix on each vertex
                let vout = GLKMatrix4MultiplyVector4(M, pos[v])
                
                let temp = i*20+v*5
                My.pos_tex_all[temp + 0] = vout.v.0
                My.pos_tex_all[temp + 1] = vout.v.1
                My.pos_tex_all[temp + 2] = vout.v.2
                My.pos_tex_all[temp + 3] = vout.v.3
            }
            
            // then, tex coord
            for j in 0..<8 {
                let n = i*20 + (j/2)*5 + 3+j%2
                let c = butterflies[i].c
                My.pos_tex_all[n] = My.tex[c.l][j]
            }
            
            butterflies[i].t += butterflies[i].v
        }
        
        // bind the texture atlas ONCE
        glBindTexture(GL_TEXTURE_2D.ui, textureAtlas)
        
        My.pos_tex_all.withUnsafeBufferPointer {buf in
            let pos_tex_all = buf.baseAddress
            glVertexPointer(3, GL_FLOAT.ui, 5*sizeof(GLfloat).i, pos_tex_all)
            glTexCoordPointer(2, GL_FLOAT.ui, 5*sizeof(GLfloat).i, pos_tex_all+3)
        }
        
        // draw all butterflies using ONE single call
        glDrawElements(GL_TRIANGLE_STRIP.ui, NUM_IMPOSTERS.i*6, GL_UNSIGNED_SHORT.ui, My.indices_all)
        
        glBindTexture(GL_TEXTURE_2D.ui, 0)
        
        // update parameters
        
        My.s += My.sanim
        if (My.s >= 1.5) || (My.s <= 1.0) {My.sanim *= -1.0}
        
        My.sz += My.szanim
        if (My.sz >= 1.4) || (My.sz <= -1.2) {My.szanim *= -1.0}
        
        let speed = CLAMP(0, kAnimationSpeed, 1)
        if speed != 0.0 {
            let speedInv = Int(1.0/speed)
            if frameCount % speedInv == 0 {
                // update width scale to simulate the fly effect
                widthScaleIndex = widthScaleIndex < 7 ? widthScaleIndex+1 : 0
            }
            frameCount += 1
        }
    }
    
}