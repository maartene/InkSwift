#  ``InkSwift``
Swift wrapper for the Ink narrative scripting language. Based on InkJS. 

Use the ``InkStory`` class to run your Ink stories.

### Supported features
- Apple and Linux platforms (using [JXKit](https://github.com/jectivex/JXKit))
- Loading (compiled) Ink stories `loadStory(json: String)` as well as Ink directly `loadStory(ink: String)`;
- Basic flow: continue story `continueStory()` and choices `chooseChoiceIndex(_ index: Int)`;
- Moving to knots/stitches `moveToKnitStitch(_ knot: String, stitch: String? = nil)`;
- Tag support. Read `currentTags` variable;
- Setting and getting variable values (supports strings, 32-bit integers and doubles);
- Loading and saving state `stateToJSON()` and `loadState(_ jsonDataString: String)`;
- On Apple platforms: Combine integration (subscribe to state changes, observe variables).

### Limitations
* None that I'm aware off.

### Licenced content
* The Ink runtime uses the official Ink Javascript port [InkJS](https://github.com/y-lohse/inkjs)
* Cross-platform JavaScript runtime [JXKit](https://github.com/jectivex/JXKit)