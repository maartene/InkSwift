//
//  InkStory.swift
//  InkSwift
//
//  Created by Maarten Engels on 13/04/2020.
//  Copyright © 2020 thedreamweb. All rights reserved.
//

import Foundation
import JavaScriptCore
import Combine

/// The InkStory class allows you to run Ink stories from Swift applications.
///
/// InkStory conforms to `ObservableObject`, so it's very easy to integrate into `SwiftUI`.
public final class InkStory: ObservableObject {
    struct SaveState: Codable {
        let jsonState: String
        let currentTags: [String: String]
    }
    
    var jsContext: JSContext! = JSContext()
    
    /// Tags specified in this array retain their value after the line where they are declared (making them act kind of like a variable).
    ///
    /// By default, tags only have a value on the line they are defined (they are not retained). In some cases though, it might be useful to retain the value of a tag even after it is set. (This makes them act more like a variable). This array allows you to add tags that should be retained.
    /// By default, we retain the "IMAGE" tag. This way, an image persists between story parts, until a different image is set.
    /// If you don't want this behaviour, set `inkStory.retainTags = []`
    ///
    public var retainTags = ["IMAGE"]
    
    
    /// Creates a new InkStory
    ///
    /// The created Ink story contains the Ink framework, but is completely empty from a content point of view. Start using it using ``loadStory(json:)``.
    public init() {
        currentText = ""
        canContinue = false
        options = [Option]()
        currentTags = [String: String]()
        globalTags = [String: String]()
        oberservedVariables = [String: JSValue]()
        currentErrors = [String]()
        
        guard let jsInkUrl = Bundle.module.url(forResource: "ink", withExtension: "js") else {
            fatalError("Failed to locate InkJS in bundle.")
        }
        
        guard let data = try? Data(contentsOf: jsInkUrl) else {
            fatalError("Failed to load InkJS from bundle.")
        }
        
        guard let jsInkUrlString = String(data: data, encoding: .utf8) else {
            fatalError("Unable to parse InkJS as string.")
        }
        
        jsContext.evaluateScript(jsInkUrlString)
    }
    
    
    /// Compiles and runs an Ink story based on specified Ink code.
    /// - Parameter ink: The story to load in Ink format.
    ///
    /// WARNING: This method is not yet implemented as the Ink compiler is not yet part of the InkJS distribution.
    public func loadStory(ink: String) {
        fatalError("Not implemented.")
        
        jsContext.evaluateScript("const story  = (new inkjs.Compiler('\(ink)')).Compile()")
        continueStory()
        print("Succesfully loaded and compiled InkStory.")
    }
    
    /*public func inkStoryJson(fileName: String, fileExtension: String?) -> String {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
            fatalError("Could not find ink story file.")
        }
        
        do {
            return try String(contentsOf: url)
        } catch {
            print(error)
        }
        return ""
    }*/
    
    /// Loads an Ink story from the Ink stories JSON representations.
    /// - Parameter json: JSON representation from the Ink Story.
    ///
    /// InkStory can't load Ink files directly, but relies on the Ink representation in JSON. The easiest way to create a JSON representation of an Ink story is to use  [Inky's](https://github.com/inkle/inky/releases/tag/0.11.0) 'Export to JSON...' menu option. Another option is to use [Inklecate](https://github.com/inkle/ink/releases).
    ///
    /// Also note, this method requires the actual JSON, not a filename.
    public func loadStory(json: String) {
        
        jsContext.evaluateScript("story = new inkjs.Story(\(json));")
        continueStory()
        
        print("Succesfully loaded InkStory.")
    }
    
    /// The text output for the current location in the Ink story.
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var currentText: String
    
    /// Whether it is possible to continue the current story.
    ///
    /// When this value is true, you can call ``continueStory()`` on the story.
    /// Reasons why you might not be able to continue the story:
    /// * The story is presenting a choice
    /// * The story reached it's end (there is no more content)
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var canContinue: Bool
    
    /// The current options in the Ink story.
    ///
    /// When there are no options, this property's value is `[]`.
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var options: [Option]
    
    /// The global tags and their current values
    ///
    /// This is a dictionary of the form `tag` => `value`. Note that tags don't need to have an associated value. If that is the case, then `value` = `tag`.
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var globalTags: [String: String]
    
    /// Currently active errors in the Ink story.
    ///
    /// When there are no options, this property's value is `[]`.
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var currentErrors: [String]
    
    /// The currently active tags and their (current) values.
    ///
    /// This is a dictionary of the form `tag` => `value`. Note that tags don't need to have an associated value. If that is the case, then `value` = `tag`.
    ///
    /// You can use `Combine` to subscribe to changes in this property.
    @Published public var currentTags: [String: String]
    
    /// The Ink variable's value changes which trigger Combine to publish a value change.
    ///
    /// All variables can be inspected using ``getVariable(_:)``. This property exists mainly for combine to signal the change to specific Ink variables.
    @Published public var oberservedVariables: [String: JSValue]
    
