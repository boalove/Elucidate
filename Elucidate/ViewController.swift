//
//  ViewController.swift
//  Elucidate
//
//  Created by Harry Shamansky on 1/24/15.
//  Copyright (c) 2015 Harry Shamansky. All rights reserved.
//


// TODO: Check that the computer is plugged in. Warn if it's not.
// TODO: Animated the dropview when a file is dragged overtop of it


import Cocoa

class ViewController: NSViewController, NSTextFieldDelegate, DropViewDelegate, ElucidatePDFManagerDelegate {

    // MARK: IBOutlets
    @IBOutlet weak var outputOptions: NSMatrix!
    @IBOutlet weak var overwriteRadioButton: NSButtonCell!
    @IBOutlet weak var addPrefixRadioButton: NSButtonCell!
    @IBOutlet weak var makeSearchableCheckbox: NSButton!
    @IBOutlet weak var splitPagesCheckbox: NSButton!
    @IBOutlet weak var adjustTiltCheckbox: NSButton!
    @IBOutlet weak var prefixTextField: NSTextField!
    @IBOutlet weak var dropView: DropView!
    
    @IBOutlet weak var dropHereText: NSTextField!
    @IBOutlet weak var inProcessText: NSTextField!
    @IBOutlet weak var progressBar: NSProgressIndicator!
    @IBOutlet weak var detailText: NSTextField!
    @IBOutlet weak var chooseFileButton: NSButton!
    @IBOutlet weak var cancelButton: NSButton!
    
