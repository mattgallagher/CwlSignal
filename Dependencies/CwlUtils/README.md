# CwlUtils

A collection of utilities written as part of articles on [Cocoa with Love](https://www.cocoawithlove.com)

## Included functionality

The following features are included in the library.

* [CwlStackFrame.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlStackFrame.swift) from [Better stack traces in Swift](https://cocoawithlove.com/blog/2016/02/28/stack-traces-in-swift.html)
* [CwlSysctl.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlSysctl.swift) from [Gathering system information in Swift with sysctl](https://www.cocoawithlove.com/blog/2016/03/08/swift-wrapper-for-sysctl.html)
* [CwlUnanticipatedError.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlUnanticipatedError.swift) from [Presenting unanticipated errors to users](https://www.cocoawithlove.com/blog/2016/04/14/error-recovery-attempter.html)
* [CwlScalarScanner.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlScalarScanner.swift) from [Swift name demangling: C++ vs Swift for parsing](https://www.cocoawithlove.com/blog/2016/05/01/swift-name-demangling.html)
* [CwlRandom.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlRandom.swift) from [Random number generators in Swift](https://www.cocoawithlove.com/blog/2016/05/19/random-numbers.html)
* [CwlMutex.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlMutex.swift) from [Mutexes and closure capture in Swift](https://www.cocoawithlove.com/blog/2016/06/02/threads-and-mutexes.html)
* [CwlDispatch.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDispatch.swift) from [Design patterns for safe timer usage](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html)
* [CwlResult.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlResult.swift) from [Values and errors, part 1: 'Result' in Swift](https://www.cocoawithlove.com/blog/2016/08/21/result-types-part-one.html)
* [CwlDeque.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDeque.swift) from [Optimizing a copy-on-write double-ended queue in Swift](https://www.cocoawithlove.com/blog/2016/09/22/deque.html)
* [CwlExec.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlExec.swift) from [Specifying function execution contexts](https://www.cocoawithlove.com/blog/specifying-execution-contexts.html)
* [CwlDebugContext.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDebugContext.swift) from [Testing actions over time](https://www.cocoawithlove.com/blog/testing-actions-over-time.html)

## Adding to your project

This project can be included in your projects in a number of different ways:
   
   * [Manually included framework](#manual-framework-inclusion)
   * [Statically included files](#statically-included-files)
   * [Swift Package Manager](#swift-package-manager)
   * [CocoaPods](#cocoapods)
   * [Carthage](#carthage)

The standard restrictions for each of these approaches apply so you'll need to pick an approach based on your situation and preferences.

Minimum requirements are iOS 8 or macOS 10.10.

## Manual inclusion

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlUtils.git`
2. Drag the "CwlUtils.xcodeproj" file from the Finder to somewhere your in own project's file tree in Xcode
3. Drag the "CwlUtils.framework" from the "Products" folder of the "CwlUtils" project to the "Copy Files (Frameworks)" build phases of any target that you want to include this module.

## Statically included files

This approach generates a concatenated files named CwlUtils.swift that can simply be added to another project (no dynamic frameworks, libraries or other settings required).

> This approach will omit the CwlStackFrame.swift, CwlAddressInfo.swift, CwlUnanticipatedError.swift and CwlFrameAddress.c files (since they cannot be included via a single-file approach). If you need these files, please use one of the other inclusion strategies.

1. Get the latest version of CwlUtils by running `git clone https://github.com/mattgallagher/CwlUtils.git` on the command-line.
2. Open the CwlUtils.xcodeproj in Xcode and select the CwlCwlUtilsConcat scheme with a destination of "My Mac" (choose from the Scheme popup in the toolbar or from the "Product" &rarr; "Scheme" and "Product" &rarr; "Destination" menus in the menubar.
3. Build the scheme (Command-B or "Product" &rarr; "Build")
4. Open the "Products" folder by right-clicking (or Control-click) on the "Products" folder in the project's file tree in Xcode and select "Show in Finder" and open the "Debug" folder in the "Products" folder that this reveals.

Inside a folder located "Concat_internal" should the file "CwlUtils_internal.swift". You can copy this file and include it in any of your own projects, like any other file.

A folder named "Concat_public" should also be present. This version is almost identical to the "Concat_internal" version except that where the "Concat_internal" version strips `public` and `open` specifiers, the "Concat_public" version leaves these in-place. This allows the "Concat_public" version to be use in the "Sources" folder of Swift playgrounds or otherwise used where the features need to be exported from a module.

## Swift Package Manager

Add the following to the `dependencies` array in your "Package.swift" file:

    .Package(url: "https://github.com/mattgallagher/CwlUtils.git", majorVersion: 1),

Or, if you're using the `swift-tools-version:4.0` package manager, add the following to the `dependencies` array in your "Package.swift" file:

    .package(url: "https://github.com/mattgallagher/CwlUtils.git", majorVersion: 1)

> NOTE: even though this git repository includes its dependencies in the Dependencies folder, building via the Swift Package manager fetches and builds these dependencies independently.

## CocoaPods

Add the following to your target in your "Podfile":

    pod 'CwlUtils', :git => 'https://github.com/mattgallagher/CwlUtils.git'

## Carthage

Add the following line to your Cartfile:

    git "https://github.com/mattgallagher/CwlUtils.git" "master"
