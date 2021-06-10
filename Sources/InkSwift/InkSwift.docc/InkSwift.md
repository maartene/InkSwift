#  ``InkSwift``
Swift wrapper for the Ink narrative scripting language. Based on InkJS. Requires JavaScriptCore (so for now no Linux support).

Use the ``InkStory`` class to run your Ink stories.

### Supported features
- Loading Ink stories `loadStory(json: String)`;
- Basic flow: continue story `continueStory()` and choices `chooseChoiceIndex(_ index: Int)`;
- Moving to knots/stitches `moveToKnitStitch(_ knot: String, stitch: String? = nil)`;
- Tag support. Read `currentTags` variable;
- Setting and getting variable values (supports strings, 32-bit integers and doubles);
- Loading and saving state `stateToJSON()` and `loadState(_ jsonDataString: String)`;
- Combine integration (subscribe to state changes, observe variables).

### Limitations
* InkSwift uses JavascriptCore. This means that only Apple platforms are supported. I'm working on Linux support using [SwiftJS](https://github.com/SusanDoggie/SwiftJS), but there is a [bug](https://github.com/SusanDoggie/SwiftJS/issues/1) that makes it unusable at this time.

### Licenced content
* The Ink runtime uses the official Ink Javascript port [InkJS](https://github.com/y-lohse/inkjs)
