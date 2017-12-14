//
//  VideoMesh.swift
//  testPKTRecognitionFrameworkApp
//
//  Created by Roberto Avanzi on 16/08/16.
//  Copyright © 2016 Pikkart. All rights reserved.
//

import UIKit

open class VideoMesh: NSObject {
    
    fileprivate var parentCtrl:UIViewController?
    
    fileprivate var mVertices:[Float] = []
    fileprivate var mTexCoords:[Float] = []
    fileprivate var mNormals:[Float] =  []
    fileprivate var mIndex:[UInt16] =  []
    
    fileprivate var mIndices_Number:Int = 0;
    fileprivate var mVertices_Number:Int = 0;
    fileprivate var mKeyframeTexture_GL_ID:Int = 0
    fileprivate var mIconBusyTexture_GL_ID:Int = 0
    fileprivate var mIconPlayTexture_GL_ID:Int = 0
    fileprivate var mIconErrorTexture_GL_ID:Int = 0
    fileprivate var mVideoTexture_GL_ID:Int = 0
    
    fileprivate var mVideo_Program_GL_ID:Int = 0
    fileprivate var mKeyframe_Program_GL_ID:Int = 0
    fileprivate var mPikkartVideoPlayer:PikkartVideoPlayer!
    fileprivate var mMovieUrl:String = ""
    fileprivate var mSeekPosition:Int = 0
    fileprivate var mAutostart:Bool = false
    
    fileprivate var keyframeAspectRatio:Float = 1.0
    fileprivate var videoAspectRatio:Float = 1.0
    
