//
//  UIView+Wiggle.swift
//  Magic Board
//
//  Created by Josh Birnholz on 2/15/20.
//  Copyright © 2020 Josh Birnholz. All rights reserved.
//

import UIKit

extension UIView {
    
    private struct AnimationKey {
        static let Rotation = "rotation"
        static let Bounce = "bounce"
    }
    
	public func startWiggle(durationModifier: Double = 1.0, varianceModifier: Double = 1.0, angleModifier: Double = 1.0, bounceModifier: Double = 1.0){
		
        let wiggleBounceY = 2.0 * bounceModifier
        let wiggleBounceDuration = 0.18 * durationModifier
        let wiggleBounceDurationVariance = 0.025 * varianceModifier
        
        let wiggleRotateAngle = 0.02 * angleModifier
        let wiggleRotateDuration = 0.14 * durationModifier
        let wiggleRotateDurationVariance = 0.025 * varianceModifier
        
        guard // If the view is already animating rotation or bounce, return
            layer.animation(forKey: AnimationKey.Rotation) == nil,
			layer.animation(forKey: AnimationKey.Bounce) == nil
        else {
            return
        }
        
        //Create rotation animation
        let rotationAnimation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.values = [-wiggleRotateAngle, wiggleRotateAngle]
        rotationAnimation.autoreverses = true
        rotationAnimation.duration = randomize(interval: wiggleRotateDuration, withVariance: wiggleRotateDurationVariance)
        rotationAnimation.repeatCount = .infinity
        
        //Create bounce animation
        let bounceAnimation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounceAnimation.values = [wiggleBounceY, 0]
        bounceAnimation.autoreverses = true
        bounceAnimation.duration = randomize(interval: wiggleBounceDuration, withVariance: wiggleBounceDurationVariance)
        bounceAnimation.repeatCount = .infinity
        
        //Apply animations to view
        UIView.animate(withDuration: 0) {
            self.layer.add(rotationAnimation, forKey: AnimationKey.Rotation)
            self.layer.add(bounceAnimation, forKey: AnimationKey.Bounce)
            self.transform = .identity
        }
    }
    
    public func stopWiggle(){
        layer.removeAnimation(forKey: AnimationKey.Rotation)
        layer.removeAnimation(forKey: AnimationKey.Bounce)
    }
    
    // Utility
    
    private func randomize(interval: TimeInterval, withVariance variance: Double) -> Double{
        let random = (Double(arc4random_uniform(1000)) - 500.0) / 500.0
        return interval + variance * random
    }
}
