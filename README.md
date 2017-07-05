# CwlSignal

An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html)

## Adding to your project

This project can be included in your projects in a number of different ways:
   
   * [Manually included framework](#manual-framework-inclusion)
   * [Statically included files](#statically-included-files)
   * [Swift Package Manager](#swift-package-manager)
   * [CocoaPods](#cocoapods)
   * [Carthage](#carthage)

The standard restrictions for each of these approaches apply so you'll need to pick an approach based on your situation and preferences.

Minimum requirements are iOS 8 or macOS 10.10.

## Manual framework inclusion

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlSignal.git`
2. Drag the "CwlSignal.xcodeproj" file from the Finder to somewhere your in own project's file tree in Xcode
3. Drag the "CwlSignal.framework" and CwlUtils.framework" from the "Products" folder of the "CwlSignal" project to the "Copy Files (Frameworks)" build phases of any target that you want to include this module.

That third step is a little tricky if you're unfamiliar with Xcode but it involves:

1. click on your project in the file tree
2. click on the target that you want to include CwlSignal
3. select the "Build Phases" tab
4. if you don't already have a "Copy File" build phase with a "Destination: Frameworks", add one using the "+" button in the top left of the tab (it should appear at the bottom of the list of build phases)
5. drag the CwlSignal.framework and CwlUtils.framework from the "Products" subfolder inside the CwlSignal.xcodeproj in the Xcode file tree onto the "Copy File (Frameworks)" build phase. There will be two frameworks with these names (the macOS and iOS versions). Drag the two which are immediately above the corresponding CwlSignal_macOSTests.xctest or CwlSignal_iOSTests.xctest product.

#### Swift Package Manager related problems and errors

When building using this approach, the "FetchDependencies" target will use the Swift Package Manager to download the "CwlUtils" project from github. The checkout is placed in the "Build intermediates" directory for your project. Normally, you can ignore this detail but you will need network access when building the first time and if you get any errors from the "FetchDependencies" target, you might need to take some appropriate steps.

In particular, when jumping around between Swift versions or checking out different repository versions, you may see:

> swift-package: error: unsatisfiable

or

> !!! swift package show-dependencies failed

as errors in the build log.

In this case, try deleting the "Package.pins" file in the root directory of CwlSignal and trying again. If this doesn't help, try cleaning the build folder. (Hold "Option" key while selecting "Product" &rarr; "Clean Build Folder..." from the Xcode menubar).

If you want to download dependencies manually (instead of using this behind-the-scenes use of the Swift package manager), you should delete the "FetchDependencies" target and replace the "CwlUtils" targets with alternatives that build the dependencies in accordance with your manual download.

## Statically included files

This approach generates three concatenated files (CwlUtils.swift, CwlSignal.swift and CwlSignalExtensions.swift) that can be added to another project – macOS or iOS – with no dynamic frameworks, libraries or other settings required.

1. Get the latest version of CwlSignal by running `git clone https://github.com/mattgallagher/CwlSignal.git` on the command-line.
2. Open the CwlSignal.xcodeproj in Xcode and select the CwlSignalConcat scheme with a destination of "My Mac" (choose from the Scheme popup in the toolbar or from the "Product" &rarr; "Scheme" and "Product" &rarr; "Destination" menus in the menubar.
3. Build the scheme (Command-B or "Product" &rarr; "Build")
4. Open the "Products" folder by right-clicking (or Control-click) on the "Products" folder in the project's file tree in Xcode and select "Show in Finder" and open the "Debug" folder in the "Products" folder that this reveals.

Inside a folder located "Concat_internal" should be three files:

* CwlUtils_internal.swift
* CwlSignal_internal.swift
* CwlSignalExtensions_internal.swift

You can copy these three files and include them in any of your own projects like any other files.

A folder named "Concat_public" should also be present. This version is almost identical to the "Concat_internal" version except that where the "Concat_internal" version strips `public` and `open` specifiers from files, the "Concat_public" version leaves these in-place. This allows the "Concat_public" version to be use in the "Sources" folder of Swift playgrounds or otherwise used where the features need to be exported from a module.

> NOTE: this approach will pull CwlUtils from github using the Swift Package Manager, as with the [Manually included framework](#manual-framework-inclusion) instructions. If you get errors from the FetchDependencies build step, see the note in the [Manually included framework](#manual-framework-inclusion) section on cleaning the build folder and .pins files.

## Swift Package Manager

Add the following to the `dependencies` array in your "Package.swift" file:

    .Package(url: "https://github.com/mattgallagher/CwlSignal.git", majorVersion: 1),

Or, if you're using the `swift-tools-version:4.0` package manager, add the following to the `dependencies` array in your "Package.swift" file:

    .package(url: "https://github.com/mattgallagher/CwlSignal.git", majorVersion: 1)

## CocoaPods

Add the following lines to your target in your "Podfile":

    pod 'CwlSignal', :git => 'https://github.com/mattgallagher/CwlSignal.git'
    pod 'CwlUtils', :git => 'https://github.com/mattgallagher/CwlUtils.git'

## Carthage

Add the following line to your Cartfile:

    git "https://github.com/mattgallagher/CwlSignal.git" "master"
