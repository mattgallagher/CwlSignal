# CwlSignal

An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html)

## Usage

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlSignal.git`
2. Drag the "CwlSignal.xcodeproj" file from the Finder into your own project's file tree in Xcode
3. Click on your project in the file tree to access project settings and click on the target to which you want to add CwlSignal.
5. Click on the "Build Phases" tab
6. Add a "Target dependency" for CwlSignal_iOS or CwlSignal_macOS (depending on whether your target builds for iOS or Mac)
7. If you don't already have a "Copy Files" build phase with a "Destination: Frameworks", add one using the "+" in the top left of the tab.
8. Add the "CwlSignal.framework" to the "Copy Files, Destination: Frameworks" step. NOTE: there may be multiple "CwlSignal.framework" files in the list, including one for macOS and one for iOS. You should select the "CwlSignal.framework" that appears *above* the corresponding CwlSignal macOS or iOS testing target.
9. In Swift files where you want to use CwlSignal code, write `import CwlSignal` at the top.

Note about step (1): it is not required to create the checkout inside your project's directory but if you check the code out in a shared location and then open it in multiple parent projects simultaneously, Xcode will complain – it's usually easier to create a new copy inside each of your projects.

Note about step (2): Adding the "CwlSignal.xcodeproj" file to your project's file tree will also add all of its schemes to your scheme list in Xcode. You can hide these from your scheme list from the menubar by selecting "Product" -> "Scheme" -> "Manage Schemes" (or typing Command-Shift-,) and unselecting the checkboxes in the "Show" column next to the CwlSignal scheme names.
