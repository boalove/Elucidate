//
//  ElucidatePDFManager.swift
//  Elucidate
//
//  Created by Harry Shamansky on 2/1/15.
//  Copyright (c) 2015 Harry Shamansky. All rights reserved.
//

import Cocoa

class ElucidatePDFManager: NSObject, TesseractDelegate {

    internal var progress: Double = 0.0
    internal var totalPagesToProcess = 1
    internal var currentPage = 0
    internal var delegate: ElucidatePDFManagerDelegate?
    internal var tag = 0
    internal var shouldCancel = false
    
    private var skew: Float = 0.0
    
    /// Runs a PDF file through Tesseract, and creates a searchable PDF, splits the pages, and adjusts the tilt
    /// based on boolean flags
    ///
    /// :param: URL The URL of the source PDF.
    /// :param: recognizeText Whether or not to draw text on the PDF that's output.
    /// :param: splitPages Whether or not to split pages if a side-by-side page is detected.
    /// :param: adjustTilt Whether or not to rotate the scanned image so it appears perfectly straight.
    /// :param: fileSuffix Optional suffix that's appended to the file output. If null, then overwrite.
    internal func processFileWithURL(URL: NSURL, recognizeText: Bool, splitPages: Bool, adjustTilt: Bool, fileSuffix: String?) {
        
        // nested function that actually draws the text
        func drawText(pdfContext: CGContext, textlines: [[String : AnyObject]], cropRect: NSRect) {
            for line in textlines {
                
                // nested function that checks for descenders and returns true or false for a given string
                func descendersPresent(text: String) -> Bool {
                    // just loop through string and die immediately instead of using string methods
                    for char in text {
                        if char == "g" || char == "y" || char == "p" || char == "j" || char == "q" || char == "Q" {
                            return true
                        }
                    }
                    return false
                }
                
                // find the maximum height font that we can accomodate in the bounding box
                let frameRect = line["boundingbox"] as! NSValue
                var fontSize = 11.0
                if skew == 0.0 || adjustTilt {
                    fontSize = fontSizeForBoundingHeight(Double((frameRect.rectValue).size.height) / 2, startingFontName: "Times New Roman", startingFontSize: 11.0, text: line["text"] as! String)
                }
                
                
                let originalRect = frameRect.rectValue
                var font: CTFont = CTFontCreateWithName("Times New Roman", CGFloat(fontSize), nil)
                // Tesseract starts the bounding box at the bottom of the descenders.
                // CoreText lets the descenders extend below. Offset to account for this.
                let descenderOffset = (descendersPresent(line["text"] as! String)) ? CTFontGetDescent(font) : 0.0
                let convertedRect = CGRectMake((originalRect.origin.x / 2) + cropRect.origin.x, descenderOffset + (cropRect.size.height - (originalRect.origin.y / 2) - (originalRect.height / 2)) + cropRect.origin.y, (originalRect.width / 2), (originalRect.height / 2))

                let cText = CFAttributedStringCreate(nil, (line["text"] as! String) as CFStringRef, nil)
                let mutableAttributedString = CFAttributedStringCreateMutableCopy(nil, 0, cText)
                CFAttributedStringSetAttribute(mutableAttributedString, CFRangeMake(0, count(line["text"] as! String)), kCTFontAttributeName, font)
                CFAttributedStringSetAttribute(mutableAttributedString, CFRangeMake(0, CFStringGetLength((line["text"] as! String) as CFStringRef)), kCTForegroundColorAttributeName, CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.0))
                
                CGContextSetTextMatrix(pdfContext, CGAffineTransformIdentity)
                
                var lineToDraw = CTLineCreateWithAttributedString(mutableAttributedString)
                lineToDraw = CTLineCreateJustifiedLine(lineToDraw, 1.0, Double((frameRect.rectValue).size.width) / 2)
                CGContextSetTextPosition(pdfContext, convertedRect.origin.x, convertedRect.origin.y)
                CTLineDraw(lineToDraw, pdfContext)
            }
        }
        
        // TODO: Make sure we have permission to open the PDF. Or ask for password if we don't.
        
