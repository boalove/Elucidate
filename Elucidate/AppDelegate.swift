//
//  AppDelegate.swift
//  Elucidate
//
//  Created by Harry Shamansky on 1/24/15.
//  Copyright (c) 2015 Harry Shamansky. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {



    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

/// runs a closure after a delay
///
/// :param: delay How long to delay the closure (in seconds)
/// :param: closure The closure to call after the delay
func delay(delay:Double, closure:()->()) {
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            Int64(delay * Double(NSEC_PER_SEC))
        ),
        dispatch_get_main_queue(), closure)
}

/// encodes a value as NSData for C code
///
/// :param: value The value to encode
///
/// :returns: An NSData object
func encode<T>(var value: T) -> NSData {
    return withUnsafePointer(&value) { p in
        NSData(bytes: p, length: sizeofValue(value))
    }
}
