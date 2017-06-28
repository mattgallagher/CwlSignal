# CwlSignal

An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html)

## Adding to your project

This project can be used by manual inclusion in your projects or through any of the Swift Package Manager, CocoaPods or Carthage.

Minimum requirements are iOS 8 (simulator-only) or macOS 10.9. The project includes tvOS 9 and POSIX targets but these aren't regularly tested.

### Manual inclusion

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlSignal.git`
2. Drag the "CwlSignal.xcodeproj" file from the Finder into your own project's file tree in Xcode
3. Add the "CwlSignal.framework" to the "Copy Files (Frameworks)" build phases of any target that you want to include this module.
4. Drag the "CwlUtils.framework" from the "Dependencies" group (within the CwlSignal project's file tree) onto the same "Copy Files (Frameworks)" build phase (this item may be red but that shouldn't be a problem).

That third step is a little tricky if you're unfamiliar with Xcode but it involves:

a. click on your project in the file tree
b. click on the target to whih you want to add this module
c. select the "Build Phases" tab
d. if you don't already have a "Copy File" build phase with a "Destination: Frameworks", add one using the "+" button in the top left of the tab
e. click the "+" within the "Copy File (Frameworks)" phase and from the list that appears, select the "CwlSignal.framework" (if there are multiple frameworks with the same name, look for the one that appears *above* the corresponding macOS or iOS CwlSignal testing target).

#### Swift Package Manager related problems and errors

When building using this approach, the "FetchDependencies" target will use the Swift Package Manager to download the "CwlUtils" project from github. The checkout is placed in the "Build intermediates" directory for your project. Normally, you can ignore its existence but if you get any errors from the "FetchDependencies" target, you might need to clean the build folder (Hold "Option" key while selecting "Product" &rarr; "Clean Build Folder..." from the Xcode menubar). In some rare cases when switching between Xcode 8 and Xcode 9, you might need to delete the Package.pins file in the CwlSignal directory.

In particular, when jumping around between Swift versions or checking out different repository versions, you may see:

> swift-package: error: unsatisfiable

or

> !!! swift package show-dependencies failed

as errors in the build log. Make certain to clean the build folder and remove the Package.pins file from the CwlSignal directory, as described above.

If you want to download dependencies manually (instead of using this behind-the-scenes use of the Swift package manager), you should delete the "FetchDependencies" target and replace the "CwlUtils" targets with alternatives that build the dependencies in accordance with your manual download.

### Swift Package Manager

Add the following to the `dependencies` array in your "Package.swift" file:

    .Package(url: "https://github.com/mattgallagher/CwlSignal.git", majorVersion: 1),

Or, if you're using the `swift-tools-version:4.0` package manager, add the following to the `dependencies` array in your "Package.swift" file:

    .package(url: "https://github.com/mattgallagher/CwlSignal.git", majorVersion: 1)

### CocoaPods

Add the following lines to your target in your "Podfile":

    pod 'CwlSignal', :git => 'https://github.com/mattgallagher/CwlSignal.git'
    pod 'CwlUtils', :git => 'https://github.com/mattgallagher/CwlUtils.git'

### Carthage

Add the following line to your Cartfile:

    git "https://github.com/mattgallagher/CwlSignal.git" "master"
