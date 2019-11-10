//  Converted to Swift 5.1 by Swiftify v5.1.30744 - https://objectivec2swift.com/
/*
     File: EffectStackController.swift
 Abstract: This class controls the automatically resizeable effect stack inspector. It must also be able to resize and reconfigure itself when switching documents.
  Version: 2.1

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

import AppKit

private func stringCompare(_ o1: Any?, _ o2: Any?, _ context: UnsafeMutableRawPointer?) -> Int {
    var str1: String?
    var str2: String?

    str1 = o1 as? String
    str2 = o2 as? String
    return str1?.compare(str2 ?? "").rawValue ?? 0
}

class EffectStackController: NSWindowController {
    @IBOutlet var topPlusButton: NSButton! // the plus button at the top of the effect stack inspector (outside of any layer box)
    @IBOutlet var resetButton: NSButton! // the reset button at the top of the effect stack inspector (outside of any layer box)
    @IBOutlet var playButton: NSButton! // the play button at the top of the effect stack inspector (outside of any layer box)
    private var inspectingCoreImageView: CoreImageView? // pointer to the core image view that is currently associated with the effect stack inspector
    private var inspectingEffectStack: EffectStack? // pointer to the effect stack that is currently associated with the effect stack inspector
    private var needsUpdate = false // set this to re-layout the effect stack inspector on update
    private var boxes: [AnyHashable]? // an array of FilterView (subclass of NSBox) that make up the effect stack inspector's UI
    // filter palette stuff
    @IBOutlet var filterPalette: NSWindow! // the filter palette (called image units)
    @IBOutlet var filterOKButton: NSButton! // the apply button, actually
    @IBOutlet var filterCancelButton: NSButton! // the cancel button
    @IBOutlet var categoryTableView: NSTableView! // the category table view
    @IBOutlet var filterTableView: NSTableView! // the filter list table view
    @IBOutlet var filterTextButton: NSButton! // the text button
    private var filterPaletteTopLevelObjects: [AnyHashable]? // an array of the top level objects in the filter palette nib
    private var currentCategory = 0 // the currently selected row in the category table view
    private var currentFilterRow = 0 // the currently selected row in the filter table view
    private var categories: [AnyHashable : Any]? // a dictionary containing all filter category names and the filters that populate the category
    private var filterClassname: String? // returned filter's classname from the modal filter palette (when a filter has been selected)
    private var timer: Timer? /// playing all transitions
    // globals used in the sequential animation of all transitions
    private var transitionStartTime = 0.0
    private var transitionDuration = 0.0
    private var transitionEndTime = 0.0

    static var _sharedEffectStackController: EffectStackController? = nil

    class func shared() -> Self {

        if _sharedEffectStackController == nil {
            _sharedEffectStackController = EffectStackController()
        }
        return _sharedEffectStackController!
    }

    func setAutomaticDefaults(_ f: CIFilter?, at index: Int) {
        if (NSStringFromClass(type(of: f).self) == "CIGlassDistortion") {
            // glass distortion gets a default texture file
            f?.setValue(NSApp.defaultTexture(), forKey: "inputTexture")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultTexturePath(), forKey: "inputTexture")
        } else if (NSStringFromClass(type(of: f).self) == "CIRippleTransition") {
            // ripple gets a material map for shading the ripple that has a transparent alpha except specifically for the shines and darkenings
            f?.setValue(NSApp.defaultAlphaEMap(), forKey: "inputShadingImage")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultAlphaEMapPath(), forKey: "inputShadingImage")
        } else if (NSStringFromClass(type(of: f).self) == "CIPageCurlTransition") {
            // we set up a good page curl default material map (like that for the ripple transition)
            f?.setValue(NSApp.defaultAlphaEMap(), forKey: "inputShadingImage")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultAlphaEMapPath(), forKey: "inputShadingImage")
            // the angle chosen shows off the alpha material map's shine on the leading curl
            f?.setValue(NSNumber(value: -.pi * 0.25), forKey: "inputAngle")
        } else if (NSStringFromClass(type(of: f).self) == "CIShadedMaterial") {
            // shaded material gets an opaque material map that shows off surfaces well
            f?.setValue(NSApp.defaultShadingEMap(), forKey: "inputShadingImage")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultShadingEMapPath(), forKey: "inputShadingImage")
        } else if (NSStringFromClass(type(of: f).self) == "CIColorMap") {
            // color map gets a gradient image that's a color spectrum
            f?.setValue(NSApp.defaultRamp(), forKey: "inputGradientImage")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultRampPath(), forKey: "inputGradientImage")
        } else if (NSStringFromClass(type(of: f).self) == "CIDisintegrateWithMaskTransition") {
            // disintegrate with mask transition gets a mask that has a growing star
            f?.setValue(NSApp.defaultMask(), forKey: "inputMaskImage")
            inspectingEffectStack?.setFilterLayer(index, imageFilePathValue: NSApp.defaultMaskPath(), forKey: "inputMaskImage")
        } else if (NSStringFromClass(type(of: f).self) == "CICircularWrap") {
            // circular wrap needs to be aware of the size of the screen to put its data in the right place
            let bounds = inspectingCoreImageView?.bounds()
            let cx = bounds?.origin.x ?? 0.0 + 0.5 * (bounds?.size.width ?? 0.0)
            let cy = bounds?.origin.y ?? 0.0 + 0.5 * (bounds?.size.height ?? 0.0)
            f?.setValue(CIVector(x: cx, y: cy), forKey: "inputCenter")
        }
    }

    @IBAction func topPlusButtonAction(_ sender: Any) {
        var d: [AnyHashable : Any]?

        d = collectFilterImageOrText()
        if d == nil {
            return
        }
        if (d?["type"] == "filter") {
            insert(d?["filter"] as? CIFilter, atIndex: NSNumber(value: 0))
        } else if (d?["type"] == "image") {
            insert(d?["image"] as? CIImage, withFilename: d?["filename"] as? String, andImageFilePath: d?["imageFilePath"] as? String, atIndex: NSNumber(value: 0))
        } else if (d?["type"] == "text") {
            insert(d?["string"] as? String, with: d?["image"] as? CIImage, atIndex: NSNumber(value: 0))
        }
        enablePlayButton()
    }

    @IBAction func plusButtonAction(_ sender: Any) {
        var d: [AnyHashable : Any]?
        var index: Int

        d = collectFilterImageOrText()
        if d == nil {
            return
        }
        index = sender.tag() + 1
        if (d?["type"] == "filter") {
            insert(d?["filter"] as? CIFilter, atIndex: NSNumber(value: index))
        } else if (d?["type"] == "image") {
            insert(d?["image"] as? CIImage, withFilename: d?["filename"] as? String, andImageFilePath: d?["imageFilePath"] as? String, atIndex: NSNumber(value: index))
        } else if (d?["type"] == "text") {
            insert(d?["string"] as? String, with: d?["image"] as? CIImage, atIndex: NSNumber(value: index))
        }
        enablePlayButton()
    }

    @IBAction func minusButtonAction(_ sender: Any) {
        removeFilterImageOrText(atIndex: NSNumber(value: sender.tag()))
        enablePlayButton()
    }

    @IBAction func resetButtonAction(_ sender: Any) {
        var i: Int
        var count: Int

        // kill off all layers from the effect stack
        count = inspectingEffectStack?.layerCount() ?? 0
        if count == 0 {
            return
        }
        // note: done using glue primitives so it will be an undoable operation
        if !(inspectingEffectStack?.type(atIndex: 0) == "image") {
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

    func playButtonAction(_ sender: ) {
        var i: Int
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

    func layoutInspector() {
        // decide how inspector is to be sized and layed out
        // boxes are all internally sized properly at this point
        var i: Int
        var count: Int
        var inspectorheight: Int
        var fvtop: Int
        var fv: FilterView?

        // first estimate the size of the effect stack inspector (with the boxes placed one after another vertically)
        count = boxes?.count ?? 0
        inspectorheight = inspectorTopY
        for i in 0..<count {
            fv = boxes?[i] as? FilterView
            let height = fv?.bounds().size.height ?? 0.0
            // add the height of the box plus some spacing
            inspectorheight += Int(height + 6)
        }
        // resize the effect stack inspector now
        var frm = window?.frame
        let delta = CGFloat(inspectorheight) + (window?.frame.size.height ?? 0.0) - (window?.contentView?.frame.size.height ?? 0.0) - (frm?.size.height ?? 0.0)
        frm?.size.height += delta
        frm?.origin.y -= delta
        window?.setFrame(frm ?? NSRect.zero, display: true, animate: true) // animate the window size change
        // and move all the boxes into place

        fvtop = inspectorheight - inspectorTopY
        for i in 0..<count {
            fv = boxes?[i] as? FilterView
            frm = fv?.frame()
            frm?.origin.y = CGFloat(fvtop) - (frm?.size.height ?? 0.0)
            fv?.frame = frm
            fvtop -= Int((frm?.size.height ?? 0.0) + 6)
            // unhide the box
            fv?.hidden = false
        }
        // finally call for a redisplay of the effect stack inspector
        window?.contentView?.needsDisplay = true
    }

    func newUI(for f: CIFilter?, index: Int) -> FilterView? {
        var hasBackground: Bool
        var attr: [AnyHashable : Any]?
        var inputKeys: [AnyHashable]?
        var key: String?
        var typestring: String?
        var classstring: String?
        var enumerator: NSEnumerator?
        var frame: NSRect
        var fv: FilterView?
        var view: NSView?

        // create box first
        view = window?.contentView
        frame = view?.bounds ?? NSRect.zero
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        fv = FilterView(frame: frame)
        fv?.filter = f
        fv?.hidden = true
        if let fv = fv {
            window?.contentView?.addSubview(fv)
        }
        fv?.titlePosition = NSBox.TitlePosition.noTitle
        fv?.autoresizingMask = [.width, .minYMargin]
        fv?.borderType = NSBorderType.grooveBorder
        fv?.boxType = NSBox.BoxType.primary
        fv?.master = self
        fv?.tag = index
        // first compute size of box with all the controls
        fv?.tryFilterHeader(f)
        attr = f?.attributes
        inputKeys = f?.inputKeys
        // decide if this filter has a background image parameter (true for blend modes and Porter-Duff modes)
        hasBackground = false
        enumerator = (inputKeys as NSArray?)?.objectEnumerator()
        while (key = enumerator?.nextObject() as? String) != nil {
            let parameter = attr?[key ?? ""]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "CIImage") && (key == "inputBackgroundImage") {
                    hasBackground = true
                }
            }
        }
        // enumerate all input parameters and reserve space for their generated UI
        enumerator = (inputKeys as NSArray?)?.objectEnumerator()
        while (key = enumerator?.nextObject() as? String) != nil {
            let parameter = attr?[key ?? ""]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "NSNumber") {
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if (typestring == kCIAttributeTypeBoolean) {
                        // if it's a boolean type, save space for a check box
                        fv?.tryCheckBox(for: f, key: key, display: inspectingCoreImageView)
                    } else {
                        // otherwise space space for a slider
                        fv?.trySlider(for: f, key: key, display: inspectingCoreImageView)
                    }
                } else if (classstring == "CIColor") {
                    // save space for a color well
                    fv?.tryColorWell(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIImage") {
                    // don't bother to create a UI element for the chained image
                    if hasBackground {
                        // the chained image is the background image for blend modes and Porter-Duff modes
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputBackgroundImage") {
                            // save space for an image well
                            fv?.tryImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    } else {
                        // the chained image is the input image for all other filters
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputImage") {
                            // save space for an image well
                            fv?.tryImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    }
                } else if (classstring == "NSAffineTransform") {
                    // save space for transform inspection widgets
                    fv?.tryTransform(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIVector") {
                    // check for a vector with no attributes
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if typestring == nil {
                        // save space for a 4-element vector inspection widget (4 text fields)
                        fv?.tryVector(for: f, key: key, display: inspectingCoreImageView)
                    } else if (typestring == kCIAttributeTypeOffset) {
                        fv?.tryOffset(for: f, key: key, display: inspectingCoreImageView)
                    }
                    // note: the other CIVector parameters are handled in mouse down processing of the core image view
                }
            }
        }
        // now resize the box to hold the controls we're about to make
        fv?.trimBox()
        // now add all the controls
        fv?.addFilterHeader(f, tag: index, enabled: inspectingEffectStack?.layerEnabled(index))
        attr = f?.attributes
        inputKeys = f?.inputKeys
        // enumerate all input parameters and generate their UI
        enumerator = (inputKeys as NSArray?)?.objectEnumerator()
        while (key = enumerator?.nextObject() as? String) != nil {
            let parameter = attr?[key ?? ""]
            if (parameter is [AnyHashable : Any]) {
                classstring = (parameter as? [AnyHashable : Any])?[kCIAttributeClass] as? String
                if (classstring == "NSNumber") {
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if (typestring == kCIAttributeTypeBoolean) {
                        // if it's a boolean type, generate a check box
                        fv?.addCheckBox(for: f, key: key, display: inspectingCoreImageView)
                    } else {
                        // otherwise generate a slider
                        fv?.addSlider(for: f, key: key, display: inspectingCoreImageView)
                    }
                } else if (classstring == "CIImage") {
                    if hasBackground {
                        // the chained image is the background image for blend modes and Porter-Duff modes
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputBackgroundImage") {
                            // generate an image well
                            fv?.addImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    } else {
                        // the chained image is the input image for all other filters
                        // it is provided by what's above this layer in the effect stack
                        if !(key == "inputImage") {
                            // generate an image well
                            fv?.addImageWell(for: f, key: key, display: inspectingCoreImageView)
                        }
                    }
                } else if (classstring == "CIColor") {
                    // generate a color well
                    fv?.addColorWell(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "NSAffineTransform") {
                    // generate transform inspection widgets
                    fv?.addTransform(for: f, key: key, display: inspectingCoreImageView)
                } else if (classstring == "CIVector") {
                    // check for a vector with no attributes
                    typestring = (parameter as? [AnyHashable : Any])?[kCIAttributeType] as? String
                    if typestring == nil {
                        // generate a 4-element vector inspection widget (4 text fields)
                        fv?.addVector(for: f, key: key, display: inspectingCoreImageView)
                    } else if (typestring == kCIAttributeTypeOffset) {
                        fv?.addOffset(for: f, key: key, display: inspectingCoreImageView)
                    }
                    // the rest are handled in mouse down processing
                }
            }
        }
        // retrun the box with the filter's UI
        return fv
    }

    func newUI(for im: CIImage?, filename: String?, index: Int) -> FilterView? {
        var frame: NSRect
        var fv: FilterView?
        var view: NSView?

        // create the box first
        view = window?.contentView
        frame = view?.bounds ?? NSRect.zero
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        fv = FilterView(frame: frame)
        fv?.filter = nil
        fv?.hidden = true
        if let fv = fv {
            window?.contentView?.addSubview(fv)
        }
        fv?.titlePosition = NSBox.TitlePosition.noTitle
        fv?.autoresizingMask = [.width, .minYMargin]
        fv?.borderType = NSBorderType.grooveBorder
        fv?.boxType = NSBox.BoxType.primary
        fv?.master = self
        fv?.tag = index
        // first compute size of box with all the controls
        fv?.tryImageHeader(im)
        fv?.tryImageWell(for: im, tag: index, display: inspectingCoreImageView)
        // now resize the box to hold the controls we're about to make
        fv?.trimBox()
        // now add all the controls
        fv?.addImageHeader(im, filename: filename, tag: index, enabled: inspectingEffectStack?.layerEnabled(index))
        fv?.addImageWell(for: im, tag: index, display: inspectingCoreImageView)
        return fv
    }

    func newUI(forText string: String?, index: Int) -> FilterView? {
        var frame: NSRect
        var fv: FilterView?
        var view: NSView?

        // create the box first
        view = window?.contentView
        frame = view?.bounds ?? NSRect.zero
        frame.size.width -= 12
        frame.origin.x += 6
        frame.size.height -= CGFloat(inspectorTopY)
        fv = FilterView(frame: frame)
        fv?.filter = nil
        fv?.hidden = true
        if let fv = fv {
            window?.contentView?.addSubview(fv)
        }
        fv?.titlePosition = NSBox.TitlePosition.noTitle
        fv?.autoresizingMask = [.width, .minYMargin]
        fv?.borderType = NSBorderType.grooveBorder
        fv?.boxType = NSBox.BoxType.primary
        fv?.master = self
        fv?.tag = index
        // first compute size of box with all the controls
        fv?.tryTextHeader(string)
        fv?.tryTextViewForString()
        fv?.trySliderForText()
        // now resize the box to hold the controls we're about to make
        fv?.trimBox()
        // now add all the controls
        fv?.addTextHeader(string, tag: index, enabled: inspectingEffectStack?.layerEnabled(index))
        fv?.addTextView(forString: inspectingEffectStack?.mutableDictionary(at: index), key: "string", display: inspectingCoreImageView)
        fv?.addSlider(forText: inspectingEffectStack?.mutableDictionary(at: index), key: "scale", lo: 1.0, hi: 100.0, display: inspectingCoreImageView)
        return fv
    }

    func _loadFilterListIntoInspector() {
        var cat: String?
        var attrs: [AnyHashable]?
        var all: [AnyHashable]?
        var i: Int
        var m: Int

        // here's a list of all categories
        attrs = [kCICategoryGeometryAdjustment, kCICategoryDistortionEffect, kCICategoryBlur, kCICategorySharpen, kCICategoryColorAdjustment, kCICategoryColorEffect, kCICategoryStylize, kCICategoryHalftoneEffect, kCICategoryTileEffect, kCICategoryGenerator, kCICategoryGradient, kCICategoryTransition, kCICategoryCompositeOperation]
        // call to load all plug-in image units
        CIPlugIn.loadAllPlugIns()
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

    @IBAction func filterOKButtonAction(_ sender: Any) {
        // signal to apply filter
        NSApp.stopModal(withCode: 100)
    }

    @IBAction func filterCancelButtonAction(_ sender: Any) {
        // signal cancel
        NSApp.stopModal(withCode: 101)
    }

    @IBAction func filterImageButtonAction(_ sender: Any) {
        // signal to get an image
        NSApp.stopModal(withCode: 102)
    }

    @IBAction func filterTextButtonAction(_ sender: Any) {
        // signal to setup a text layer
        NSApp.stopModal(withCode: 103)
    }

    @IBAction func tableViewDoubleClick(_ sender: Any) {
        NSApp.stopModal(withCode: 100)
    }

    func setNeedsUpdate(_ b: Bool) {
        needsUpdate = b
    }

    func updateLayout() {
        needsUpdate = true
        window?.update()
    }

    func effectStackFilterHasMissingImage(_ f: CIFilter?) -> Bool {
        return inspectingEffectStack?.filterHasMissingImage(f) ?? false
    }

    func closeDown() {
        // resize inspector now
        let frm = window?.frame
        let delta = CGFloat(inspectorTopY) + (window?.frame.size.height ?? 0.0) - (window?.contentView?.frame.size.height ?? 0.0) - (frm?.size.height ?? 0.0)
        frm?.size.height += delta
        frm?.origin.y -= delta
        window?.setFrame(frm ?? NSRect.zero, display: true, animate: false) // skip animation on quit!
    }

    func setLayer(_ index: Int, image im: CIImage?, andFilename filename: String?) {
        inspectingEffectStack?.setImageLayer(index, image: im, andFilename: filename)
    }

    func setChanges() {
        doc()?.updateChangeCount(NSDocument.ChangeType.changeDone)
    }

    func setCoreImageView(_ v: CoreImageView?) {
        inspectingCoreImageView = v
    }

    func removeFilterImageOrText(atIndex index: NSNumber?) {
        var type: String? = nil
        var filter: CIFilter? = nil
        var image: CIImage? = nil
        var filename: String? = nil
        var string: String? = nil
        var path: String? = nil

        // first get handles to parameters we want to retain for "save for undo"
        type = inspectingEffectStack?.type(at: index?.intValue ?? 0)
        if (type == "filter") {
            filter = inspectingEffectStack?.filter(at: index?.intValue ?? 0)
        } else if (type == "image") {
            image = inspectingEffectStack?.image(at: index?.intValue ?? 0)
            filename = inspectingEffectStack?.filename(at: index?.intValue ?? 0)
            path = inspectingEffectStack?.imageFilePath(at: index?.intValue ?? 0)
        } else if (type == "text") {
            image = inspectingEffectStack?.image(at: index?.intValue ?? 0)
            string = inspectingEffectStack?.string(at: index?.intValue ?? 0)
        }
        // actually remove the layer from the effect stack here
        inspectingEffectStack?.removeLayer(at: index?.intValue ?? 0)
        // do "save for undo"
        if (type == "filter") {
            doc()?.undoManager().prepare(withInvocationTarget: self).insert(filter, atIndex: index)
            doc()?.undoManager().setActionName("Filter \(CIFilter.localizedName(forFilterName: NSStringFromClass(type(of: filter).self)) ?? "")")
        } else if (type == "image") {
            doc()?.undoManager().prepare(withInvocationTarget: self).insert(image, withFilename: filename, andImageFilePath: path, atIndex: index)
            doc()?.undoManager().setActionName("Image \(filename?.lastPathComponent ?? "")")
        } else if (type == "string") {
            doc()?.undoManager().prepare(withInvocationTarget: self).insert(string, with: image, atIndex: index)
            doc()?.undoManager().setActionName("Text")
        }

        if filter != nil {
        }
        if image != nil {
        }
        if filename != nil {
        }
        if string != nil {
        }

        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    func reconfigureWindow() {
        var path: String?
        var image: CIImage?
        var extent: CGRect

        path = inspectingEffectStack?.imageFilePath(atIndex: 0)
        image = inspectingEffectStack?.image(atIndex: 0)
        extent = image?.extent ?? CGRect.zero
        doc()?.reconfigureWindow(toSize: NSMakeSize(extent.size.width, extent.size.height), andPath: path)
    } // called when dragging into or choosing base image to reconfigure the document's window

    // for retaining full file names of images
    func registerImageLayer(_ index: Int, imageFilePath path: String?) {
        inspectingEffectStack?.setImageLayer(index, imageFilePath: path)
    }

    func registerFilterLayer(_ filter: CIFilter?, key: String?, imageFilePath path: String?) {
        var i: Int
        var count: Int
        var type: String?

        count = inspectingEffectStack?.layerCount() ?? 0
        for i in 0..<count {
            type = inspectingEffectStack?.type(at: i)
            if !(type == "filter") {
                continue
            }
            if filter == inspectingEffectStack?.filter(at: i) {
                inspectingEffectStack?.setFilterLayer(i, imageFilePathValue: path, forKey: key)
                break
            }
        }
    }

    func imageFilePath(forImageLayer index: Int) -> String? {
        return inspectingEffectStack?.imageFilePath(at: index)
    }

    func imageFilePath(forFilterLayer filter: CIFilter?, key: String?) -> String? {
        var i: Int
        var count: Int
        var type: String?

        count = inspectingEffectStack?.layerCount() ?? 0
        for i in 0..<count {
            type = inspectingEffectStack?.type(at: i)
            if !(type == "filter") {
                continue
            }
            if filter == inspectingEffectStack?.filter(at: i) {
                return inspectingEffectStack?.filterLayer(i, imageFilePathValueForKey: key)
            }
        }
        return nil
    }

    // since the effect stack inspector window is global to all documents, we here provide a way of accessing the shared window
    // load from nib (really only the stuff at the top of the inspector)
    convenience init() {
        self.init(windowNibName: "EffectStack")
        windowFrameAutosaveName = "EffectStack"
        // set up an array to hold the representations of the layers from the effect stack we inspect
        boxes = [AnyHashable](repeating: 0, count: 10)
        filterPaletteTopLevelObjects = []
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

    // reset the core image view (used when going to into full screen mode and back out)
    // flag that we need to reconfigure ourselves after some effect stack change
    func enablePlayButton() {
        var enabled: Bool
        var i: Int
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

    // when a window loads from the nib file, we set up the core image view pointer and effect stack pointers
    // and set up notifications
    override func windowDidLoad() {
        super.windowDidLoad()
        setMainWindow(NSApp.mainWindow())
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowChanged(_:)), name: NSWindow.didBecomeMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mainWindowResigned(_:)), name: NSWindow.didResignMainNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NSWindowDelegate.windowDidUpdate(_:)), name: NSWindow.didUpdateNotification, object: nil)
        NSColorPanel.shared.showsAlpha = true
    }

    // when window changes, update the pointers
    @objc func mainWindowChanged(_ notification: Notification?) {
        setMainWindow(notification?.object as? NSWindow)
    }

    // dissociate us when the window is gone.
    @objc func mainWindowResigned(_ notification: Notification?) {
        setMainWindow(nil)
    }

    // when we see an update, check for the flag that tells us to reconfigure our effect stack inspection
    @objc func windowDidUpdate(_ notification: Notification) {
        var i: Int
        var count: Int
        var filter: CIFilter?
        var w: NSWindow?
        var type: String?
        var string: String?
        var image: CIImage?

        w = notification.object as? NSWindow
        if w != window {
            return
        }
        if needsUpdate {
            // we need an update
            needsUpdate = false
            // remove tthe old boxes from the UI
            count = boxes?.count ?? 0
            for i in 0..<count {
                boxes?[i].removeFromSuperview()
            }
            // and clear out the boxes array
            boxes?.removeAll()
            // now, if required, automatically generate the effect stack UI into separate boxes for each layer
            if inspectingEffectStack != nil {
                // create all boxes shown in the effect stack inspector from scratch, and place them into an array for layout purposes
                count = inspectingEffectStack?.layerCount() ?? 0
                for i in 0..<count {
                    type = inspectingEffectStack?.type(at: i)
                    if (type == "filter") {
                        filter = inspectingEffectStack?.filter(at: i)
                        if let autorelease = newUI(for: filter, index: i) {
                            boxes?.append(autorelease)
                        }
                    } else if (type == "image") {
                        image = inspectingEffectStack?.image(at: i)
                        if let autorelease = newUI(for: image, filename: inspectingEffectStack?.filename(at: i), index: i) {
                            boxes?.append(autorelease)
                        }
                    } else if (type == "text") {
                        string = inspectingEffectStack?.string(at: i)
                        if let autorelease = newUI(forText: string, index: i) {
                            boxes?.append(autorelease)
                        }
                    }
                }
            }
            // now lay it out
            layoutInspector()
        }
    }

    // this method brings up the "image units palette" (we call it the filter palette) - and it also has buttons for images and text layers
    func collectFilterImageOrText() -> [AnyHashable : Any]? {
        var i: Int
        var im: CIImage?
        var url: URL?
        var op: NSOpenPanel?

        // when running the filter palette, if a filter is chosen (as opposed to an image or text) then filterClassname returns the
        // class name of the chosen filter

        filterClassname = nil

        // load the nib for the filter palette
        var topLevelObjects: [AnyHashable]?
        Bundle.main.loadNibNamed("FilterPalette", owner: self, topLevelObjects: &topLevelObjects)
        // keep the top level objects in the filterPaletteTopLevelObjects array
        for i in 0..<(topLevelObjects?.count ?? 0) {
            if let object = topLevelObjects?[i] {
                if !(filterPaletteTopLevelObjects?.contains(object) ?? false) {
                    filterPaletteTopLevelObjects?.append(object)
                }
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
        i = NSApp.runModal(for: filterPalette).rawValue
        filterPalette.close()
        if i == 100 {
            // Apply
            // create the filter layer dictionary
            if let filter1 = CIFilter(name: filterClassname ?? "") {
                return [
                "type" : "filter",
                "filter" : filter1
                ]
            }
            return nil
        } else if i == 101 {
            // Cancel
            return nil
        } else if i == 102 {
            // Image
            // use the open panel to open an image
            op = NSOpenPanel()
            op?.allowsMultipleSelection = false
            op?.canChooseDirectories = false
            op?.resolvesAliases = true
            op?.canChooseFiles = true
            // run the open panel with the allowed types
            op?.allowedFileTypes = ["jpg", "jpeg", "tif", "tiff", "png", "crw", "cr2", "raf", "mrw", "nef", "srf", "exr"]
            let j = op?.runModal()?.rawValue ?? 0
            if j == NSOKButton {

                // get image from open panel
                url = op?.urls[0]
                if let url = url {
                    im = CIImage(contentsOf: url)
                }
                // create the image layer dictionary
                if let im = im {
                    return [
                    "type" : "image",
                    "image" : im,
                    "filename" : url?.lastPathComponent,
                    "imageFilePath" : url?.path
                    ]
                }
                return nil
            } else if j == NSCancelButton {
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

    // set changes (dirty the document)
    // call to directly update (and re-layout) the configuration of the effect stack inspector
    // this is the glue code you call to insert a filter layer into the effect stack. this handles save for undo, etc.
    func insert(_ f: CIFilter?, atIndex index: NSNumber?) {
        // actually insert the filter layer into the effect stack
        inspectingEffectStack?.insertFilterLayer(f, at: index?.intValue ?? 0)
        // set filter attributes to their defaults
        (inspectingEffectStack?.filter(at: index?.intValue ?? 0)).setDefaults()
        // set any automatic defaults we need (generally the odd image parameter)
        setAutomaticDefaults(inspectingEffectStack?.filter(at: index?.intValue ?? 0), at: index?.intValue ?? 0)
        // do "save for undo"
        doc()?.undoManager().prepare(withInvocationTarget: self).removeFilterImageOrText(atIndex: index)
        doc()?.undoManager().setActionName("Filter \(CIFilter.localizedName(forFilterName: NSStringFromClass(type(of: f).self)) ?? "")")
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    // this is the high-level glue code you call to insert an image layer into the effect stack. this handles save for undo, etc.
    func insert(_ image: CIImage?, withFilename filename: String?, andImageFilePath path: String?, atIndex index: NSNumber?) {
        // actually insert the image layer into the effect stack
        inspectingEffectStack?.insertImageLayer(image, withFilename: filename, at: index?.intValue ?? 0)
        inspectingEffectStack?.setImageLayer(index?.intValue ?? 0, imageFilePath: path)
        // do "save for undo"
        doc()?.undoManager().prepare(withInvocationTarget: self).removeFilterImageOrText(atIndex: index)
        doc()?.undoManager().setActionName("Image \(filename?.lastPathComponent ?? "")")
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    // this is the high-level glue code you call to insert a text layer into the effect stack. this handles save for undo, etc.
    func insert(_ string: String?, with image: CIImage?, atIndex index: NSNumber?) {
        // actually insert the text layer into the effect stack
        inspectingEffectStack?.insertTextLayer(string, with: image, at: index?.intValue ?? 0)
        // do "save for undo"
        doc()?.undoManager().prepare(withInvocationTarget: self).removeFilterImageOrText(atIndex: index)
        doc()?.undoManager().setActionName("Text")
        // dirty the documdent
        setChanges()
        // redo the effect stack inspector's layout after the change
        updateLayout()
        // finally, let core image render the view
        inspectingCoreImageView?.needsDisplay = true
    }

    // this is the high-level glue code you call to remove a layer (of any kind) from the effect stack. this handles save for undo, etc.
    // the "global" plus button inserts a layer before the first layer
    // this handles a change to each layer's "enable" check box
    @IBAction func enableCheckBoxAction(_ sender: Any) {
        inspectingEffectStack?.setLayer(sender.tag(), enabled: (sender.state() == .on) ? true : false)
        setChanges()
        inspectingCoreImageView?.needsDisplay = true
    }

    // a layer's plus button inserts another new layer after this one
    // for a new filter, set up the odd image parameter
    // a layer's mins button removes the layer
    // the reset button removes all layers from the effect stack
    // stop the transition timer
    func stopTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
    }

    // start the transition timer
    func startTimer() {
        if timer == nil {
            timer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(autoTimer(_:)), userInfo: nil, repeats: true)
            timer
        }
    }

    // called by the transition timer every 1/30 second
    // this animates the transitions in sequence - one after another
    @objc func autoTimer(_ sender: Any?) {
        var count: Int
        var i: Int
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

    // handle the play button - play all transitions
    // this must be in synch with EffectStack.nib
let inspectorTopY = 36

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
    func categoryName(for i: Int) -> String? {
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
        return s
    }

    // return the category index for the category name - used by filter palette category table view
    func index(forCategory nm: String?) -> Int {
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

    // build a dictionary of approved filters in a given category for the filter inspector
    func buildFilterDictionary(_ names: [AnyHashable]?) -> [AnyHashable : Any]? {
        var inspectable: Bool
        var attr: [AnyHashable : Any]?
        var parameter: [AnyHashable : Any]?
        var inputKeys: [AnyHashable]?
        var enumerator: NSEnumerator?
        var td: [AnyHashable : Any]?
        var catfilters: [AnyHashable : Any]?
        var classname: String?
        var classstring: String?
        var key: String?
        var typestring: String?
        var filter: CIFilter?
        var i: Int

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
                enumerator = (inputKeys as NSArray?)?.objectEnumerator()
                while (key = enumerator?.nextObject() as? String) != nil {
                    parameter = attr?[key ?? ""] as? [AnyHashable : Any]
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

    // build the filter list (enumerates all filters)
    // table view data source methods
    func numberOfRows(in tv: NSTableView?) -> Int {
        var count: Int
        var s: String?
        var dict: [AnyHashable : Any]?
        var filterNames: [AnyHashable]?

        switch tv?.tag {
            case 0:
                // category table view
                count = 13
            case 1:
                fallthrough
            default:
                // filter table view
                s = categoryName(for: currentCategory)
                // use category name to get dictionary of filter names
                dict = categories?[s ?? ""] as? [AnyHashable : Any]
                // create an array
                filterNames = dict?.keys
                // return number of filters in this category
                count = filterNames?.count ?? 0
        }
        return count
    }

    func tableView(_ tv: NSTableView, objectValueFor tc: NSTableColumn?, row: Int) -> Any? {
        var s: String?
        var dict: [AnyHashable : Any]?
        var filterNames: [AnyHashable]?
        var tfc: NSTextFieldCell?

        switch tv.tag {
            case 0:
                // category table view
                s = categoryName(for: row)
                tfc = tc?.dataCell as? NSTextFieldCell
                // handle names that are too long by ellipsizing the name
                s = ParameterView.ellipsizeField(tc?.width, font: tfc?.font, string: s)
            case 1:
                fallthrough
            default:
                // filter table view
                // we need to maintain the filter names in a sorted order.
                s = categoryName(for: currentCategory)
                // use label (category name) to get dictionary of filter names
                dict = categories?[s ?? ""] as? [AnyHashable : Any]
                // create an array of the sorted names (this is inefficient since we don't cache the sorted array)
                filterNames = (dict?.keys as NSArray?)?.sortedArray(stringCompare, context: nil) as? [AnyHashable]
                // return filter name
                s = filterNames?[row] as? String
                tfc = tc?.dataCell as? NSTextFieldCell
                // handle names that are too long by ellipsizing the name
                s = ParameterView.ellipsizeField(tc?.width, font: tfc?.font, string: s)
        }
        return s
    }

    // this is called when we select a filter from the list
    func addEffect() {
        var row: Int
        var tv: NSTableView?
        var dict: [AnyHashable : Any]?
        var td: [AnyHashable : Any]?
        var filterNames: [AnyHashable]?

        // get current category item
        tv = filterTableView
        // decide current filter name from selected row (or none selected) in the filter name list
        row = tv?.selectedRow ?? 0
        if row == -1 {
            filterClassname = nil
            filterOKButton.isEnabled = false
            return
        }
        // use label (category name) to get dictionary of filter names
        dict = categories?[categoryName(for: currentCategory) ?? ""] as? [AnyHashable : Any]
        // create an array of all filter names for this category
        filterNames = (dict?.keys as NSArray?)?.sortedArray(stringCompare, context: nil) as? [AnyHashable]
        // return filter name
        if let object = filterNames?[row] {
            td = dict?[object] as? [AnyHashable : Any]
        }
        // retain the name in filterClassname for use outside the modal

        filterClassname = td?[kCIAttributeClass] as? String
        // enable the apply button
        filterOKButton.isEnabled = true
    }

    func tableViewSelectionDidChange(_ aNotification: Notification) {
        var row: Int
        var tv: NSTableView?

        tv = aNotification.object as? NSTableView
        row = tv?.selectedRow ?? 0
        switch tv?.tag {
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

class EffectStackBox: NSBox /* subclassed */ {
    var filter: CIFilter?
    var master: EffectStackController?

