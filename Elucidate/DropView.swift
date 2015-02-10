//
//  DropView.swift
//  Elucidate
//
//  Created by Harry Shamansky on 1/25/15.
//  Copyright (c) 2015 Harry Shamansky. All rights reserved.
//

import Cocoa

class DropView: NSView, NSPasteboardItemDataProvider, NSDraggingDestination {

    var delegate: DropViewDelegate?
    var highlight = false
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.registerForDraggedTypes([NSFilenamesPboardType])
    }
    
    override func drawRect(dirtyRect: NSRect) {
        super.drawRect(dirtyRect)
        if highlight {
            NSColor.grayColor().set()
            NSBezierPath.setDefaultLineWidth(5.0)
            NSBezierPath.strokeRect(dirtyRect)
        }
    }
    
    // MARK: Pasteboard Item Data Provider
    func pasteboard(pasteboard: NSPasteboard!, item: NSPasteboardItem!, provideDataForType type: String!) {
        NSLog("This happened")
        return
    }
    
    // MARK: Dragging
    override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
        highlight = true
        self.needsDisplay = true
        return NSDragOperation.Copy
    }
    
    override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
        return NSDragOperation.Copy
    }
    
    override func draggingExited(sender: NSDraggingInfo?) {
        highlight = false
        self.needsDisplay = true
        return
    }
    
    override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
        highlight = false
        self.needsDisplay = true
        return true
    }
    
    override func performDragOperation(sender: NSDraggingInfo) -> Bool {

        let pBoard = sender.draggingPasteboard()
        let URLs = pBoard.readObjectsForClasses([NSURL.self], options: nil) as! [NSURL]
        
        for u in URLs {
            self.delegate?.processFileWithURL(u)
        }
        
        return true
    }
    
    override func concludeDragOperation(sender: NSDraggingInfo?) {
        return
    }
    
    
}

protocol DropViewDelegate {
    func processFileWithURL(URL: NSURL)
}