# InkSwift
Swift wrapper for the Ink narrative scripting language. Based on InkJS. Requires JavaScriptCore (so no Linux support).

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


### Using SwiftPM
Add InkSwift as a dependency to `Package.swift`:




## Usage
Start by creating a InkStory
```
let story = InkStory()
```

Then load a story from a Ink JSON (you can use Inklecate or Inky to convert an .Ink file to a .json file.):
let storyJSON = ... //
story.loadStory(json: storyJSON)

A very cool





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
