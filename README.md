# InkSwift
Swift wrapper for the Ink narrative scripting language. Based on InkJS. Requires JavaScriptCore (so for now no Linux support).

## Supported features
* Loading Ink stories `loadStory(json: String)`;
* Basic flow: continue story `continueStory()` and choices `chooseChoiceIndex(_ index: Int)`;
* Moving to knots/stitches `moveToKnitStitch(_ knot: String, stitch: String? = nil)`;
* Tag support. Read `currentTags` variable;
* Setting and getting variable values (supports strings, 32-bit integers and doubles);
* Loading and saving state `stateToJSON()` and `loadState(_ jsonDataString: String)`;
* Combine integration (subscribe to state changes, observe variables).

## Limitations
* InkSwift uses JavascriptCore. This means that only Apple platforms are supported. I'm working on Linux support using [SwiftJS](https://github.com/SusanDoggie/SwiftJS), but there is a [bug](https://github.com/SusanDoggie/SwiftJS/issues/1) that makes it unusable at this time.

## Getting started
### Regular XCode project
Use 'File' -> 'Swift Packages' -> 'Add Package Dependency...' to add the package to your project.

### Using SwiftPM
Add InkSwift as a dependency to `Package.swift`:
```
let package = Package(
    name: "test_swiftpm",   // choose your own name
    platforms: [
        .macOS(.v10_15),    
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/maartene/InkSwift.git", from: "0.0.2")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "test_swiftpm",
            dependencies: ["InkSwift"]),
        .testTarget(
            name: "test_swiftpmTests",
            dependencies: ["test_swiftpm"]),
    ]
)
```

## Usage
Start by creating a InkStory
```
let story = InkStory()
```

Then load a story from a Ink JSON (you can use [Inklecate](https://github.com/inkle/ink/releases) or [Inky](https://github.com/inkle/inky/releases/tag/0.11.0) to convert an .ink file to a .json file.):
```
let storyJSON = ... //
story.loadStory(json: storyJSON)
```

You can create a very basic command line 'player' using just a few lines of code:

```
// As long as the story can continue (either because there is more text or there are options you can choose)), keep the loop going
while story.canContinue || story.options.count > 0 {
    // Print the current text to the console/terminal
    print(story.currentText)
    
    // If you can continue the story, we wait for input before continuing.
    if story.canContinue {
        print("Press 'enter' to continue")
        _ = readLine()
        story.continueStory()
    }
    // If there are options, show the options and wait for player to choose
    else if story.options.count > 0 {
        // print every option
        for option in story.options {
            print("\(option.index). \(option.text)")
        }
        print("What is your choice?")
        
        // wait for input from player
        if let choice = readLine() {
            // try and convert input to an index.
            if let index = Int(String(choice.first ?? "a")) {
                // choose the selected option index
                story.chooseChoiceIndex(index)
            }
        }
    }
}
// no more content, story is done.
print("Story done!")
```

## Using Combine/SwiftUI
InkStory conforms to the `ObservableObject` protocol. This makes using it in Combine possible and SwiftUI very easy. A simple example SwiftUI view that can play an Ink story would contain:

### Import the SwiftInk package
Add 
```
import SwiftInk
``` 

to ContentView.swift

### The ink story as a @StateObject
Add the following property to your ContentView:
    `@StateObject var story = InkStory()`

### Add a function that loads the Ink story:
Note: change the filename to load to your own JSON file. Don't forget to add it to the project.

``` 
func loadStory() {
guard let url = Bundle.main.url(forResource: "test.ink", withExtension: "json") else {
    fatalError("Could not find ink story file.")
}

guard let storyJSON = try? String(contentsOf: url) else {
    fatalError("Could not load story file.")
}

story.loadStory(json: storyJSON)
}
```

### Create the body property
```
var body: some View {
    VStack {
        Text(story.currentText)
        if story.canContinue {
            Button("Continue") {
                story.continueStory()
            }
        }
        ForEach(story.options, id: \.index) { option in
            Button(option.text) {
                story.chooseChoiceIndex(option.index)
            }
        }
    }.padding()
    .onAppear {
        loadStory()
    }
}
```

## Licenced content
* The Ink runtime uses the official Ink Javascript port [InkJS](https://github.com/y-lohse/inkjs)
