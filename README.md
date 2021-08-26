# CwlSignal

An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html).

## Adding to your project

The CwlSignal library requires the [Swift Package Manager](#swift-package-manager). Minimum requirements are iOS 8 or macOS 10.10 and Swift 5.0.

Add the following to the `dependencies` array in your "Package.swift" file:

    .package(url: "https://github.com/mattgallagher/CwlSignal.git", from: Version(3, 0, 0)),

> NOTE: even though this git repository includes its dependencies in the Dependencies folder, building via the Swift Package manager fetches and builds these dependencies independently.

## CocoaPods and Carthage

Up to version 2.2.0, this library supported CocoaPods and Carthage. If you wish to use these package managers, you can check out the [CwlSignal 2.2.0 tag](https://github.com/mattgallagher/CwlSignal/releases/tag/2.2.0).