    private func refreshState() {
        currentText = jsContext.evaluateScript("story.currentText;")?.toString() ?? ""
        refreshOptions()
        parseTags()
        refreshObservedVariables()
        refreshErrors()
        _ = _storyCanContinue()
    }
    
    /// Continues the Ink story.
    ///
    /// Ink stories are progressed on a line by line basis. This makes Ink go to the next line. Together with ``chooseChoiceIndex(_:afterChoiceAction:)`` these methods are the main ways to play an Ink story.
    ///
    /// Please be careful to make sure you only call this function when you can actually continue the story (check ``canContinue`` first).
    ///
    /// - Returns: The next line of text in the Ink story. Same value as ``currentText``
    @discardableResult public func continueStory() -> String {
        _ = jsContext.evaluateScript("story.Continue();")
        refreshState()
        return currentText
    }
    
    /// Returns the current story text (bridging InkJS 'currentText' variable)
    /// # This function has side effects: it sets the 'currentText' variable.
    /*private func _storyCurrentText() -> String {
        let s = jsContext.evaluateScript("story.currentText;")?.toString() ?? ""
        currentText = s
        return s
    }*/
    
    /// Returns whether the story can respond to a 'continue' trigger (bridging InkJS 'canContinue' variable)
    /// # This function has side effects: it sets the 'canContinue' variable
    private func _storyCanContinue() -> Bool {
        let c = jsContext.evaluateScript("story.canContinue;").toBool()
        canContinue = c
        return c
    }
    
    private func refreshOptions() {
        //options.removeAll()
        let textOptions = jsContext.evaluateScript("story.currentChoices;")?.toArray() ?? []
        
        options = textOptions.compactMap { option in
            if let dict = option as? Dictionary<String, Any> {
                if let index = dict["index"] as? NSNumber, let text = dict["text"] as? String {
                    return Option(index: index.intValue, text: text)
                }
            }
            return nil
        }
        
        /*for option in textOptions {
            if let dict = option as? Dictionary<String, Any> {
                if let index = dict["index"] as? NSNumber, let text = dict["text"] as? String {
                    options.append(Option(index: index.intValue, text: text))
                }
            }
        }*/
    }
    
    private func refreshErrors() {
        let errors = jsContext.evaluateScript("story.currentErrors;")?.toArray() ?? []
        currentErrors = errors.compactMap { element in
            element as? String
        }
    }
    
    
    /// Continues the story by making a particular choice.
    ///
    /// Please make sure that there are actual choices to be made before calling this function (i.e. ``options`` is not empty)
    /// Together with ``continueStory()`` these methods are the main way of playing an Ink story.
    ///
    /// - Parameters:
    ///   - index: (retrieve from ``Option/index``)
    ///   - afterChoiceAction: an optional callback to call after the choice is made
    public func chooseChoiceIndex(_ index: Int, afterChoiceAction: (() -> Void)? = nil) {
        jsContext.evaluateScript("story.ChooseChoiceIndex(\(index));")
        //options.removeAll()
        continueStory()
        afterChoiceAction?()
    }
    
    private func clearTags() {
        for element in currentTags {
            if retainTags.contains(element.key) {
                //print("Retaining: \(element)")
            } else {
                currentTags.removeValue(forKey: element.key)
            }
        }
    }
    