    fileprivate var mTexCoordTransformationMatrix:[Float] = []
    fileprivate var videoTextureCoords:[Float] = [0.0,1.0,1.0, 1.0,1.0, 0.0,0.0, 0.0]
    fileprivate var videoTextureCoordsTransformed:[Float] = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0]
    fileprivate var mVideoTexCoords:[Float] = [0.0,1.0,1.0, 1.0,1.0, 0.0,0.0, 0.0]

    
    open var videoPlayer:PikkartVideoPlayer {
        get {
            return mPikkartVideoPlayer
        }
        set {
            mPikkartVideoPlayer = newValue
        }
    }
    
    internal static let VERTEX_SHADER:String = "\n\n"+"attribute vec4 vertexPosition;\n"+"attribute vec2 vertexTexCoord;\n\n"+"varying vec2 texCoord;\n\n"+"uniform mat4 modelViewProjectionMatrix;\n\n"+"void main() \n{\n"+"   gl_Position = modelViewProjectionMatrix * vertexPosition;\n"+"   texCoord = vertexTexCoord;\n"+"}\n"
    
    internal static let KEYFRAME_FRAGMENT_SHADER:String = "\n\n"+"precision mediump float;\n\n"+"varying vec2 texCoord;\n\n"+"uniform sampler2D texSampler2D;\n\n"+"void main()\n{\n"+"   gl_FragColor = texture2D(texSampler2D, texCoord);\n"+"}\n"
    
    internal static let  VIDEO_FRAGMENT_SHADER:String = " \n"
    + "precision mediump float; \n"
    + "varying vec2 texCoord; \n"
    + "uniform sampler2D texSamplerOES; \n" + " \n"
    + "void main() { \n"
    + "   gl_FragColor = texture2D(texSamplerOES, texCoord); \n"
    + "} \n"
    
    fileprivate func GenerateMesh() -> Bool {
        mVertices = [ 0.0, 0.0, 0.0,
                      1.0, 0.0, 0.0,
                      1.0, 1.0, 0.0,
                      0.0, 1.0, 0.0 ]
        mVertices_Number = 4
        mTexCoords = [ 0.0, 1.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0]
        mNormals = [ 0.0, 0.0, 1.0,
                     0.0, 0.0, 1.0,
                     0.0, 0.0, 1.0,
                     0.0, 0.0, 1.0]
        
        mIndex = [0, 1, 2, 2, 3, 0]
        mIndices_Number = 6
        
        return true
    }
    
    //MARK: init method
    init(parentCtrl:UIViewController) {
        self.parentCtrl = parentCtrl;
        super.init()
    }
    
    open func InitMesh(_ movieUrl:String, keyFrameUrl:String, seekPosition:Int, autostart:Bool, videoPlayer:PikkartVideoPlayer?) -> Bool {
        
        GenerateMesh()
        
        if (videoPlayer == nil) {
            self.videoPlayer = PikkartVideoPlayer()
        } else {
            self.videoPlayer = videoPlayer!
        }
        var dims:CGSize = CGSize.zero
        
        self.mMovieUrl = movieUrl
        self.mKeyframeTexture_GL_ID = RenderUtils.loadTextureFromFileName(keyFrameUrl, dims: &dims)
        self.keyframeAspectRatio = Float(dims.height/dims.width)
        self.mSeekPosition = seekPosition
        self.mAutostart = autostart
        
        let mediaBundlePath=Bundle.main.bundlePath+"/media.bundle"
        let mediaBundle=Bundle(path: mediaBundlePath)
        self.mIconBusyTexture_GL_ID = RenderUtils.loadTextureFromFileName(mediaBundle!.path(forResource: "busy", ofType: "png")!)
        self.mIconPlayTexture_GL_ID = RenderUtils.loadTextureFromFileName(mediaBundle!.path(forResource: "play", ofType: "png")!)
        self.mIconErrorTexture_GL_ID = RenderUtils.loadTextureFromFileName(mediaBundle!.path(forResource: "error", ofType: "png")!)
        
        self.mKeyframe_Program_GL_ID = RenderUtils.createProgram(VideoMesh.VERTEX_SHADER, fragmentShaderSrc: VideoMesh.KEYFRAME_FRAGMENT_SHADER)
        self.mVideo_Program_GL_ID = RenderUtils.createProgram(VideoMesh.VERTEX_SHADER, fragmentShaderSrc: VideoMesh.VIDEO_FRAGMENT_SHADER)
        
        self.mVideoTexture_GL_ID = RenderUtils.createVideoTexture();
        
        if (self.mVideoTexture_GL_ID != 0) {
            self.videoPlayer.videoTextureHandle = GLuint(self.mVideoTexture_GL_ID)
            self.videoPlayer.load(movieUrl, playImmediately: autostart, seekPosition: Float(seekPosition))
        }
        
        return true
    }
    
    open func reloadOnAppear() {
        if self.mPikkartVideoPlayer != nil {
            if (self.mVideoTexture_GL_ID != 0) {
                self.videoPlayer.videoTextureHandle = GLuint(self.mVideoTexture_GL_ID)
                self.videoPlayer.load(self.mMovieUrl, playImmediately: self.mAutostart  , seekPosition: Float(self.mSeekPosition))
            }
        }
    }
    
    open func pauseVideo() {
        if self.mPikkartVideoPlayer != nil {
            let status:PikkartVideoPlayer.VIDEO_STATE = self.mPikkartVideoPlayer.videoStatus
            if (status == .playing) {
                self.mPikkartVideoPlayer.pause()
            }
        }
    }
    
    open func playOrPauseVideo() {
        if self.mPikkartVideoPlayer != nil {
            let status:PikkartVideoPlayer.VIDEO_STATE = self.mPikkartVideoPlayer.videoStatus
            if (status == .playing) {
                self.mPikkartVideoPlayer.pause()
            } else if (status == .reached_END ||
                       status == .paused ||
                       status == .ready ||
                       status == .stopped) {
                self.mPikkartVideoPlayer.play(Float(self.mSeekPosition))
            }
        }
    }
    
    fileprivate func setVideoDimensions(_ videoWidth:Float, videoHeight:Float, textureCoordMatrix:[Float]) {
    
        videoAspectRatio = videoHeight / videoWidth;

        let mtx:[Float] = textureCoordMatrix
        var tempUVMultRes:[Float]

        tempUVMultRes = uvMultMat4f(videoTextureCoordsTransformed[0], transformedV: videoTextureCoordsTransformed[1],
                                    u: videoTextureCoords[0], v: videoTextureCoords[1], pMat: mtx)
        videoTextureCoordsTransformed[0] = tempUVMultRes[0]
        videoTextureCoordsTransformed[1] = tempUVMultRes[1]

        tempUVMultRes = uvMultMat4f(videoTextureCoordsTransformed[2], transformedV: videoTextureCoordsTransformed[3],
                                    u: videoTextureCoords[2], v: videoTextureCoords[3], pMat: mtx)
        videoTextureCoordsTransformed[2] = tempUVMultRes[0]
        videoTextureCoordsTransformed[3] = tempUVMultRes[1]

        tempUVMultRes = uvMultMat4f(videoTextureCoordsTransformed[4], transformedV: videoTextureCoordsTransformed[5],
                                    u: videoTextureCoords[4], v: videoTextureCoords[5], pMat: mtx)
        videoTextureCoordsTransformed[4] = tempUVMultRes[0]
        videoTextureCoordsTransformed[5] = tempUVMultRes[1]

        tempUVMultRes = uvMultMat4f(videoTextureCoordsTransformed[6], transformedV: videoTextureCoordsTransformed[7],
                                    u: videoTextureCoords[6], v: videoTextureCoords[7], pMat: mtx)
        videoTextureCoordsTransformed[6] = tempUVMultRes[0]
        videoTextureCoordsTransformed[7] = tempUVMultRes[1]
    }
    
    fileprivate func uvMultMat4f(_ transformedU:Float, transformedV:Float, u:Float, v:Float, pMat:[Float]) -> [Float] {
        let x = pMat[0] * u + pMat[4] * v + pMat[12] * 1.0
        let y = pMat[1] * u + pMat[5] * v + pMat[13] * 1.0
        var result = [Float]()
        result[0] = x
        result[1] = y
        return result
    }
    
    fileprivate func DrawKeyFrame(_ mvpMatrix:UnsafePointer<Float>) {
    
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))

        glUseProgram(GLuint(mKeyframe_Program_GL_ID))

        RenderUtils.checkGLError()

        let vertexHandle = glGetAttribLocation(GLuint(mKeyframe_Program_GL_ID), "vertexPosition")
        let textureCoordHandle = glGetAttribLocation(GLuint(mKeyframe_Program_GL_ID), "vertexTexCoord")
        let mvpMatrixHandle = glGetUniformLocation(GLuint(mKeyframe_Program_GL_ID), "modelViewProjectionMatrix")
        let texSampler2DHandle = glGetUniformLocation(GLuint(mKeyframe_Program_GL_ID), "texSampler2D")

        RenderUtils.checkGLError()

        glVertexAttribPointer(GLuint(vertexHandle), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mVertices)
        glVertexAttribPointer(GLuint(textureCoordHandle), 2,GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mTexCoords)


        glEnableVertexAttribArray(GLuint(vertexHandle))
        glEnableVertexAttribArray(GLuint(textureCoordHandle))

        RenderUtils.checkGLError()

        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mKeyframeTexture_GL_ID))
        glUniform1i(texSampler2DHandle, 0)

        RenderUtils.checkGLError()

        glPushGroupMarkerEXT(0, "Draw Pikkart KeyFrame");

        glUniformMatrix4fv(mvpMatrixHandle, 1, GLboolean(GL_FALSE), mvpMatrix)

        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(mIndices_Number), GLenum(GL_UNSIGNED_SHORT), mIndex)

        glPopGroupMarkerEXT();

        RenderUtils.checkGLError()

        glDisableVertexAttribArray(GLuint(vertexHandle))
        glDisableVertexAttribArray(GLuint(textureCoordHandle))
        
        RenderUtils.checkGLError()

        glUseProgram(0)
        glDisable(GLenum(GL_BLEND))

        RenderUtils.checkGLError()

    }
    
    fileprivate func DrawVideo(_ mvpMatrix:[Float]) {
        
        glUseProgram(GLuint(mVideo_Program_GL_ID))

        let vertexHandle = glGetAttribLocation(GLuint(mVideo_Program_GL_ID), "vertexPosition");
        let textureCoordHandle = glGetAttribLocation(GLuint(mVideo_Program_GL_ID), "vertexTexCoord");
        let mvpMatrixHandle = glGetUniformLocation(GLuint(mVideo_Program_GL_ID), "modelViewProjectionMatrix");
        let texSampler2DHandle = glGetUniformLocation(GLuint(mVideo_Program_GL_ID), "texSamplerOES");

        RenderUtils.checkGLError()

        glVertexAttribPointer(GLuint(vertexHandle), 3, GLenum(GL_FLOAT), GLboolean(0), 0, mVertices)
        glVertexAttribPointer(GLuint(textureCoordHandle), 2, GLenum(GL_FLOAT), GLboolean(0), 0, videoTextureCoordsTransformed)

        glEnableVertexAttribArray(GLuint(vertexHandle))
        glEnableVertexAttribArray(GLuint(textureCoordHandle))

        RenderUtils.checkGLError()

        glActiveTexture(GLenum(GL_TEXTURE0));
        glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mVideoTexture_GL_ID))
        glUniform1i(texSampler2DHandle, 0)

        RenderUtils.checkGLError()

        glUniformMatrix4fv(mvpMatrixHandle, 1, GLboolean(0), mvpMatrix)

        // Render
        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(mIndices_Number), GLenum(GL_UNSIGNED_SHORT), mIndex)

        RenderUtils.checkGLError()

        glUseProgram(0)
        
        glDisableVertexAttribArray(GLuint(vertexHandle))
        glDisableVertexAttribArray(GLuint(textureCoordHandle))
        
        RenderUtils.checkGLError()

    }

    fileprivate func DrawIcon(_ mvpMatrix:[Float], status:PikkartVideoPlayer.VIDEO_STATE ) {
        
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA));

        glUseProgram(GLuint(mKeyframe_Program_GL_ID))

        RenderUtils.checkGLError()

        let vertexHandle = glGetAttribLocation(GLuint(mKeyframe_Program_GL_ID), "vertexPosition")
        let textureCoordHandle = glGetAttribLocation(GLuint(mKeyframe_Program_GL_ID), "vertexTexCoord")
        let mvpMatrixHandle = glGetUniformLocation(GLuint(mKeyframe_Program_GL_ID), "modelViewProjectionMatrix")
        let texSampler2DHandle = glGetUniformLocation(GLuint(mKeyframe_Program_GL_ID), "texSampler2D")

        glVertexAttribPointer(GLuint(vertexHandle), 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mVertices);
        glVertexAttribPointer(GLuint(textureCoordHandle), 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, mTexCoords);

        RenderUtils.checkGLError()

        glEnableVertexAttribArray(GLuint(vertexHandle))
        glEnableVertexAttribArray(GLuint(textureCoordHandle))

        RenderUtils.checkGLError()

        glActiveTexture(GLenum(GL_TEXTURE0))
        
        switch (status.rawValue) {
            case 0://end
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconPlayTexture_GL_ID))
            
            case 1://pasued
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconPlayTexture_GL_ID))
            
            case 2://stopped
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconPlayTexture_GL_ID))
            
            case 3://playing
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconPlayTexture_GL_ID))
            
            case 4://ready
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconPlayTexture_GL_ID))
            
            case 5://not ready
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconBusyTexture_GL_ID))
            
            case 6://buffering
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconBusyTexture_GL_ID))
            
            case 7://error
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconErrorTexture_GL_ID))
            
            default:
                glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(mIconBusyTexture_GL_ID))
            
        }
        RenderUtils.checkGLError()

        glUniform1i(texSampler2DHandle, 0)

        glUniformMatrix4fv(mvpMatrixHandle, 1, GLboolean(GL_FALSE), mvpMatrix)

        RenderUtils.checkGLError()

        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(mIndices_Number), GLenum(GL_UNSIGNED_SHORT), mIndex)

        
        RenderUtils.checkGLError()

        glUseProgram(0)
        
        glDisable(GLenum(GL_BLEND))
        glDisableVertexAttribArray(GLuint(vertexHandle))
        glDisableVertexAttribArray(GLuint(textureCoordHandle))
        
        RenderUtils.checkGLError()

    }
    
    open func DrawMesh(_ modelView:[Float], projection:[Float])
    {
        let viewCtrl:ViewController? = parentCtrl as? ViewController
        
        if (viewCtrl != nil) {
            var currentStatus = PikkartVideoPlayer.VIDEO_STATE.not_READY;
            if(mPikkartVideoPlayer != nil) {
                currentStatus = mPikkartVideoPlayer.videoStatus
                if (currentStatus == .playing) {
                    mPikkartVideoPlayer.updateVideoData()
                    videoAspectRatio = Float(mPikkartVideoPlayer.videoSize.height/mPikkartVideoPlayer.videoSize.width)
                }
            }
            
            let currentMarker = viewCtrl!.getCurrentMarker()
            if (currentMarker != nil) {
                let width=CGFloat(currentMarker!.width)
                let height=CGFloat(currentMarker!.height)
                let markerSize = CGSize(width:width,height:height)
                glEnable(GLenum(GL_DEPTH_TEST))
                glDisable(GLenum(GL_CULL_FACE))
                
                if ((currentStatus == .ready)
                    || (currentStatus == .reached_END)
                    || (currentStatus == .not_READY)
                    || (currentStatus == .error)) {
                    
                    var scaleMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    RenderUtils.createIdentity(UnsafeMutablePointer(mutating:scaleMatrix))
                    scaleMatrix[0]=Float(markerSize.width)
                    scaleMatrix[5]=Float(markerSize.width) * keyframeAspectRatio;
                    scaleMatrix[10]=Float(markerSize.width)
                    
                    var temp_mv:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating: modelView), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating:scaleMatrix), result: UnsafeMutablePointer(mutating:temp_mv))
                    
                    var temp_mvp:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating:projection), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating: temp_mv), result: UnsafeMutablePointer(mutating: temp_mvp))

                    var mvpMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    
                    RenderUtils.makeTranspose(UnsafeMutablePointer(mutating:temp_mvp),
                                              m_out: UnsafeMutablePointer(mutating:mvpMatrix))

                    DrawKeyFrame(mvpMatrix);
                } else
                {
                    
                    var scaleMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    RenderUtils.createIdentity(UnsafeMutablePointer(mutating:scaleMatrix))
                    scaleMatrix[0]=Float(markerSize.width)
                    scaleMatrix[5]=Float(markerSize.width) * videoAspectRatio;
                    scaleMatrix[10]=Float(markerSize.width)
                    
                    
                    var temp_mv:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating:modelView), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating:scaleMatrix), result: UnsafeMutablePointer(mutating:temp_mv))
                    
                    
                    var temp_mvp:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating:projection), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating:temp_mv), result: UnsafeMutablePointer(mutating:temp_mvp))
                    
                    var mvpMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
                    
                    RenderUtils.makeTranspose(UnsafeMutablePointer(mutating:temp_mvp),
                                              m_out: UnsafeMutablePointer(mutating:mvpMatrix))
                    
                    DrawVideo(mvpMatrix)
                }
                
                if ((currentStatus == .ready)
                    || (currentStatus == .reached_END)
                    || (currentStatus == .paused)
                    || (currentStatus == .not_READY)
                    || (currentStatus == .error)) {
                    
                    var translateMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

                    RenderUtils.createIdentity(UnsafeMutablePointer(mutating:translateMatrix))
                    //scale a bit
                    translateMatrix[0] = 0.4
                    translateMatrix[5] = 0.4
                    translateMatrix[10] = 0.4
                    //translate a bit
                    translateMatrix[3] = 0.0
                    translateMatrix[7] = 0.45
                    translateMatrix[11] = -0.05
                    
                    var temp_mv:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating:modelView), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating:translateMatrix), result: UnsafeMutablePointer(mutating:temp_mv))
                    
                    var temp_mvp:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

                    RenderUtils.makeMatrixMultiply(4, cols1: 4, mat1: UnsafeMutablePointer(mutating:projection), row1: 4, cols2: 4, mat2: UnsafeMutablePointer(mutating:temp_mv), result: UnsafeMutablePointer(mutating:temp_mvp))
                    
                    var mvpMatrix:[Float] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]

                    RenderUtils.makeTranspose(UnsafeMutablePointer(mutating:temp_mvp),
                                              m_out: UnsafeMutablePointer(mutating:mvpMatrix))
                    
                    DrawIcon(mvpMatrix, status: currentStatus)
                }
                RenderUtils.checkGLError()
            }

        }
    }
    
    open func isPlaying() -> Bool {
        
        if (mPikkartVideoPlayer != nil) {
            if(mPikkartVideoPlayer.videoStatus == .playing ||
                mPikkartVideoPlayer.videoStatus == .paused){
                return true;
            }
        }
        return false;
    }

    
}