    func draw(_ r: NSRect) {
        var path: NSBezierPath?
        var bl: NSPoint
        var br: NSPoint
        var tr: NSPoint
        var tl: NSPoint
        var R: NSRect

        super.draw(r)
        if master?.effectStackFilterHasMissingImage(filter) ?? false {
            // overlay the box now - colorized
            NSColor(deviceRed: 1.0, green: 0.0, blue: 0.0, alpha: 0.15).set()
            path = NSBezierPath()
            R = NSOffsetRect(bounds().insetBy(dx: CGFloat(boxInset), dy: CGFloat(boxInset)), 0, 1)
            bl = R.origin
            br = NSPoint(x: R.origin.x + R.size.width, y: R.origin.y)
            tr = NSPoint(x: R.origin.x + R.size.width, y: R.origin.y + R.size.height)
            tl = NSPoint(x: R.origin.x, y: R.origin.y + R.size.height)
            path?.move(to: NSPoint(x: CGFloat(bl.x + boxFillet), y: bl.y))
            path?.line(to: NSPoint(x: CGFloat(br.x - boxFillet), y: br.y))
            path?.curve(to: NSPoint(x: br.x, y: CGFloat(br.y + boxFillet)), controlPoint1: NSPoint(x: CGFloat(br.x - cpdelta), y: br.y), controlPoint2: NSPoint(x: br.x, y: CGFloat(br.y + cpdelta)))
            path?.line(to: NSPoint(x: tr.x, y: CGFloat(tr.y - boxFillet)))
            path?.curve(to: NSPoint(x: CGFloat(tr.x - boxFillet), y: tr.y), controlPoint1: NSPoint(x: tr.x, y: CGFloat(tr.y - cpdelta)), controlPoint2: NSPoint(x: CGFloat(tr.x - cpdelta), y: tr.y))
            path?.line(to: NSPoint(x: CGFloat(tl.x + boxFillet), y: tl.y))
            path?.curve(to: NSPoint(x: tl.x, y: CGFloat(tl.y - boxFillet)), controlPoint1: NSPoint(x: CGFloat(tl.x + cpdelta), y: tl.y), controlPoint2: NSPoint(x: tl.x, y: CGFloat(tl.y - cpdelta)))
            path?.line(to: NSPoint(x: bl.x, y: CGFloat(bl.y + boxFillet)))
            path?.curve(to: NSPoint(x: CGFloat(bl.x + boxFillet), y: bl.y), controlPoint1: NSPoint(x: bl.x, y: CGFloat(bl.y + cpdelta)), controlPoint2: NSPoint(x: CGFloat(bl.x + cpdelta), y: bl.y))
            path?.close()
            path?.fill()
        }
    }

    func setFilter(_ f: CIFilter?) {
        filter = f
    }

    func setMaster(_ m: EffectStackController?) {
        master = m
    }

    // this is a subclass of NSBox required so we can draw the interior of the box as red when there's something
    // in the box (namely an image well) that still needs filling

let boxInset = 3.0
let boxFillet = 7.0
    // control point distance from rectangle corner
let cpdelta = boxFillet * 0.35
}