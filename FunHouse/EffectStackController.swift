//  Converted to Swift 5.1 by Swiftify v5.1.30744 - https://objectivec2swift.com/
/*
     File: EffectStackController.swift
 Abstract: This class controls the automatically resizeable effect stack inspector. It must also be able to resize and reconfigure itself when switching documents.
  Version: 2.1

 Copyright (C) 2014 Apple Inc. All Rights Reserved.

 */

import AppKit

private let inspectorTopY = 36


@objcMembers final class EffectStackController: NSWindowController {
    @IBOutlet var topPlusButton: NSButton! // the plus button at the top of the effect stack inspector (outside of any layer box)
    @IBOutlet var resetButton: NSButton! // the reset button at the top of the effect stack inspector (outside of any layer box)
    @IBOutlet var playButton: NSButton! // the play button at the top of the effect stack inspector (outside of any layer box)
    // filter palette stuff
    @IBOutlet var filterPalette: NSWindow! // the filter palette (called image units)
    @IBOutlet var filterOKButton: NSButton! // the apply button, actually
    @IBOutlet var filterCancelButton: NSButton! // the cancel button
    @IBOutlet var categoryTableView: NSTableView! // the category table view
    @IBOutlet var filterTableView: NSTableView! // the filter list table view
    @IBOutlet var filterTextButton: NSButton! // the text button

    private var inspectingCoreImageView: CoreImageView? // pointer to the core image view that is currently associated with the effect stack inspector
    private var inspectingEffectStack: EffectStack? // pointer to the effect stack that is currently associated with the effect stack inspector
    private var needsUpdate = false // set this to re-layout the effect stack inspector on update
    private var boxes: [FilterView] = [] // an array of FilterView (subclass of NSBox) that make up the effect stack inspector's UI
    private var filterPaletteTopLevelObjects: [NSView] = [] // an array of the top level objects in the filter palette nib
    private var currentCategory = 0 // the currently selected row in the category table view
    private var currentFilterRow = 0 // the currently selected row in the filter table view
    private var categories: [AnyHashable : Any]? // a dictionary containing all filter category names and the filters that populate the category
    private var filterClassname: String? // returned filter's classname from the modal filter palette (when a filter has been selected)
    private var timer: Timer? /// playing all transitions

    // globals used in the sequential animation of all transitions
    private var transitionStartTime = 0.0
    private var transitionDuration = 0.0
    private var transitionEndTime = 0.0

    static var _sharedEffectStackController: EffectStackController?
    private let nsApp = NSApplication.shared as! FunHouseApplication

    class func sharedEffectStackController() -> EffectStackController {
        if _sharedEffectStackController == nil {
            _sharedEffectStackController = EffectStackController()
        }
        return _sharedEffectStackController!
    }