        // work on the file in a temporary directory, then move it to the output
        let fileManager = NSFileManager.defaultManager()
        let tempDir = NSTemporaryDirectory()
        let tempURL = NSURL(fileURLWithPath: tempDir.stringByAppendingPathComponent("\(NSUUID().UUIDString)-output.pdf"))
        var err: NSError?
        
        // create PDF data, an NSPDFImageRep, and a CGPDFDocument
        let data = NSData(contentsOfURL: URL)
        let imageRep = NSPDFImageRep(data: data!)
        let document = CGPDFDocumentCreateWithURL(URL)
        
        // die if the document is encrypted
        // TODO: Prompt for a password here
        if CGPDFDocumentIsEncrypted(document) {
            let alert = NSAlert()
            alert.addButtonWithTitle("OK")
            alert.messageText = "PDF Locked"
            alert.informativeText = "Please unlock this PDF and try again."
            alert.alertStyle = NSAlertStyle.WarningAlertStyle
            if let window = self.delegate?.getWindow() {
                dispatch_async(dispatch_get_main_queue(), {
                    alert.beginSheetModalForWindow(window, completionHandler: nil)
                })
            } else {
                dispatch_async(dispatch_get_main_queue(), {
                    alert.runModal()
                    NSLog("PDF Encrypted. Could not open.")
                })
            }
            return
        }
        
        self.totalPagesToProcess = imageRep!.pageCount
        
        // set up Tesseract
        var tesseract: Tesseract? = Tesseract()
        tesseract?.language = "eng"
        tesseract?.setPageSegMode(1)
        tesseract?.delegate = self
        
        // Notify the delegate the conversion has begun
        if let del = self.delegate {
            dispatch_async(dispatch_get_main_queue(), {
                del.conversionDidStart()
            })
        }
        
        // create a PDF drawing context that's sized for the document
        var fullRect = CGPDFPageGetBoxRect(CGPDFDocumentGetPage(document, 1), kCGPDFMediaBox)
        let pdfContext = CGPDFContextCreateWithURL(tempURL, &fullRect, nil)
        
