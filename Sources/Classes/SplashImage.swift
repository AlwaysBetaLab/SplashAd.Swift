//
//  SplashImage.swift
//  Pods-SplashAd.Swift_Example
//
//  Created by Feijunjie on 2020/1/16.
//

import UIKit
import ImageIO
import MobileCoreServices

class SplashImage {
    /// 内部读取图片帧队列
    private lazy var readFrameQueue: DispatchQueue = DispatchQueue(label: "image.queue", qos: .background)
    /// 图片资源数据
    private var cgImageSource: CGImageSource?
    /// 总动画时长
    var totalDuration: TimeInterval = 0.0
    /// 每一帧对应的动画时长
    var frameDurations: [Int: TimeInterval] = [:]
    /// 每一帧对应的图片
    var frameImages: [Int: UIImage] = [:]
    /// 总图片数
    var frameTotalCount: Int = 0
    /// 兼容之前的 UIImage 使用
    var image: UIImage?

    /// 全局配置
    struct GlobalSetting {
        /// 配置预加载帧的数量
        static var prefetchNumber: Int = 10
        static var minFrameDuration: TimeInterval = 0.01
    }

    /// 兼容 UIImage named 调用
    convenience init?(named name: String!, postfix: String!) {
        guard let path = Bundle.main.path(forResource: name, ofType: postfix) else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        self.init(data: data)
    }

//    ///  TODO 兼容 UIImage contentsOfFile 调用，后期有时间完善
//    convenience init?(contentsOfFile path: String) {
//        guard let url = URL(string: path) else { return nil }
//        guard let data = try? Data(contentsOf: url) else { return nil }
//        self.init(data: data)
//    }
//
//    /// TODO 兼容 UIImage contentsOf 调用，后期有时间完善
//    convenience init?(contentsOf url: URL) {
//        guard let data = try? Data(contentsOf: url) else { return nil }
//        self.init(data: data)
//    }

    /// 兼容 UIImage data 调用
    convenience init?(data: Data) {
        self.init(data: data, scale: 1.0)
    }
    
    /// 根据二进制数据初始化【核心初始化方法】
    init?(data: Data, scale: CGFloat) {
        guard let cgImageSource = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        self.cgImageSource = cgImageSource
        if SplashImage.isCGImageSourceContainAnimatedGIF(cgImageSource: cgImageSource) {
            initGIFSource(cgImageSource: cgImageSource)
        } else {
            image = UIImage(data: data, scale: scale)
        }
    }
    
    /// 判断图片数据源包含 GIF 信息
    private class func isCGImageSourceContainAnimatedGIF(cgImageSource: CGImageSource) -> Bool {
        guard let type = CGImageSourceGetType(cgImageSource) else { return false }
        let isGIF = UTTypeConformsTo(type, kUTTypeGIF)
        let imgCount = CGImageSourceGetCount(cgImageSource)
        return isGIF && imgCount > 1
    }
    
    /// 获取图片数据源的第 index 帧图片的动画时间
    private class func getCGImageSourceGifFrameDelay(imageSource: CGImageSource, index: Int) -> TimeInterval {
        var delay = 0.0
        guard let imgProperties: NSDictionary = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) else { return delay }
        // 获取该帧图片的属性字典
        if let property = imgProperties[kCGImagePropertyGIFDictionary as String] as? NSDictionary {
            // 获取该帧图片的动画时长
            if let unclampedDelayTime = property[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber {
                delay = unclampedDelayTime.doubleValue
                if delay <= 0, let delayTime = property[kCGImagePropertyGIFDelayTime as String] as? NSNumber {
                    delay = delayTime.doubleValue
                }
            }
        }
        return delay
    }
    
    /// 根据图片数据源初始化，设置动画总时长、总帧数等属性
    private func initGIFSource(cgImageSource: CGImageSource) {
        let numOfFrames = CGImageSourceGetCount(cgImageSource)
        frameTotalCount = numOfFrames
        for index in 0..<numOfFrames {
            // 获取每一帧的动画时长
            let frameDuration = SplashImage.getCGImageSourceGifFrameDelay(imageSource: cgImageSource, index: index)
            self.frameDurations[index] = max(GlobalSetting.minFrameDuration, frameDuration)
            self.totalDuration += frameDuration
            // 一开始初始化预加载一定数量的图片，而不是全部图片
            if index < GlobalSetting.prefetchNumber {
                if let cgimage = CGImageSourceCreateImageAtIndex(cgImageSource, index, nil) {
                    let image: UIImage = UIImage(cgImage: cgimage)
                    if index == 0 {
                        self.image = image
                    }
                    self.frameImages[index] = image
                }
            }
        }
    }

    /// 获取某一帧图片
    func getFrame(index: Int) -> UIImage? {
        guard index < frameTotalCount else { return image ?? nil }
        // 取当前帧图片
        let currentImage = self.frameImages[index] ?? self.image
        // 如果总帧数大于预加载数，需要加载后面未加载的帧图片
        if frameTotalCount > GlobalSetting.prefetchNumber {
            // 清除当前帧图片缓存数据，空出内存
            if index != 0 {
                self.frameImages[index] = nil
            }
            // 加载后面帧图片到内存
            for i in 1...GlobalSetting.prefetchNumber {
                let idx = (i + index) % frameTotalCount
                if self.frameImages[idx] == nil {
                    // 默认加载第一张帧图片为占位，防止多次加载
                    self.frameImages[idx] = self.frameImages[0]
                    self.readFrameQueue.async { [weak self] in
                        guard let strongSelf = self, let cgImageSource = strongSelf.cgImageSource else { return }
                        guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, idx, nil) else { return }
                        strongSelf.frameImages[idx] = UIImage(cgImage: cgImage)
                    }
                }
            }
        }
        return currentImage
    }
}
