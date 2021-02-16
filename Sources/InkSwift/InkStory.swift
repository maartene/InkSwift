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


public final class InkStory: ObservableObject {
    struct SaveState: Codable {
        let jsonState: String
        let currentTags: [String: String]
    }
    
    var jsContext: JSContext! = JSContext()
    
    // by default, we retain the "IMAGE" tag. This way, an image persists between story parts, until a different image is set.
    // if you don't want this behaviour, set inkStory.retainTags = []
    public var retainTags = ["IMAGE"]
    
    
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
    
    public func loadStory(json: String) {
        
        jsContext.evaluateScript("story = new inkjs.Story(\(json));")
        continueStory()
        
        print("Succesfully loaded InkStory.")
    }
    
    @Published public var currentText: String
    @Published public var canContinue: Bool
    @Published public var options: [Option]
    @Published public var globalTags: [String: String]
    @Published public var currentErrors: [String]
    
    // these need to be persisted
    @Published public var currentTags: [String: String]
    @Published public var oberservedVariables: [String: JSValue]
    
    private func refreshState() {
        currentText = jsContext.evaluateScript("story.currentText;")?.toString() ?? ""
        refreshOptions()
        parseTags()
        refreshObservedVariables()
        refreshErrors()
        _ = _storyCanContinue()
    }
    
    @discardableResult
    public func continueStory() -> String {
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
    
    public func moveToKnitStitch(_ knot: String, stitch: String? = nil) {
        var path = knot
        if let s = stitch {
            path += ".\(s)"
        }
                
        print("moveToKnitStitch: path: \(path)")
        
        jsContext.evaluateScript("story.ChoosePathString(\"\(path)\")")
        continueStory()
    }
    
    public func getVariable(_ variable: String) -> JSValue {
        return jsContext.evaluateScript("story.variablesState[\"\(variable)\"];")
    }
    
    public func setVariable(_ variable: String, to value: String) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \"\(value)\";")
    }
    
    public func setVariable(_ variable: String, to value: Int) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \(value);")
    }
    
    public func setVariable(_ variable: String, to value: Double) {
        jsContext.evaluateScript("story.variablesState[\"\(variable)\"] = \(value);")
    }
    
    public func registerObservedVariable(_ variableName: String) {
        if oberservedVariables.keys.contains(variableName) == false {
            oberservedVariables[variableName] = JSValue(nullIn: jsContext)
        }
    }
    
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

public struct Option {
    public let index: Int
    public let text: String
}
