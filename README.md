![Swift 5.6](https://img.shields.io/badge/swift-5.6-orange.svg)
# InkSwift

Swift support for the [Ink](https://www.inklestudios.com/ink/) narrative scripting language.

## Which runtime should I use?

**For new projects we recommend `SwiftInkRuntime` — the native runtime.** It is pure
Swift with its own native Ink compiler, needs **no JavaScriptCore or JXKit**, executes
[The Intercept](https://github.com/inkle/the-intercept) fully, and runs on both Apple
platforms and Linux.

The original `InkStory` runtime (the JavaScriptCore/inkjs **JS-bridge**) is now the
**legacy** path. It remains fully functional and is scheduled for removal in **v3.0.0**.
See the [migration guide](docs/how-to/migrate-from-js-bridge.md) to move an existing
`InkStory`-based app to the native runtime.

### Known gaps vs the JS-bridge

The native runtime does not yet cover every JS-bridge capability, so this is not a claim
of complete parity. Known gaps include `LIST`, `RANDOM` / `SEED_RANDOM`, threads,
`EXTERNAL` functions, shuffle variable-text (`{~a|b}`), and Combine-based variable
observation. If your story needs one of these, stay on the JS-bridge for now. The
complete, maintained list is the
[supported-parity / known-gaps statement](docs/reference/js-bridge-vs-native-parity.md).

---

## Legacy: the JavaScriptCore JS-bridge (`InkStory`)

> The sections below document the **legacy** `InkStory` JS-bridge. It is deprecated and
> will be removed in **v3.0.0**. New projects should use `SwiftInkRuntime` (see above);
> existing projects should follow the
> [migration guide](docs/how-to/migrate-from-js-bridge.md).

### Supported features

- Apple and Linux platforms (using [JXKit](https://github.com/jectivex/JXKit)). If you want to use the JavaScriptCore version (Apple platforms only), use release 0.0.4.
- Loading compiled Ink stories `loadStory(json: String)` as well as Ink directly `loadStory(ink: String)`;
- Basic flow: continue story `continueStory()` and choices `chooseChoiceIndex(_ index: Int)`;
- Moving to knots/stitches `moveToKnitStitch(_ knot: String, stitch: String? = nil)`;
- Tag support. Read `currentTags` variable;
- Setting and getting variable values (supports strings, 32-bit integers and doubles);
- Loading and saving state `stateToJSON()` and `loadState(_ jsonDataString: String)`;
- On Apple platforms: Combine integration (subscribe to state changes, observe variables).

### Linux installations

JXKit on Linux requires JavaScriptCore libraries, that are part of WebKit. For Ubuntu 20.04 and newer:
`sudo apt install libwebkit2gtk-4.0-dev`

## Limitations

- When using the built in Ink compiler, don't use JavaScript tokens that can confuse string definitions, like \`.

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
        .package(url: "https://github.com/maartene/InkSwift.git", from: "2.0.0")
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

Alternatively, you can load a story from Ink directly. Not however, that this might hinder performance for users.

```
story.loadStory(ink: "Hello, World!")

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

### Import the InkSwift package

Add

```
import InkSwift
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

## Contributors
- [Griff](https://github.com/techpink) added support for choice tags.

## Licenced content

- The Ink runtime uses the official Ink Javascript port [InkJS](https://github.com/y-lohse/inkjs)
- The Compiler tests use [The Intercept](https://github.com/inkle/the-intercept) as an example story to compile
- Uses [JSONEquality](https://github.com/neallester/JSONEquality.git) in some of the tests
- Cross-platform JavaScript runtime [JXKit](https://github.com/jectivex/JXKit)