    /// An Array of PDF managers
    var pdfManagers: [ElucidatePDFManager?] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // special setup for first run
        if !NSUserDefaults.standardUserDefaults().boolForKey("hasCompletedInitialSetup") {
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "outputDuplicate")
            NSUserDefaults.standardUserDefaults().setValue("Converted", forKey: "outputSuffix")
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "conversionSearchable")
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "conversionSplitPages")
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "conversionAdjustTilt")
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: "hasCompletedInitialSetup")
            NSUserDefaults.standardUserDefaults().synchronize()
        }
        
        // set the presets
        if NSUserDefaults.standardUserDefaults().boolForKey("outputDuplicate") {
            addPrefixRadioButton.state = NSOnState
            overwriteRadioButton.state = NSOffState
            if let str = NSUserDefaults.standardUserDefaults().stringForKey("outputSuffix") {
                prefixTextField.stringValue = str
            }
        } else {
            overwriteRadioButton.state = NSOnState
            addPrefixRadioButton.state = NSOffState
        }
        
        prefixTextField.enabled = NSUserDefaults.standardUserDefaults().boolForKey("outputDuplicate")
        
        makeSearchableCheckbox.state = NSUserDefaults.standardUserDefaults().boolForKey("conversionSearchable") ? NSOnState : NSOffState
        splitPagesCheckbox.state = NSUserDefaults.standardUserDefaults().boolForKey("conversionSplitPages") ? NSOnState : NSOffState
        adjustTiltCheckbox.state = NSUserDefaults.standardUserDefaults().boolForKey("conversionAdjustTilt") ? NSOnState : NSOffState
        
        dropView.wantsLayer = true
        dropView.layer?.backgroundColor = CGColorCreateGenericGray(0.8, 1.0)
        dropView.delegate = self
        
        swapInterface(false)
    }

    override func controlTextDidChange(obj: NSNotification) {
        NSUserDefaults.standardUserDefaults().setValue(prefixTextField.stringValue, forKey: "outputSuffix")
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    
    // MARK: ViewController Actions
    @IBAction func clickOverwrite(sender: NSButtonCell) {
        NSUserDefaults.standardUserDefaults().setBool(false, forKey: "outputDuplicate")
        NSUserDefaults.standardUserDefaults().setValue(prefixTextField.stringValue, forKey: "outputSuffix")
        NSUserDefaults.standardUserDefaults().synchronize()
        prefixTextField.enabled = false
    }
    
    @IBAction func clickAddPrefix(sender: NSButtonCell) {
        NSUserDefaults.standardUserDefaults().setBool(true, forKey: "outputDuplicate")
        NSUserDefaults.standardUserDefaults().setValue(prefixTextField.stringValue, forKey: "outputSuffix")
        NSUserDefaults.standardUserDefaults().synchronize()
        prefixTextField.enabled = true
    }
    
    @IBAction func clickSearchable(sender: NSButton) {
        NSUserDefaults.standardUserDefaults().setBool(sender.state == NSOnState, forKey: "conversionSearchable")
        NSUserDefaults.standardUserDefaults().synchronize()
    }

    @IBAction func clickSplitPages(sender: NSButton) {
        NSUserDefaults.standardUserDefaults().setBool(sender.state == NSOnState, forKey: "conversionSplitPages")
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    @IBAction func clickAdjustTilt(sender: NSButton) {
        NSUserDefaults.standardUserDefaults().setBool(sender.state == NSOnState, forKey: "conversionAdjustTilt")
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    @IBAction func browseForFile(sender: NSButton) {
        let fileTypes = ["pdf"]
        let oPanel = NSOpenPanel()
        var startingDir: String? = NSUserDefaults.standardUserDefaults().objectForKey("StartingDirectory") as? String
        
        if (startingDir == nil) {
            startingDir = NSHomeDirectory()
        }
        
        oPanel.allowsMultipleSelection = true
        oPanel.allowedFileTypes = fileTypes
        
        if let window = NSApplication.sharedApplication().mainWindow {
            oPanel.beginSheetModalForWindow(window, completionHandler: { (returnCode: Int) in
                if returnCode == NSOKButton {
                    for URL in oPanel.URLs {
                        if let u = URL as? NSURL {
                            self.processFileWithURL(u)
                        }
                    }
                }
            })
        }
    }
    
    @IBAction func cancel(sender: NSButton) {
        self.pdfManagers.map({ $0?.shouldCancel = true })
        for i in 0..<self.pdfManagers.count {
            self.pdfManagers[i] = nil
        }
        self.pdfManagers = []
    }
    
    
    
    // MARK: DropViewDelegate
    func processFileWithURL(URL: NSURL) {
        
        let pdfManager = ElucidatePDFManager()
        pdfManager.delegate = self
        pdfManager.tag = pdfManagers.count
        pdfManagers.append(pdfManager)
        
        let recognizeText = NSUserDefaults.standardUserDefaults().boolForKey("conversionSearchable")
        let splitPages = NSUserDefaults.standardUserDefaults().boolForKey("conversionSplitPages")
        let adjustTilt = NSUserDefaults.standardUserDefaults().boolForKey("conversionAdjustTilt")
        var suffix = NSUserDefaults.standardUserDefaults().stringForKey("outputSuffix")
        
        if !NSUserDefaults.standardUserDefaults().boolForKey("outputDuplicate") {
            suffix = nil
        }
        
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), {
            pdfManager.processFileWithURL(URL, recognizeText: recognizeText, splitPages: splitPages, adjustTilt: adjustTilt, fileSuffix: suffix)
        })
        
    }
    
    // MARK: ElucidatePDFManagerDelegate Methods
    func progressUpdated() {
        var total = pdfManagers.count
        
        if total < 1 {
            return
        }
        
        var current = 0.0
        for manager in pdfManagers.filter({ $0 != nil }) {
            current += (manager!.progress / Double(total))
        }
        progressBar.doubleValue = current
        
        if pdfManagers.count == 1 {
            if let manager = pdfManagers.first {
                let current: Int = manager!.currentPage
                let total: Int = manager!.totalPagesToProcess
                if total <= 1 {
                    detailText.stringValue = ""
                } else {
                    detailText.stringValue = "Analyzing Page \(current + 1) of \(total)"
                }
            }
        } else {
            detailText.stringValue = ""
        }
    }
    
    func conversionDidStart() {
        progressBar.doubleValue = 0.0
        swapInterface(true)
    }
    
    func conversionDidEnd(sender: ElucidatePDFManager) {
        for i in 0..<pdfManagers.count {
            if pdfManagers[i] === sender {
                pdfManagers.removeAtIndex(i)
            }
        }
        if pdfManagers.count == 0 {
            NSApplication.sharedApplication().requestUserAttention(NSRequestUserAttentionType.InformationalRequest)
            progressBar.doubleValue = 0.0
            swapInterface(false)
        }
        
    }
    
    func getWindow() -> NSWindow? {
        if let window = NSApplication.sharedApplication().mainWindow {
            return window
        } else {
            return nil
        }
    }

    // MARK: Swapping interfaces
    func swapInterface(processing: Bool) {
        // TODO: Make this more elegant
        
        detailText.stringValue = ""
        dropHereText.hidden = processing
        chooseFileButton.hidden = processing
        
        inProcessText.hidden = !processing
        progressBar.hidden = !processing
        detailText.hidden = !processing
        cancelButton.hidden = !processing
    }
    
}