    private func parseTags() {
        let gts = jsContext.evaluateScript("story.globalTags;")?.toArray() ?? []
        
        for tag in gts {
            if let tagValue = tag as? String {
                let splits = tagValue.split(separator: ":")
                if splits.count > 1 {
                    globalTags[String(splits[0])] = String(splits[1])
                } else {
                    globalTags[String(splits[0])] = String(splits[0])
                }
            }
        }
        //print("Global tags: \(globalTags)")
        
        clearTags()
        let cts = jsContext.evaluateScript("story.currentTags;")?.toArray() ?? []
        for tag in cts {
            if let tagValue = tag as? String {
                let splits = tagValue.split(separator: ":")
                if splits.count > 1 {
                    currentTags[String(splits[0])] = String(splits[1]).trimmingCharacters(in: .whitespaces)
                } else {
                    currentTags[String(splits[0])] = String(splits[0])
                }
            }
        }
        //print("Current tags: \(currentTags)")
    }
    
    
    /// JSON representation of the Ink stories current state.
    ///
    /// The JSON representation does not contain the actual story, only the information required to reproduce the current stories state when applied to a specific story. This makes the JSON from this method very small (compared to the actual Ink story). But to use this representation, you need to first load the Ink file and then apply this JSON to it using ``loadState(_:)``
    ///
    /// - Returns: a JSON representation of the Ink stories current state.
    public func stateToJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let json = jsContext.evaluateScript("story.state.toJson();")?.toString() ?? ""
        let state = SaveState(jsonState: json, currentTags: currentTags)
        do {
            let data = try encoder.encode(state)
            let string = String(data: data, encoding: .utf8) ?? ""
            print("Succesfully created save state JSON.")
            return string
        } catch {
            print("Error while saving: ", error)
            return ""
        }
    }
    
    /// Sets the Ink story to the state as represented by JSON.
    ///
    /// To use this method, you first need to load an Ink story (using ``loadStory(json:)``). Then you can apply a JSON state using this method.
    ///
    /// - Parameter jsonDataString: JSON representation of the story state (retrieve using ``stateToJSON()``
    public func loadState(_ jsonDataString: String) {
        let jsonData = jsonDataString.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        do {
            let state = try decoder.decode(SaveState.self, from: jsonData)
        
            // Double escape JSON input to pass as a parameter inside evaluateScriptInContext
            var json = state.jsonState
            json = json.replacingOccurrences(of: "\\", with: "\\\\")
            json = json.replacingOccurrences(of: "\"", with: "\\\"")
            json = json.replacingOccurrences(of: "\'", with: "\\\'")
            //json = json.replacingOccurrences(of: "\n", with: "\\n")
            json = json.replacingOccurrences(of: "\n", with: "\\n")
            json = json.replacingOccurrences(of: "\r", with: "\\r")
            //json = json.replacingOccurrences(of: "\f", with: "\\f")
            
            jsContext.evaluateScript("story.state.LoadJson(\"\(json)\");")
            currentTags = state.currentTags
            print("Succesfully restored state from JSON string.")
            continueStory()
        } catch {
            print("Error while loading: ", error)
        }
        
        //print(jsContext.evaluateScript("story.hasError;")?.toBool() ?? false)
        //print(jsContext.evaluateScript("story.currentErrors;")?.toArray() ?? [])
        
    }
    
    
    /// Continues the story from a specific knot and stitch.
    ///
    /// Use this method to override the regular story flow.
    ///
    /// - Parameters:
    ///   - knot: The knot to jump to (required)
    ///   - stitch: (optional) a stitch within the knot to jump to.
    public func moveToKnitStitch(_ knot: String, stitch: String? = nil) {
        var path = knot
        if let s = stitch {
            path += ".\(s)"
        }
                
        print("moveToKnitStitch: path: \(path)")
        
        jsContext.evaluateScript("story.ChoosePathString(\"\(path)\")")
        continueStory()
    }
    
    
    /// Inspect an Ink variables value.
    /// - Parameter variable: the Ink variable to inspect
    /// - Returns: the variables value or `null` if the variable is not known.
    public func getVariable(_ variable: String) -> JSValue {
        return jsContext.evaluateScript("story.variablesState[\"\(variable)\"];")
    }
    
    
    /// Sets an Ink variable to a specific String value 
    /// - Parameters:
    ///   - variable: Ink variable name
    ///   - value: new String value
    public func setVariable(_ variable: String, to value: String) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \"\(value)\";")
        refreshObservedVariables()
    }
    
    /// Sets an Ink variable to a specific Int value
    /// - Parameters:
    ///   - variable: Ink variable name
    ///   - value: new Int value
    public func setVariable(_ variable: String, to value: Int) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \(value);")
        refreshObservedVariables()
    }
    
    /// Sets an Ink variable to a specific Double value
    /// - Parameters:
    ///   - variable: Ink variable name
    ///   - value: new Double value
    public func setVariable(_ variable: String, to value: Double) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \(value);")
        refreshObservedVariables()
    }
    
    
    /// Adds an Ink variable to the list of observed variables.
    ///
    /// ``oberservedVariables`` contains all observed variables.
    ///
    /// - Parameter variableName: the variable to observe.
    public func registerObservedVariable(_ variableName: String) {
        if oberservedVariables.keys.contains(variableName) == false {
            oberservedVariables[variableName] = JSValue(nullIn: jsContext)
        }
    }
    
    /// Removes an Ink variable from the list of observed variables.
    ///
    /// ``oberservedVariables`` contains all observed variables.
    ///
    /// - Parameter variableName: the variable to stop observing.
    public func deregisterObservedVariable(_ variableName: String) {
        if oberservedVariables.keys.contains(variableName) {
            oberservedVariables.removeValue(forKey: variableName)
        }
    }
    
    private func refreshObservedVariables() {
        for key in oberservedVariables.keys {
            oberservedVariables[key] = getVariable(key)
        }
    }
}

/// An `Option` represents a choice in an InkStory, adding an index to the choice.
///
/// Use these in your UI, to signal to Ink which choice a player made using ``InkStory/chooseChoiceIndex(_:afterChoiceAction:)``
///
/// `Options` can only be created from the InkStory and can be retrieved using ``InkStory/options``. Don't create them programatically!
public struct Option {
    /// The designated index for this option.
    public let index: Int
    /// The choices text as returned from the Ink story.
    public let text: String
    
    fileprivate init(index: Int, text: String) {
        self.index = index
        self.text = text
    }
}
