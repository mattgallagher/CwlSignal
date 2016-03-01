# CwlUtils

A collection of utilities written as part of articles on [Cocoa with Love](http://cocoawithlove.com)

## Related articles

* [Better stack traces in Swift](http://cocoawithlove.com/blog/2016/02/28/stack-traces-in-swift.html)

## Usage

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlUtils.git`
2. Drag the "CwlUtils.xcodeproj" file into your own project's file tree in Xcode
3. Click on your project in the file tree to access project settings and click on the target to which you want to add CwlUtils.
4. Click on the "Build Phases" tab and under "Target Dependencies" click "+" and add the CwlUtils_OSX or CwlUtils_iOS target as appropriate for your target's platform.
5. Still on "Build Phases", if you don't already have a "Copy Files" build phase with a "Destination: Frameworks", add one. In this build phase, add "CwlUtils.framework". NOTE: there will be *two* frameworks in the list with the same name (one is OS X and the other is iOS). The "CwlUtils.framework" will appear above the corresponding CwlUtils OS X or iOS testing target.

Note about step (1): it is not required to create the checkout inside your project's directory but if you check the code out in a shared location and then open it in multiple parent projects simultaneously, Xcode will complain – it's usually easier to create a new copy inside each of your projects.