    func setAutomaticDefaults(_ f: CIFilter, at index: Int) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        switch NSStringFromClass(type(of: f).self) {
        case "CIGlassDistortion":
            // glass distortion gets a default texture file
            f.setValue(nsApp.defaultTexture(), forKey: "inputTexture")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultTexturePath(), forKey: "inputTexture")
        case "CIRippleTransition":
            // ripple gets a material map for shading the ripple that has a transparent alpha except specifically for the shines and darkenings
            f.setValue(nsApp.defaultAlphaEMap(), forKey: "inputShadingImage")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultAlphaEMapPath(), forKey: "inputShadingImage")
        case "CIPageCurlTransition":
            // we set up a good page curl default material map (like that for the ripple transition)
            f.setValue(nsApp.defaultAlphaEMap(), forKey: "inputShadingImage")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultAlphaEMapPath(), forKey: "inputShadingImage")
            // the angle chosen shows off the alpha material map's shine on the leading curl
            f.setValue(NSNumber(value: -.pi * 0.25), forKey: "inputAngle")
        case "CIShadedMaterial":
            // shaded material gets an opaque material map that shows off surfaces well
            f.setValue(nsApp.defaultShadingEMap(), forKey: "inputShadingImage")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultShadingEMapPath(), forKey: "inputShadingImage")
        case "CIColorMap":
            // color map gets a gradient image that's a color spectrum
            f.setValue(nsApp.defaultRamp(), forKey: "inputGradientImage")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultRampPath(), forKey: "inputGradientImage")
       case "CIDisintegrateWithMaskTransition":
            // disintegrate with mask transition gets a mask that has a growing star
            f.setValue(nsApp.defaultMask(), forKey: "inputMaskImage")
            inspectingEffectStack.setFilterLayer(index, imageFilePathValue: nsApp.defaultMaskPath(), forKey: "inputMaskImage")
       case "CICircularWrap":
            // circular wrap needs to be aware of the size of the screen to put its data in the right place
            if let bounds = inspectingCoreImageView?.bounds {
                let cx = bounds.origin.x + 0.5 * (bounds.size.width)
                let cy = bounds.origin.y + 0.5 * (bounds.size.height)
                f.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
            }
        default: fatalError()
        }
    }

    func effectStackFilterHasMissingImage(_ f: CIFilter) -> Bool {
        guard let inspectingEffectStack = inspectingEffectStack else { return false }

        return inspectingEffectStack.filterHasMissingImage(f)
    }

    // this method brings up the "image units palette" (we call it the filter palette) - and it also has buttons for images and text layers
    func collectFilterImageOrText() -> [String: Any]? {
        // when running the filter palette, if a filter is chosen (as opposed to an image or text) then filterClassname returns the
        // class name of the chosen filter

        filterClassname = nil

        // load the nib for the filter palette
        var topLevelObjects: NSArray?
        Bundle.main.loadNibNamed("FilterPalette", owner: self, topLevelObjects: &topLevelObjects)
        // keep the top level objects in the filterPaletteTopLevelObjects array
        guard let topLevelObjs = topLevelObjects as? [NSView] else { fatalError() }

        for object in topLevelObjs {
            if !filterPaletteTopLevelObjects.contains(object) {
                filterPaletteTopLevelObjects.append(object)
            }
        }

        // set up the categories data structure, that enumerates all filters for use by the filter palette
        if categories == nil {
            categories = [:]
            _loadFilterListIntoInspector()
        } else {
            filterTableView.reloadData()
        }
        // set up the usual target-action stuff for the filter palette
        filterTableView.target = self
        filterTableView.doubleAction = #selector(tableViewDoubleClick(_:))
        filterOKButton.isEnabled = false
        // re-establish the current position in the filters palette
        categoryTableView.selectRowIndexes(NSIndexSet(index: currentCategory) as IndexSet, byExtendingSelection: false)
        filterTableView.selectRowIndexes(NSIndexSet(index: currentFilterRow) as IndexSet, byExtendingSelection: false)
        // run the modal filter palette now
        let i = NSApp.runModal(for: filterPalette).rawValue
        filterPalette.close()
        if i == 100 {
            // Apply
            // create the filter layer dictionary
            if let filterClassname = filterClassname, let filter1 = CIFilter(name: filterClassname) {
                return [
                "type" : "filter",
                "filter" : filter1
                ]
            }
            fatalError()
        } else if i == 101 {
            // Cancel
            return nil
        } else if i == 102 {
            // Image
            // use the open panel to open an image
            let op = NSOpenPanel()
            op.allowsMultipleSelection = false
            op.canChooseDirectories = false
            op.resolvesAliases = true
            op.canChooseFiles = true
            // run the open panel with the allowed types
            op.allowedFileTypes = ["jpg", "jpeg", "tif", "tiff", "png", "crw", "cr2", "raf", "mrw", "nef", "srf", "exr"]
            let j = op.runModal()
            if j == NSApplication.ModalResponse.OK {
                // get image from open panel
                let url = op.urls[0]
                let im = CIImage(contentsOf: url)
                // create the image layer dictionary
                if let im = im {
                    return [
                    "type" : "image",
                    "image" : im,
                    "filename" : url.lastPathComponent,
                    "imageFilePath" : url.path
                    ]
                }
                return nil
            } else if j == NSApplication.ModalResponse.cancel {
                return nil
            }
        } else if i == 103 {
            // Text
            // create the text layer dictionary
            return [
            "type" : "text",
            "string" : "text",
            "scale" : NSNumber(value: 10.0)
            ]
        }
        return nil
    }

    // get the currently associated document
    func doc() -> FunHouseDocument? {
        return NSDocumentController.shared.currentDocument as? FunHouseDocument
    }

    func setChanges() {
        doc()?.updateChangeCount(NSDocument.ChangeType.changeDone)
    }

    func setCoreImageView(_ v: CoreImageView?) {
        inspectingCoreImageView = v
    }

    func setNeedsUpdate(_ b: Bool) {
        needsUpdate = b
    }

    func updateLayout() {
        needsUpdate = true
        window?.update()
    }

    func _loadFilterListIntoInspector() {
        var cat: String?
        var attrs: [AnyHashable]?
        var all: [AnyHashable]?
        var m: Int

        // here's a list of all categories
        attrs = [kCICategoryGeometryAdjustment, kCICategoryDistortionEffect, kCICategoryBlur, kCICategorySharpen, kCICategoryColorAdjustment, kCICategoryColorEffect, kCICategoryStylize, kCICategoryHalftoneEffect, kCICategoryTileEffect, kCICategoryGenerator, kCICategoryGradient, kCICategoryTransition, kCICategoryCompositeOperation]
        // call to load all plug-in image units
        CIPlugIn.loadNonExecutablePlugIns() // loadAllPlugIns()
        // enumerate all filters in the chosen categories
        m = attrs?.count ?? 0
        for i in 0..<m {
            // get this category
            cat = attrs?[i] as? String
            // make a list of all filters in this category
            all = CIFilter.filterNames(inCategory: cat)
            // make this category's list of approved filters
            categories?[CIFilter.localizedName(forCategory: cat ?? "")] = buildFilterDictionary(all)
        }
        currentCategory = 0
        currentFilterRow = 0
        // load up the filter list into the table view
        filterTableView.reloadData()
    }

    // build a dictionary of approved filters in a given category for the filter inspector
    func buildFilterDictionary(_ names: [AnyHashable]?) -> [AnyHashable : Any]? {
        var inspectable: Bool
        var attr: [AnyHashable : Any]?
        var parameter: [AnyHashable : Any]?
        var inputKeys: [AnyHashable]?
        var td: [AnyHashable : Any]?
        var catfilters: [AnyHashable : Any]?
        var classname: String?
        var classstring: String?
        var typestring: String?
        var filter: CIFilter?

        catfilters = [:]
        for i in 0..<(names?.count ?? 0) {
            // load the filter class name
            classname = names?[i] as? String
            // create an instance of the filter
            filter = CIFilter(name: classname ?? "")
            if filter != nil {
                // search the filter for any input parameters we can't inspect
                inspectable = true
                attr = filter?.attributes
                inputKeys = filter?.inputKeys
                // enumerate all input parameters and generate their UI
                //enumerator = (inputKeys as NSArray?)?.objectEnumerator()
                guard let inputKeys = inputKeys as? [String] else { continue }

                for key in inputKeys  {
                    parameter = attr?[key] as? [AnyHashable : Any]
                    classstring = parameter?[kCIAttributeClass] as? String
                    if (classstring == "CIImage") || (classstring == "CIColor") || (classstring == "NSAffineTransform") || (classstring == "NSNumber") {
                        continue // all inspectable
                    } else if (classstring == "CIVector") {
                        // check for a vector with no attributes
                        typestring = parameter?[kCIAttributeType] as? String
                        if typestring != nil && !(typestring == kCIAttributeTypePosition) && !(typestring == kCIAttributeTypeRectangle) && !(typestring == kCIAttributeTypePosition3) && !(typestring == kCIAttributeTypeOffset) {
                            inspectable = false
                        }
                    } else {
                        inspectable = false
                    }
                }
                if !inspectable {
                    continue // if we can't inspect it, it's not approved and must be omitted from the list
                }
                // create a dictionary for the filter with filter's class name
                td = [:]
                td?[kCIAttributeClass] = classname
                // set it as the value for a key which is the filter's localized name
                catfilters?[CIFilter.localizedName(forFilterName: classname ?? "")] = td
            } else {
                print(" could not create '\(classname ?? "")' filter")
            }
        }
        return catfilters
    }

    // set changes (dirty the document)
    // call to directly update (and re-layout) the configuration of the effect stack inspector
    // this is the glue code you call to insert a filter layer into the effect stack. this handles save for undo, etc.
    func insert(_ f: CIFilter, atIndex index: NSNumber) {
        guard let inspectingEffectStack = inspectingEffectStack  else { fatalError() }

        // actually insert the filter layer into the effect stack
        inspectingEffectStack.insertFilterLayer(f, at: index.intValue)
        // set filter attributes to their defaults
        inspectingEffectStack.filter(at: index.intValue).setDefaults()
        // set any automatic defaults we need (generally the odd image parameter)
        setAutomaticDefaults(inspectingEffectStack.filter(at: index.intValue), at: index.intValue)

        if let doc = doc(), let udMgr = doc.undoManager, let target = udMgr.prepare(withInvocationTarget: self) as? EffectStackController {
        // do "save for undo"
            target.removeFilterImageOrText(atIndex: index)
            let name = CIFilter.localizedName(forFilterName: String(describing: type(of: f)))!
            udMgr.setActionName("Filter \(name)")
        }
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    // this is the high-level glue code you call to insert an image layer into the effect stack. this handles save for undo, etc.
    func insert(_ image: CIImage, withFilename filename: String, andImageFilePath path: String, atIndex index: NSNumber) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        // actually insert the image layer into the effect stack
        inspectingEffectStack.insertImageLayer(image, withFilename: filename, at: index.intValue)
        inspectingEffectStack.setImageLayer(index.intValue, imageFilePath: path)
        // do "save for undo"
        if let doc = doc(), let udMgr = doc.undoManager, let target = udMgr.prepare(withInvocationTarget: self) as? EffectStackController {
            target.removeFilterImageOrText(atIndex: index)
            let url = URL(fileURLWithPath: filename)
            udMgr.setActionName("Image \(url.lastPathComponent)")
        }
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    // this is the high-level glue code you call to insert a text layer into the effect stack. this handles save for undo, etc.
    func insert(_ string: String, with image: CIImage, atIndex index: NSNumber) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        // actually insert the text layer into the effect stack
        inspectingEffectStack.insertTextLayer(string, with: image, at: index.intValue)
        // do "save for undo"
        if let doc = doc(), let udMgr = doc.undoManager, let target = udMgr.prepare(withInvocationTarget: self) as? EffectStackController {
            target.removeFilterImageOrText(atIndex: index)
            udMgr.setActionName("Text")
        }
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    func setLayer(_ index: Int, image im: CIImage, andFilename filename: String) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        inspectingEffectStack.setImageLayer(index, image: im, andFilename: filename)
    }

    // reset the core image view (used when going to into full screen mode and back out)
    // flag that we need to reconfigure ourselves after some effect stack change
    func enablePlayButton() {
        var enabled: Bool
        var count: Int
        var type: String?
        var f: CIFilter?
        var attr: [AnyHashable : Any]?

        count = inspectingEffectStack?.layerCount() ?? 0
        enabled = false
        for i in 0..<count {
            type = inspectingEffectStack?.type(at: i)
            if !(type == "filter") {
                continue
            }
            // first find time slider
            f = inspectingEffectStack?.filter(at: i)
            attr = f?.attributes
            if attr?["inputTime"] != nil {
                enabled = true
                break
            }
        }
        playButton.isEnabled = enabled
    }

    func removeFilterImageOrText(atIndex index: NSNumber) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        var typ: String!
        var filter: CIFilter!
        var image: CIImage!
        var filename: String!
        var string: String!
        var path: String!

        // first get handles to parameters we want to retain for "save for undo"
        typ = inspectingEffectStack.type(at: index.intValue)
        switch typ {
        case "filter":
            filter = inspectingEffectStack.filter(at: index.intValue)
        case "image":
            image = inspectingEffectStack.image(at: index.intValue)
            filename = inspectingEffectStack.filename(at: index.intValue)
            path = inspectingEffectStack.imageFilePath(at: index.intValue)
        case "text":
            image = inspectingEffectStack.image(at: index.intValue)
            string = inspectingEffectStack.string(at: index.intValue)
        default:
            fatalError()
        }
        // actually remove the layer from the effect stack here
        inspectingEffectStack.removeLayer(at: index.intValue)

        // do "save for undo"
        if let doc = doc(), let udMgr = doc.undoManager, let target = udMgr.prepare(withInvocationTarget: self) as? EffectStackController {
            switch typ {
            case "filter":
                guard let filter = filter, let name = CIFilter.localizedName(forFilterName: String(describing: type(of: filter))) else { fatalError() }
                udMgr.setActionName("Filter \(name)")
            case "image":
                guard let filename = filename else { fatalError() }
                target.insert(image, withFilename: filename, andImageFilePath: path, atIndex: index)
                let url = URL(fileURLWithPath: filename)
                udMgr.setActionName("Image \(url.lastPathComponent)")
            case "text":    // ObjC says "string" ???
                target.insert(string, with: image, atIndex: index)
                udMgr.setActionName("Text")
            default:
                fatalError()
            }
        }
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    @IBAction func topPlusButtonAction(_ sender: NSControl) {
        guard let d = collectFilterImageOrText(), let type = d["type"] as? String else { fatalError() }

        switch type {
        case "filter":
            guard let filter = d["filter"] as? CIFilter else { fatalError() }
            insert(filter, atIndex: NSNumber(value: 0))
        case "image":
            guard let image = d["image"]  as? CIImage, let string = d["filename"] as? String, let path = d["imageFilePath"] as? String else { fatalError() }
            insert(image, withFilename: string, andImageFilePath: path, atIndex: NSNumber(value: 0))
        case "text":
            guard let string = d["string"] as? String, let image = d["image"] as? CIImage else { fatalError() }
            insert(string, with: image, atIndex: NSNumber(value: 0))
        default: fatalError()
        }
        enablePlayButton()
    }

    @IBAction func plusButtonAction(_ sender: NSControl) {
        guard let d = collectFilterImageOrText(), let type = d["type"] as? String else { fatalError() }
        let index = sender.tag + 1

        switch type {
        case "filter":
            guard let filter = d["filter"] as? CIFilter else { fatalError() }
            insert(filter, atIndex: NSNumber(value: index))
        case "image":
            guard let image = d["image"]  as? CIImage, let string = d["filename"] as? String, let path = d["imageFilePath"] as? String else { fatalError() }
            insert(image, withFilename: string, andImageFilePath: path, atIndex: NSNumber(value: index))
        case "text":
            guard let string = d["string"] as? String, let image = d["image"] as? CIImage else { fatalError() }
            insert(string, with: image, atIndex: NSNumber(value: index))
        default: fatalError()
        }

        enablePlayButton()
    }

    @IBAction func minusButtonAction(_ sender: NSControl) {
        removeFilterImageOrText(atIndex: NSNumber(value: sender.tag))
        enablePlayButton()
    }

    @IBAction func resetButtonAction(_ sender: NSControl) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        var i: Int
        var count: Int

        // kill off all layers from the effect stack
        count = inspectingEffectStack.layerCount()
        if count == 0 {
            return
        }
        // note: done using glue primitives so it will be an undoable operation
        if !(inspectingEffectStack.type(at: 0) == "image") {
            i = count - 1
            while i >= 0 {
                removeFilterImageOrText(atIndex: NSNumber(value: i))
                i -= 1
            }
        } else {
            i = count - 1
            while i > 0 {
                removeFilterImageOrText(atIndex: NSNumber(value: i))
                i -= 1
            }
        }
        // dirty the document
        setChanges()
        // update the configuration of the effect stack inspector
        updateLayout()
        // let core image recompute the view
        inspectingCoreImageView?.needsDisplay = true
        enablePlayButton()
    }

    func playButtonAction(_ sender: NSButton) {
        var count: Int
        var nTransitions: Int
        var type: String?
        var f: CIFilter?
        var attr: [AnyHashable : Any]?
        var d: [AnyHashable : Any]?

        count = inspectingEffectStack?.layerCount() ?? 0
        // first determine the number of transitions
        nTransitions = 0
        for i in 0..<count {
            type = inspectingEffectStack?.type(at: i)
            // find only filter layers
            if !(type == "filter") {
                continue
            }
            // first find time slider
            f = inspectingEffectStack?.filter(at: i)
            attr = f?.attributes
            // basically anything with an "inputTime" is a transition by definition
            d = attr?["inputTime"] as? [AnyHashable : Any]
            if d == nil {
                continue
            }
            // we have a transition 
            nTransitions += 1
        }
        if nTransitions == 0 {
            return
        }
        // set up the information governing the global time index over all transitions
        transitionStartTime = Date.timeIntervalSinceReferenceDate
        transitionDuration = 1.5
        transitionEndTime = transitionStartTime + transitionDuration * Double(CGFloat(nTransitions))
        // start the timer now
        startTimer()
        // set all inputTime parameters to 0.0
        for i in 0..<count {
            type = inspectingEffectStack?.type(at: i)
            // find only filters
            if !(type == "filter") {
                continue
            }
            // first find time slider
            f = inspectingEffectStack?.filter(at: i)
            attr = f?.attributes
            d = attr?["inputTime"] as? [AnyHashable : Any]
            if d == nil {
                continue
            }
            // set the value to zero
            f?.setValue(NSNumber(value: 0.0), forKey: "inputTime")
        }
        // let core image recompute the view
        inspectingCoreImageView?.needsDisplay = true // force a redisplay
    }

    // start the transition timer
    func startTimer() {
        if timer == nil {
            timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(autoTimer(_:)), userInfo: nil, repeats: true)
        }
    }

    // a layer's plus button inserts another new layer after this one
    // for a new filter, set up the odd image parameter
    // a layer's mins button removes the layer
    // the reset button removes all layers from the effect stack
    // stop the transition timer
    func stopTimer() {
        guard let timer = timer else { return }
        timer.invalidate()
        self.timer = nil
    }

    // called by the transition timer every 1/30 second
    // this animates the transitions in sequence - one after another
    @objc func autoTimer(_ sender: Timer) {
        var count: Int
        var transitionIndex: Int
        var f: CIFilter?
        var type: String?
        var attr: [AnyHashable : Any]?
        var now: Double
        var transitionValue: CGFloat
        var value: CGFloat
        var lastTimeValue: CGFloat = 0.0

        now = Date.timeIntervalSinceReferenceDate
        // compute where the global time index within the state of the "n" transitions that are animating
        transitionValue = CGFloat((now - transitionStartTime) / transitionDuration)
        if transitionValue < 0.0 {
            stopTimer()
            return
        }
        // set all times now
        if transitionValue >= 0.0 {
            // assign an index to each transition
            transitionIndex = 0
            count = inspectingEffectStack?.layerCount() ?? 0
            for i in 0..<count {
                type = inspectingEffectStack?.type(at: i)
                if !(type == "filter") {
                    continue
                }
                // first find time slider
                f = inspectingEffectStack?.filter(at: i)
                attr = f?.attributes
                if attr?["inputTime"] != nil {
                    // for this transition decide where it is within its time sequence
                    // by subtracting the transition index from the global time index
                    value = transitionValue - CGFloat(transitionIndex)
                    // clamp to the time sequence of the transition
                    if value <= 0.0 {
                        value = 0.0
                    } else if value > 1.0 {
                        value = 1.0
                    }
                    lastTimeValue = value
                    // set the inputTime value
                    f?.setValue(NSNumber(value: Double(value)), forKey: "inputTime")
                    // increment the transition index
                    transitionIndex += 1
                }
            }
        }
        // let core image recompute the view
        inspectingCoreImageView?.needsDisplay = true // force a redisplay
        // terminate the animation if we've animated all transitions to their completion point
        if now >= transitionEndTime && lastTimeValue == 1.0 {
            // when all transitions are done, update the sliders in the effect stack inspector
            updateLayout()
            // and turn off the timer
            stopTimer()
            return
        }
    }


    func layoutInspector() {
        guard let window = window, let contentView = window.contentView else { fatalError() }

        // decide how inspector is to be sized and layed out
        // boxes are all internally sized properly at this point
        var inspectorheight: Int
        var fvtop: Int

        // first estimate the size of the effect stack inspector (with the boxes placed one after another vertically)
        inspectorheight = inspectorTopY
        for fv in boxes{
            let height = fv.bounds.size.height
            // add the height of the box plus some spacing
            inspectorheight += Int(height + 6)
        }
        // resize the effect stack inspector now
        var frm = window.frame
        let delta = CGFloat(inspectorheight) + window.frame.size.height - contentView.frame.size.height - frm.size.height
        frm.size.height += delta
        frm.origin.y -= delta
        window.setFrame(frm, display: true, animate: true) // animate the window size change
        // and move all the boxes into place

        fvtop = inspectorheight - inspectorTopY
        for fv in boxes {
            frm = fv.frame
            frm.origin.y = CGFloat(fvtop) - frm.size.height
            fv.frame = frm
            fvtop -= Int(frm.size.height + 6)
            // unhide the box
            fv.isHidden = false
        }
        // finally call for a redisplay of the effect stack inspector
        contentView.needsDisplay = true
    }

    func newUI(for f: CIFilter, index: Int) -> FilterView {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        var hasBackground: Bool
        var typestring: String?
        var classstring: String?
        var frame: NSRect
        var view: NSView?

        // create box first
        view = window?.contentView
        frame = view?.bounds ?? NSRect.zero
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        let fv = FilterView(frame: frame)

        fv.setFilter(f)
        fv.isHidden = true
        window?.contentView?.addSubview(fv)

        fv.titlePosition = NSBox.TitlePosition.noTitle
        fv.autoresizingMask = [.width, .minYMargin]
        fv.borderType = NSBorderType.grooveBorder
        fv.boxType = NSBox.BoxType.primary
        fv.setMaster(self)
        fv.setTag(index)
        // first compute size of box with all the controls
        fv.tryFilterHeader(f)
        var attr = f.attributes
        // decide if this filter has a background image parameter (true for blend modes and Porter-Duff modes)
        hasBackground = false
        let inputKeys = f.inputKeys

        // enumerate all input parameters and generate their UI
        for key in inputKeys {
            let parameter = attr[key]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "CIImage") && (key == "inputBackgroundImage") {
                    hasBackground = true
                }
            }
        }
        // enumerate all input parameters and reserve space for their generated UI
        for key in inputKeys {
            let parameter = attr[key]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "NSNumber") {
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if (typestring == kCIAttributeTypeBoolean) {
                        // if it's a boolean type, save space for a check box
                        fv.tryCheckBox(for: f, key: key, display: inspectingCoreImageView)
                    } else {
                        // otherwise space space for a slider
                        fv.trySlider(for: f, key: key, display: inspectingCoreImageView)
                    }
                } else if (classstring == "CIColor") {
                    // save space for a color well
                    fv.tryColorWell(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIImage") {
                    // don't bother to create a UI element for the chained image
                    if hasBackground {
                        // the chained image is the background image for blend modes and Porter-Duff modes
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputBackgroundImage") {
                            // save space for an image well
                            fv.tryImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    } else {
                        // the chained image is the input image for all other filters
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputImage") {
                            // save space for an image well
                            fv.tryImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    }
                } else if (classstring == "NSAffineTransform") {
                    // save space for transform inspection widgets
                    fv.tryTransform(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIVector") {
                    // check for a vector with no attributes
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if typestring == nil {
                        // save space for a 4-element vector inspection widget (4 text fields)
                        fv.tryVector(for: f, key: key, display: inspectingCoreImageView)
                    } else if (typestring == kCIAttributeTypeOffset) {
                        fv.tryOffset(for: f, key: key, display: inspectingCoreImageView)
                    }
                    // note: the other CIVector parameters are handled in mouse down processing of the core image view
                }
            }
        }
        // now resize the box to hold the controls we're about to make
        fv.trimBox()
        // now add all the controls
        fv.addFilterHeader(f, tag: index, enabled: inspectingEffectStack.layerEnabled(index))
        attr = f.attributes

        // enumerate all input parameters and generate their UI
        for key in inputKeys {
            let parameter = attr[key]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "NSNumber") {
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if (typestring == kCIAttributeTypeBoolean) {
                        // if it's a boolean type, generate a check box
                        fv.addCheckBox(for: f, key: key, display: inspectingCoreImageView)
                    } else {
                        // otherwise generate a slider
                        fv.addSlider(for: f, key: key, display: inspectingCoreImageView)
                    }
                } else if (classstring == "CIImage") {
                    if hasBackground {
                        // the chained image is the background image for blend modes and Porter-Duff modes
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputBackgroundImage") {
                            // generate an image well
                            fv.addImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    } else {
                        // the chained image is the input image for all other filters
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputImage") {
                            // generate an image well
                            fv.addImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    }
                } else if (classstring == "CIColor") {
                    // generate a color well
                    fv.addColorWell(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "NSAffineTransform") {
                    // generate transform inspection widgets
                    fv.addTransform(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIVector") {
                    // check for a vector with no attributes
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if typestring == nil {
                        // generate a 4-element vector inspection widget (4 text fields)
                        fv.addVector(for: f, key: key, display: inspectingCoreImageView)
                    } else if (typestring == kCIAttributeTypeOffset) {
                        fv.addOffset(for: f, key: key, display: inspectingCoreImageView)
                    }
                    // the rest are handled in mouse down processing
                }
            }
        }
        // retrun the box with the filter's UI
        return fv
    }

    func newUI(for im: CIImage, filename: String, index: Int) -> FilterView {
        guard let inspectingEffectStack = inspectingEffectStack, let window = window, let view = window.contentView else { fatalError() }

        // create the box first
        var frame = view.bounds
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        let fv = FilterView(frame: frame)
        fv.setFilter(nil)
        fv.isHidden = true
        view.addSubview(fv)
        fv.titlePosition = NSBox.TitlePosition.noTitle
        fv.autoresizingMask = [.width, .minYMargin]
        fv.borderType = NSBorderType.grooveBorder
        fv.boxType = NSBox.BoxType.primary
        fv.setMaster(self)
        fv.setTag(index)
        // first compute size of box with all the controls
        fv.tryImageHeader(im)
        fv.tryImageWell(for: im, tag: index, display: inspectingCoreImageView)
        // now resize the box to hold the controls we're about to make
        fv.trimBox()
        // now add all the controls
        fv.addImageHeader(im, filename: filename, tag: index, enabled: inspectingEffectStack.layerEnabled(index))
        fv.addImageWell(for: im, tag: index, display: inspectingCoreImageView)
        return fv
    }


    func newUI(forText string: String?, index: Int) -> FilterView {
        guard let inspectingEffectStack = inspectingEffectStack, let view = window?.contentView else { fatalError() }
        var frame: NSRect

        // create the box first
        frame = view.bounds
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        let fv = FilterView(frame: frame)
        fv.setFilter(nil)
        fv.isHidden = true
        window?.contentView?.addSubview(fv)

        fv.titlePosition = NSBox.TitlePosition.noTitle
        fv.autoresizingMask = [.width, .minYMargin]
        fv.borderType = NSBorderType.grooveBorder
        fv.boxType = NSBox.BoxType.primary
        fv.setMaster(self)
        fv.setTag(index)
        // first compute size of box with all the controls
        fv.tryTextHeader(string)
        fv.tryTextViewForString()
        fv.trySliderForText()
        // now resize the box to hold the controls we're about to make
        fv.trimBox()
        // now add all the controls
        fv.addTextHeader(string, tag: index, enabled: inspectingEffectStack.layerEnabled(index))
        fv.addTextView(forString: inspectingEffectStack.mutableDictionary(at: index), key: "string", display: inspectingCoreImageView)
        fv.addSlider(forText: inspectingEffectStack.mutableDictionary(at: index), key: "scale", lo: 1.0, hi: 100.0, display: inspectingCoreImageView)
        return fv
    }


    @IBAction func filterOKButtonAction(_ sender: Any) {
        // signal to apply filter
        nsApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 100))
    }

    @IBAction func filterCancelButtonAction(_ sender: Any) {
        // signal cancel
        nsApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 101))
    }

    @IBAction func filterImageButtonAction(_ sender: Any) {
        // signal to get an image
        nsApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 102))
    }

    @IBAction func filterTextButtonAction(_ sender: Any) {
        // signal to setup a text layer
        nsApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 103))
    }

    @IBAction func tableViewDoubleClick(_ sender: Any) {
        nsApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: 100))
    }

    func closeDown() {
        guard let window = window, let view = window.contentView else { fatalError() }

        // resize inspector now
        var frm = window.frame
        let delta = CGFloat(inspectorTopY) + window.frame.size.height - view.frame.size.height - frm.size.height
        frm.size.height += delta
        frm.origin.y -= delta
        window.setFrame(frm, display: true, animate: false) // skip animation on quit!
    }


    func reconfigureWindow() {
        guard let inspectingEffectStack = inspectingEffectStack, let image = inspectingEffectStack.image(at: 0), let doc = doc() else { fatalError() }

        let path = inspectingEffectStack.imageFilePath(at: 0)
        let extent = image.extent
        doc.reconfigureWindow(to: NSMakeSize(extent.size.width, extent.size.height), andPath: path)
    } // called when dragging into or choosing base image to reconfigure the document's window

    // for retaining full file names of images
    func registerImageLayer(_ index: Int, imageFilePath path: String) {
        inspectingEffectStack?.setImageLayer(index, imageFilePath: path)
    }

    func registerFilterLayer(_ filter: CIFilter, key: String, imageFilePath path: String) {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        let count = inspectingEffectStack.layerCount()
        for i in 0..<count {
            guard let type = inspectingEffectStack.type(at: i) else { fatalError() }

            if !(type == "filter") {
                continue
            }
            if filter == inspectingEffectStack.filter(at: i) {
                inspectingEffectStack.setFilterLayer(i, imageFilePathValue: path, forKey: key)
                break
            }
        }
    }

    func imageFilePath(forImageLayer index: Int) -> String {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }
        return inspectingEffectStack.imageFilePath(at: index)
    }

    func imageFilePath(forFilterLayer filter: CIFilter, key: String) -> String {
        guard let inspectingEffectStack = inspectingEffectStack else { fatalError() }

        let count = inspectingEffectStack.layerCount()
        for i in 0..<count {
            guard let type = inspectingEffectStack.type(at: i) else { continue }
            if !(type == "filter") {
                continue
            }
            if filter == inspectingEffectStack.filter(at: i) {
                return inspectingEffectStack.filterLayer(i, imageFilePathValueForKey: key)
            }
        }
        fatalError()
    }

    // since the effect stack inspector window is global to all documents, we here provide a way of accessing the shared window
    // load from nib (really only the stuff at the top of the inspector)
    convenience init() {
        self.init(windowNibName: "EffectStack")
        windowFrameAutosaveName = "EffectStack"
        // set up an array to hold the representations of the layers from the effect stack we inspect
        needsUpdate = true
    }

    // free up the stuff we allocate
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // this allows us to set up the right pointers when changing documents
    // in particular the core image view and the effect stack
    func setMainWindow(_ mainWindow: NSWindow?) {
        var controller: NSWindowController?
        var document: FunHouseDocument?

        // note: if mainWindow is nil, then controller becomes nil here too
        controller = mainWindow?.windowController
        if controller != nil && (controller is FunHouseWindowController) {
            // we have a core image fun house document window (by controller)
            // get the core image view pointer from it
            inspectingCoreImageView = (controller as? FunHouseWindowController)?.coreImageView()
            // load up the FunHouseDocument pointer
            document = controller?.document as? FunHouseDocument
            // and get the effect stack pointer from it
            inspectingEffectStack = document?.effectStack()
        } else {
            // we inspect nothing at the moment
            inspectingCoreImageView = nil
            inspectingEffectStack = nil
        }
        updateLayout()
    }

    // when a window loads from the nib file, we set up the core image view pointer and effect stack pointers
    // and set up notifications
    override func windowDidLoad() {
        super.windowDidLoad()
        setMainWindow(nsApp.mainWindow)
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowChanged(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowResigned(_:)), name: NSWindow.didResignMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NSWindowDelegate.windowDidUpdate(_:)), name: NSWindow.didUpdateNotification, object: nil)
        NSColorPanel.shared.showsAlpha = true
    }

    // when window changes, update the pointers
    @objc func mainWindowChanged(_ notification: Notification) {
        setMainWindow(notification.object as? NSWindow)
    }

    // dissociate us when the window is gone.
    @objc func mainWindowResigned(_ notification: Notification) {
        setMainWindow(nil)
    }

    // when we see an update, check for the flag that tells us to reconfigure our effect stack inspection
    @objc func windowDidUpdate(_ notification: Notification) {
        if needsUpdate {
            // we need an update
            needsUpdate = false
            // remove tthe old boxes from the UI
            for box in boxes {
                box.removeFromSuperview()
            }
            // and clear out the boxes array
            boxes.removeAll()
            // now, if required, automatically generate the effect stack UI into separate boxes for each layer
            if let inspectingEffectStack = inspectingEffectStack {
                // create all boxes shown in the effect stack inspector from scratch, and place them into an array for layout purposes
                let count = inspectingEffectStack.layerCount()
                for i in 0..<count {
                    let type = inspectingEffectStack.type(at: i)
                    switch type {
                    case "filter":
                        guard let filter = inspectingEffectStack.filter(at: i) else { fatalError() }
                        let autorelease = newUI(for: filter, index: i)
                        boxes.append(autorelease)
                    case "image":
                        guard let image = inspectingEffectStack.image(at: i) else { fatalError() }
                        let autorelease = newUI(for: image, filename: inspectingEffectStack.filename(at: i), index: i)
                        boxes.append(autorelease)
                    case "text":
                        guard let string = inspectingEffectStack.string(at: i) else { fatalError() }
                        let autorelease = newUI(forText: string, index: i)
                        boxes.append(autorelease)
                    default:
                        fatalError()
                    }
                }
            }
            // now lay it out
            layoutInspector()
        }
    }

    // this is the high-level glue code you call to remove a layer (of any kind) from the effect stack. this handles save for undo, etc.
    // the "global" plus button inserts a layer before the first layer
    // this handles a change to each layer's "enable" check box
    @IBAction func enableCheckBoxAction(_ sender: NSButton) {
        guard let inspectingEffectStack = inspectingEffectStack, let inspectingCoreImageView = inspectingCoreImageView else { fatalError() }
        inspectingEffectStack.setLayer(sender.tag, enabled: sender.state == .on ? true : false)
        setChanges()
        inspectingCoreImageView.needsDisplay = true
    }

    // handle the play button - play all transitions
    // this must be in synch with EffectStack.nib

    // lay out the effect stack inspector - this takes the NSBox'es in the boxes array and places them
    // as subviews to the our owned window's content view
    // close down the effect stack inspector: this must be done before quit so our owned window's popsition
    // can be properly saved and subsequently restored on the next launch
    // automatically generate the UI for an effect stack filter layer
    // returning an NSBox (actually FilterView is a subclass of NSBox)
    // automatically generate the UI for an effect stack image layer
    // returning an NSBox (actually FilterView is a subclass of NSBox)
    // automatically generate the UI for an effect stack text layer
    // returning an NSBox (actually FilterView is a subclass of NSBox)
    // handle the filter palette apply button
    // handle the filter palette cancel button
    // handle the filter palette image button
    // return the category name for the category index - used by filter palette category table view
    func categoryName(for i: Int) -> String {
        var s: String?

        switch i {
        case 0:
            s = CIFilter.localizedName(forCategory: kCICategoryGeometryAdjustment)
        case 1:
            s = CIFilter.localizedName(forCategory: kCICategoryDistortionEffect)
        case 2:
            s = CIFilter.localizedName(forCategory: kCICategoryBlur)
        case 3:
            s = CIFilter.localizedName(forCategory: kCICategorySharpen)
        case 4:
            s = CIFilter.localizedName(forCategory: kCICategoryColorAdjustment)
        case 5:
            s = CIFilter.localizedName(forCategory: kCICategoryColorEffect)
        case 6:
            s = CIFilter.localizedName(forCategory: kCICategoryStylize)
        case 7:
            s = CIFilter.localizedName(forCategory: kCICategoryHalftoneEffect)
        case 8:
            s = CIFilter.localizedName(forCategory: kCICategoryTileEffect)
        case 9:
            s = CIFilter.localizedName(forCategory: kCICategoryGenerator)
        case 10:
            s = CIFilter.localizedName(forCategory: kCICategoryGradient)
        case 11:
            s = CIFilter.localizedName(forCategory: kCICategoryTransition)
        case 12:
            s = CIFilter.localizedName(forCategory: kCICategoryCompositeOperation)
        default:
            s = ""
        }
        return s ?? ""
    }

    // return the category index for the category name - used by filter palette category table view
    func index(forCategory nm: String) -> Int {
        if (nm == CIFilter.localizedName(forCategory: kCICategoryGeometryAdjustment)) {
            return 0
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryDistortionEffect)) {
            return 1
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryBlur)) {
            return 2
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategorySharpen)) {
            return 3
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryColorAdjustment)) {
            return 4
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryColorEffect)) {
            return 5
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryStylize)) {
            return 6
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryHalftoneEffect)) {
            return 7
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryTileEffect)) {
            return 8
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryGenerator)) {
            return 9
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryGradient)) {
            return 10
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryTransition)) {
            return 11
        }
        if (nm == CIFilter.localizedName(forCategory: kCICategoryCompositeOperation)) {
            return 12
        }
        return -1
    }


    // build the filter list (enumerates all filters)
    // table view data source methods
    func numberOfRows(in tv: NSTableView) -> Int {
        var count: Int

        switch tv.tag {
        case 0:
            // category table view
            count = 13
        case 1:
            fallthrough
        default:
            // filter table view
            let s = categoryName(for: currentCategory)
            // use category name to get dictionary of filter names
            guard let categories = categories, let dict = categories[s] as? [String: Any] else { fatalError() }
            // create an array
            let filterNames = dict.keys
            // return number of filters in this category
            count = filterNames.count
        }
        return count
    }

    func tableView(_ tv: NSTableView, objectValueFor tc: NSTableColumn, row: Int) -> String {
        var s: String

        switch tv.tag {
        case 0:
            // category table view
            s = categoryName(for: row)
            guard let tfc = tc.dataCell as? NSTextFieldCell else { fatalError() }
            // handle names that are too long by ellipsizing the name
            s = ParameterView.ellipsizeField(tc.width, font: tfc.font, string: s)
        case 1:
            fallthrough
        default:
            // filter table view
            // we need to maintain the filter names in a sorted order.
            s = categoryName(for: currentCategory)
            // use label (category name) to get dictionary of filter names
            guard let categories = categories, let dict = categories[s] as? [String: Any] else { fatalError() }
            // create an array of the sorted names (this is inefficient since we don't cache the sorted array)
            let filterNames = dict.keys.sorted(by: <)
            // return filter name
            s = filterNames[row]
            guard let tfc = tc.dataCell as? NSTextFieldCell else { fatalError() }
            // handle names that are too long by ellipsizing the name
            s = ParameterView.ellipsizeField(tc.width, font: tfc.font, string: s)
        }
        return s
    }

    // this is called when we select a filter from the list
    func addEffect() {
        guard let tv = filterTableView, let categories = categories else { fatalError() }
        // get current category item
        // decide current filter name from selected row (or none selected) in the filter name list
        let row = tv.selectedRow
        if row == -1 {
            filterClassname = nil
            filterOKButton.isEnabled = false
            return
        }
        // use label (category name) to get dictionary of filter names
        guard let dict = categories[ categoryName(for: currentCategory) ] as? [String: Any] else { fatalError() }
        // create an array of all filter names for this category
        let filterNames = dict.keys.sorted(by: <)
        // return filter name
        let object = filterNames[row]
        guard let td = dict[object] as? [String: Any] else { fatalError() }
        // retain the name in filterClassname for use outside the modal

        guard let name = td[kCIAttributeClass] as? String else { fatalError() }
        filterClassname = name

        // enable the apply button
        filterOKButton.isEnabled = true
    }

    func tableViewSelectionDidChange(_ aNotification: Notification) {
        guard let tv = aNotification.object as? NSTableView else { fatalError() }
        let row = tv.selectedRow
        switch tv.tag {
        case 0:
            // category table view
            // select the category
            currentCategory = row
            // reload the filter table based on the current category
            filterTableView.reloadData()
            filterTableView.deselectAll(self)
            filterTableView.noteNumberOfRowsChanged()
        case 1:
            // filter table view
            // select a filter
            // add an effect to current effects list
            currentFilterRow = row
            addEffect()
        default:
            break
        }
    }

    // if we see a double-click in the filter list, it's like hitting apply
    // glue code for determining if a filter layer has a missing image (and should be drawn red to indicate as such)
    // glue code to set up an image layer
}