        // for each page in the PDF...
        for i in 0..<imageRep!.pageCount {
            
            if shouldCancel {
                tesseract = nil
                return
            }
            
            // update the NSPDFImageRep
            imageRep!.currentPage = i
            dispatch_async(dispatch_get_main_queue(), {
                self.currentPage = i
            })
            
            let page = CGPDFDocumentGetPage(document, UInt(i + 1))
            
            // get the crop bounds and the media bounds so we can make the correct size page in our output
            var cropRect = CGPDFPageGetBoxRect(page, kCGPDFCropBox)
            var cropData = NSData(bytes: &cropRect, length: sizeof(CGRect))
            
            var mediaRect = CGPDFPageGetBoxRect(page, kCGPDFMediaBox)
            var mediaData = NSData(bytes: &mediaRect, length: sizeof(CGRect))
            
            // create an image from the PDF page
            let image = NSImage(size: imageRep!.size)
            image.lockFocus()
            image.drawRepresentation(imageRep!, inRect: NSRect(x: 0, y: 0, width: imageRep!.size.width, height: imageRep!.size.height))
            image.unlockFocus()
            
            // pass the image to Tesseract and have it recognize
            tesseract?.image = image.blackAndWhite()
            tesseract?.recognize()
            
            // grab the text as lines
            var textlines = tesseract?.getConfidenceByTextline as! [[String : AnyObject]]
            if let tess = tesseract {
                skew = tess.getTilt()
            }
            
            // filter out blank lines
            textlines = textlines.filter({
                ($0["text"] as! String).stringByReplacingOccurrencesOfString(" ", withString: "", options: nil, range: nil).stringByReplacingOccurrencesOfString("\n", withString: "", options: nil, range: nil) != "" })
            
            
            // determine whether or not to split pages
            if splitPages {
                var leftLines: [[String : AnyObject]] = []
                var rightLines: [[String : AnyObject]] = []
                if let splitPoint = pageSplitFromTextlines(textlines, croppedPage: cropRect, leftLines: &leftLines, rightLines: &rightLines) {
                    
                    // draw the left page
                    var leftRect = NSRect(x: cropRect.origin.x, y: cropRect.origin.y, width: CGFloat(splitPoint / 2), height: cropRect.height)
                    var leftData = NSData(bytes: &leftRect, length: sizeof(CGRect))
                    CGPDFContextBeginPage(pdfContext, [(kCGPDFContextCropBox as! String) : leftData, (kCGPDFContextMediaBox as! String) : mediaData])
                    if adjustTilt {
                        rotateContext(pdfContext, skew: -1 * skew, cropRect: cropRect)
                        leftLines = adjustBoundingBoxesForSkew(leftLines, skew: skew, cropRect: cropRect)
                        CGContextDrawPDFPage(pdfContext, page)
                        rotateContext(pdfContext, skew: skew, cropRect: cropRect)
                    } else {
                        CGContextDrawPDFPage(pdfContext, page)
                    }
                    if recognizeText {
                        drawText(pdfContext, leftLines, cropRect)
                    }
                    CGPDFContextEndPage(pdfContext)
                    
                    // draw the right page
                    var rightRect = NSRect(x: cropRect.origin.x + CGFloat(splitPoint / 2), y: cropRect.origin.y, width: cropRect.width - CGFloat(splitPoint / 2), height: cropRect.height)
                    var rightData = NSData(bytes: &rightRect, length: sizeof(CGRect))
                    CGPDFContextBeginPage(pdfContext, [(kCGPDFContextCropBox as! String) : rightData, (kCGPDFContextMediaBox as! String) : mediaData])
                    if adjustTilt {
                        rotateContext(pdfContext, skew: -1 * skew, cropRect: cropRect)
                        rightLines = adjustBoundingBoxesForSkew(rightLines, skew: skew, cropRect: cropRect)
                        CGContextDrawPDFPage(pdfContext, page)
                        rotateContext(pdfContext, skew: skew, cropRect: cropRect)
                    } else {
                        CGContextDrawPDFPage(pdfContext, page)
                    }
                    if recognizeText {
                        drawText(pdfContext, rightLines, cropRect)
                    }
                    CGPDFContextEndPage(pdfContext)
                } else {
                    CGPDFContextBeginPage(pdfContext, [(kCGPDFContextCropBox as! String) : cropData, (kCGPDFContextMediaBox as! String) : mediaData])
                    if adjustTilt {
                        rotateContext(pdfContext, skew: -1 * skew, cropRect: cropRect)
                        textlines = adjustBoundingBoxesForSkew(textlines, skew: skew, cropRect: cropRect)
                        CGContextDrawPDFPage(pdfContext, page)
                        rotateContext(pdfContext, skew: skew, cropRect: cropRect)
                    } else {
                        CGContextDrawPDFPage(pdfContext, page)
                    }
                    if recognizeText {
                        drawText(pdfContext, textlines, cropRect)
                    }
                    CGPDFContextEndPage(pdfContext)
                }
            } else {
                // draw the full page
                CGPDFContextBeginPage(pdfContext, [(kCGPDFContextCropBox as! String) : cropData, (kCGPDFContextMediaBox as! String) : mediaData])
                if adjustTilt {
                    rotateContext(pdfContext, skew: -1 * skew, cropRect: cropRect)
                    textlines = adjustBoundingBoxesForSkew(textlines, skew: skew, cropRect: cropRect)
                    CGContextDrawPDFPage(pdfContext, page)
                    rotateContext(pdfContext, skew: skew, cropRect: cropRect)
                } else {
                    CGContextDrawPDFPage(pdfContext, page)
                }
                if recognizeText {
                    drawText(pdfContext, textlines, cropRect)
                }
                CGPDFContextEndPage(pdfContext)
            }
            
        }
        CGPDFContextClose(pdfContext)
        
