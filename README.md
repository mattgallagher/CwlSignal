# CwlSignal

An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html)

## Usage

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlSignal.git`
2. Drag the "CwlSignal.xcodeproj" file from the Finder into your own project's file tree in Xcode
3. Click on your project in the file tree to access project settings and click on the target to which you want to add CwlSignal.
4. Click on the "Build Phases" tab
5. If you don't already have a "Copy Files" build phase with a "Destination: Frameworks", add one using the "+" in the top left of the tab.
6. Click the "+" button within the "Copy Files, Destination: Frameworks" build phase and add the "CwlSignal.framework". NOTE: there may be multiple "CwlSignal.framework" files in the list, including one for macOS and one for iOS. You should select the "CwlSignal.framework" that appears *above* the corresponding CwlSignal macOS or iOS testing target.
7. You'll also need to add the "CwlUtils.framework" to the "Copy Files, Destination: Frameworks" build phase. It won't intially appear if you hit the "+" button on the build phase. Instead, expand the CwlSignal.xcodeproj -> Dependencies folder in the project file tree and drag the "CwlUtils.framework" that you find there onto the "Copy Files, Destination: Frameworks" build phase (the name will likely be red – that's not a problem).

In Swift files where you want to use CwlSignal code, write `import CwlSignal` at the top.

Note about step (1): it is not required to create the checkout inside your project's directory but if you check the code out in a shared location and then open it in multiple parent projects simultaneously, Xcode will complain – it's usually easier to create a new copy inside each of your projects.

Note about step (2): Adding the "CwlSignal.xcodeproj" file to your project's file tree will also add all of its schemes to your scheme list in Xcode. You can hide these from your scheme list from the menubar by selecting "Product" -> "Scheme" -> "Manage Schemes" (or typing Command-Shift-,) and unselecting the checkboxes in the "Show" column next to the CwlSignal scheme names.

## Additional steps for the latest CwlSignal 2.0.0-beta builds on master

If you've used a previous build of CwlSignal and you're now seeing a runtime error "Library not loaded: @rpath/CwlUtils.framework/CwlUtils", then please read this.

The latest master versions (including builds tagged 2.0.0-beta.1 and 2.0.0-beta.2) no longer copy the CwlUtils.framework inside the CwlSignal.framework. This avoids duplicate inclusion of the framework and other potential problems but it means that you need to copy CwlUtils.framework into your build as part of your Copy Files (Frameworks) build phase (in the same way that you're already copying the CwlSignal.framework).

To copy the CwlUtils.framework, expand the CwlSignal.xcodeproj -> Dependencies folder. You should see three frameworks there. They may be red (depending on whether you've build the Mac debug build) but that doesn't matter. Drag the CwlUtils.framework onto the Copy Files (Frameworks) build phase where you've already got CwlSignal.framework. You don't need the other two frameworks (they're used by the CwlSignal testing target, not the main build).