#if false
@objcMembers class EffectStackBox: NSBox /* subclassed */ {
    var filter: CIFilter?
    var master: EffectStackController?

    let boxInset: CGFloat = 3.0
    let boxFillet: CGFloat = 7.0
        // control point distance from rectangle corner
    let cpdelta: CGFloat = 7.0 /*boxFillet*/ * 0.35

    override func draw(_ r: NSRect) {
        super.draw(r)

        guard let filter = filter, let master = master else { fatalError() }

        if master.effectStackFilterHasMissingImage(filter){
            // overlay the box now - colorized
            NSColor(deviceRed: 1.0, green: 0.0, blue: 0.0, alpha: 0.15).set()
            let path: NSBezierPath = NSBezierPath()
            let R = NSOffsetRect(bounds.insetBy(dx: CGFloat(boxInset), dy: CGFloat(boxInset)), 0, 1)
            let bl = R.origin
            let br = NSPoint(x: R.origin.x + R.size.width, y: R.origin.y)
            let tr = NSPoint(x: R.origin.x + R.size.width, y: R.origin.y + R.size.height)
            let tl = NSPoint(x: R.origin.x, y: R.origin.y + R.size.height)
            path.move(to: NSPoint(x: CGFloat(bl.x + boxFillet), y: bl.y))
            path.line(to: NSPoint(x: CGFloat(br.x - boxFillet), y: br.y))
            path.curve(to: NSPoint(x: br.x, y: CGFloat(br.y + boxFillet)), controlPoint1: NSPoint(x: CGFloat(br.x - cpdelta), y: br.y), controlPoint2: NSPoint(x: br.x, y: CGFloat(br.y + cpdelta)))
            path.line(to: NSPoint(x: tr.x, y: CGFloat(tr.y - boxFillet)))
            path.curve(to: NSPoint(x: CGFloat(tr.x - boxFillet), y: tr.y), controlPoint1: NSPoint(x: tr.x, y: CGFloat(tr.y - cpdelta)), controlPoint2: NSPoint(x: CGFloat(tr.x - cpdelta), y: tr.y))
            path.line(to: NSPoint(x: CGFloat(tl.x + boxFillet), y: tl.y))
            path.curve(to: NSPoint(x: tl.x, y: CGFloat(tl.y - boxFillet)), controlPoint1: NSPoint(x: CGFloat(tl.x + cpdelta), y: tl.y), controlPoint2: NSPoint(x: tl.x, y: CGFloat(tl.y - cpdelta)))
            path.line(to: NSPoint(x: bl.x, y: CGFloat(bl.y + boxFillet)))
            path.curve(to: NSPoint(x: CGFloat(bl.x + boxFillet), y: bl.y), controlPoint1: NSPoint(x: bl.x, y: CGFloat(bl.y + cpdelta)), controlPoint2: NSPoint(x: CGFloat(bl.x + cpdelta), y: bl.y))
            path.close()
            path.fill()
        }
    }

    func setFilter(_ f: CIFilter) {
        filter = f
    }

    func setMaster(_ m: EffectStackController) {
        master = m
    }

    // this is a subclass of NSBox required so we can draw the interior of the box as red when there's something
    // in the box (namely an image well) that still needs filling
}
#endif