        // overwrite or create a new file depending on options selected
        if shouldCancel {
            tesseract = nil
            return
        }
        if let suffix = fileSuffix {
            if suffix != "" {
                fileManager.moveItemAtPath(tempURL!.path!, toPath: URL.path!.stringByDeletingPathExtension.stringByAppendingFormat(" - %@.pdf", suffix), error: &err)
            } else {
                fileManager.moveItemAtPath(tempURL!.path!, toPath: URL.path!.stringByDeletingPathExtension.stringByAppendingString("- Converted.pdf"), error: &err)
            }
        } else {
            let replacementPath = URL.path
            fileManager.trashItemAtURL(URL, resultingItemURL: nil, error: &err)
            fileManager.moveItemAtPath(tempURL!.path!, toPath: replacementPath!, error: &err)
        }
        
        // Notify the delegate that we've finished converting
        if let del = self.delegate {
            dispatch_async(dispatch_get_main_queue(), {
                del.conversionDidEnd(self)
            })
        }
        
        return
    }
    
    /// Adjusts the bounding boxes of textlines when the page is de-skewed
    ///
    /// :param: textlines The textlines dictionary from Tesseract
    /// :param: skew The amount of skew that was corrected
    /// :param: cropRect The crop box for this page
    ///
    /// :returns: A replacement dictionary of textlines that has corrected bounding boxes.
    private func adjustBoundingBoxesForSkew(textlines: [[String : AnyObject]], skew: Float, cropRect: NSRect) -> [[String : AnyObject]] {
        
        var retLines: [[String : AnyObject]] = []
        
        for line in textlines {
            var newLine: [String : AnyObject] = line
            let lineRect = (line["boundingbox"] as! NSValue).rectValue
            
            // set up the triangle for trig
            let height = lineRect.origin.y - (cropRect.origin.y + (cropRect.height / 2))
            var xOffset = Double(abs(height)) * tan(Double(abs(Double(skew))))
            var yOffset = 200 * abs(skew)
            if skew < 0 && height < 0 || skew > 0 && height > 0 {
                xOffset = -1 * xOffset
            }
            
            var newRect = NSRect(x: lineRect.origin.x - CGFloat(xOffset), y: lineRect.origin.y - CGFloat(yOffset), width: lineRect.width, height: lineRect.height)
            newLine["boundingbox"] = NSValue(rect: newRect)
            retLines.append(newLine)
        }
        return retLines
    }
    
    private func rotateContext(context: CGContext, skew: Float, cropRect: CGRect) {
        CGContextTranslateCTM(context, cropRect.origin.x + (cropRect.width / 2), cropRect.origin.y + (cropRect.height / 2))
        CGContextRotateCTM(context, CGFloat(-1 * skew))
        CGContextTranslateCTM(context, -1 * (cropRect.origin.x + (cropRect.width / 2)), -1 * (cropRect.origin.y + (cropRect.height / 2)))
    }
    
    /// Tests different font sizes for a given height and returns one that will work well
    ///
    /// :param: boundingHeight The height we're trying to fill
    /// :param: startingFontName The name of the font (as a string)
    /// :param: startingFontSize A size to start with
    /// :param: text The string that we need to fit.
    private func fontSizeForBoundingHeight(boundingHeight: Double, startingFontName: String, startingFontSize: Double, text: String) -> Double {
        
        if text.stringByReplacingOccurrencesOfString(" ", withString: "", options: nil, range: nil).stringByReplacingOccurrencesOfString("\n", withString: "", options: nil, range: nil) == "" {
            return startingFontSize
        }
        
        func getLineHeightForFontSize(size: Double) -> Double {
            let font = CTFontCreateWithName(startingFontName, CGFloat(size), nil)
            return Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        }
        
        var startingHeight = getLineHeightForFontSize(startingFontSize)
        var currentSize = startingFontSize
        
        if startingHeight > boundingHeight {
            while startingHeight > boundingHeight {
                currentSize -= 1
                startingHeight = getLineHeightForFontSize(currentSize)
            }
            return currentSize
        } else if startingHeight < boundingHeight {
            while startingHeight < boundingHeight {
                currentSize += 1
                startingHeight = getLineHeightForFontSize(currentSize)
            }
            return currentSize - 1
        } else {
            return startingFontSize
        }
    }
    
    /// Determines whether or not to split the page for a given set of textlines
    ///
    /// :param: textlines The text lines from Tesseract
    /// :param: croppedPage The rectangle representing the cropped area
    /// :param: leftLines A dictionary to represent the textlines on the left page (by reference)
    /// :param: rightLines A dictionary to represent the textlines on the right page (by reference)
    ///
    /// :returns: The correct point to split the page, or nil, indicating that no split is necessary
    private func pageSplitFromTextlines(textlines: [[String : AnyObject]], croppedPage: NSRect, inout leftLines: [[String : AnyObject]], inout rightLines: [[String : AnyObject]]) -> Float? {
        
        // segment the page
        let reorientedPage = NSRect(origin: CGPointZero, size: NSSize(width: croppedPage.width * 2, height: croppedPage.height * 2))
        let trueCenter = reorientedPage.width / 2
        let leftCenter = trueCenter / 2
        let rightCenter = trueCenter + leftCenter
        
        // group the lines
        func centerOfBox(box: NSRect) -> CGFloat {
            return box.origin.x + (box.width / 2)
        }
        
        func closerToLeft(boxCenter: CGFloat, leftCenter: CGFloat, rightCenter: CGFloat) -> Bool {
            return (abs(boxCenter - leftCenter)) < (abs(boxCenter - rightCenter))
        }
        
        var leftMax: CGFloat = leftCenter
        var rightMin: CGFloat = rightCenter
        // place each line on the left or right page
        for line in textlines {
            let rect = (line["boundingbox"] as! NSValue).rectValue
            if closerToLeft(centerOfBox(rect), leftCenter, rightCenter) {
                leftLines.append(line)
                if (rect.origin.x + rect.width) > leftMax {
                    leftMax = (rect.origin.x + rect.width)
                }
            } else {
                rightLines.append(line)
                if rect.origin.x < rightMin {
                    rightMin = rect.origin.x
                }
            }
        }
        
        var potentialSplit = trueCenter
        if leftMax < rightMin {
            
            // check that we don't have a blank page on either side. If we do, use the true center.
            if leftLines.count == 0 || rightLines.count == 0 {
                return Float(trueCenter)
            }
            
            potentialSplit = leftMax + ((rightMin - leftMax) / 2)
            
            // check that none of the rects cross the split point
            let splitRect = NSRect(x: potentialSplit - 1.0, y: 0.0, width: 2.0, height: reorientedPage.height)
            for line in textlines {
                let rect = (line["boundingbox"] as! NSValue).rectValue
                if NSIntersectsRect(rect, splitRect) {
                    NSLog("Failed to split page: Text crossed over potential split point. This could mean that the page need not be split.")
                    return nil
                }
            }
            return Float(potentialSplit)
        }
        return nil
    }
    
    // MARK: TesseractDelegate Methods
    func progressImageRecognitionForTesseract(tesseract: Tesseract!) {
        self.progress = ((Double(self.currentPage) / Double(self.totalPagesToProcess)) * 100) + (Double(tesseract.progress) / Double(self.totalPagesToProcess))
        if let del = self.delegate {
            dispatch_async(dispatch_get_main_queue(), {
                del.progressUpdated()
            })
        }
        
        
    }
    
    func shouldCancelImageRecognitionForTesseract(tesseract: Tesseract!) -> Bool {
        self.progress = ((Double(self.currentPage) / Double(self.totalPagesToProcess)) * 100) + (Double(tesseract.progress) / Double(self.totalPagesToProcess))
        if let del = self.delegate {
            dispatch_async(dispatch_get_main_queue(), {
                del.progressUpdated()
            })
        }
        if self.shouldCancel {
            if let del = self.delegate {
                dispatch_async(dispatch_get_main_queue(), {
                    del.conversionDidEnd(self)
                })
            }
        }
        return self.shouldCancel
    }

}

protocol ElucidatePDFManagerDelegate {
    func getWindow() -> NSWindow?
    func conversionDidStart()
    func progressUpdated()
    func conversionDidEnd(sender: ElucidatePDFManager)
}
