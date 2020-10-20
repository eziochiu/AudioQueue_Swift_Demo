//
//  AdjustFocusView.swift
//  AudioQueueCapture
//
//  Created by admin on 2020/10/19.
//

import UIKit

class AdjustFocusView: UIView {
    fileprivate var orginWidth: CGFloat = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        orginWidth = frame.size.width
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        backgroundColor = .clear
        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(UIColor.yellow.cgColor)
        context?.setLineWidth(2)
        context?.addRect(CGRect(x: 0, y: 0, width: frame.size.width, height: frame.size.height))
        context?.strokePath()
    }
    
    func frameByAnimationCenter(center: CGPoint) {
        isHidden = false
        self.center = center
        UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: .overrideInheritedOptions) {
            self.bounds = CGRect(x: 0, y: 0, width: self.orginWidth - 20, height: self.orginWidth - 20)
        } completion: { (finished) in }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(Int64(2 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) { [self] in
            if bounds.size.width != orginWidth {
                self.isHidden = true
                bounds = CGRect(x: 0, y: 0, width: self.orginWidth, height: self.orginWidth)
            }
        }
    }
}
