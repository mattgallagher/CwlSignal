# CwlUtils

A collection of utilities written as part of articles on [Cocoa with Love](https://cocoawithlove.com)

## Related articles

* [Better stack traces in Swift](https://cocoawithlove.com/blog/2016/02/28/stack-traces-in-swift.html)
* [Gathering system information in Swift with sysctl](https://www.cocoawithlove.com/blog/2016/03/08/swift-wrapper-for-sysctl.html)
* [Presenting unanticipated errors to users](https://www.cocoawithlove.com/blog/2016/04/14/error-recovery-attempter.html)
* [Swift name demangling: C++ vs Swift for parsing](https://www.cocoawithlove.com/blog/2016/05/01/swift-name-demangling.html)
* [Random number generators in Swift](https://www.cocoawithlove.com/blog/2016/05/19/random-numbers.html)
* [Mutexes and closure capture in Swift](https://www.cocoawithlove.com/blog/2016/06/02/threads-and-mutexes.html)
* [Design patterns for safe timer usage](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html)
* [Values and errors, part 1: 'Result' in Swift](https://www.cocoawithlove.com/blog/2016/08/21/result-types-part-one.html)
* [Optimizing a copy-on-write double-ended queue in Swift](https://www.cocoawithlove.com/blog/2016/09/22/deque.html)
* [Specifying function execution contexts](https://www.cocoawithlove.com/blog/specifying-execution-contexts.html)
* [Specifying function execution contexts](https://www.cocoawithlove.com/blog/specifying-execution-contexts.html)
* [Testing actions over time](https://www.cocoawithlove.com/blog/testing-actions-over-time.html)

## Usage

1. In a subdirectory of your project's directory, run `git clone https://github.com/mattgallagher/CwlUtils.git`
2. Drag the "CwlUtils.xcodeproj" file from the Finder into your own project's file tree in Xcode
3. Click on your project in the file tree to access project settings and click on the target to which you want to add CwlUtils.
4. Click on the "Build Phases" tab and if you don't already have a "Copy Files" build phase with a "Destination: Frameworks", add one using the "+" in the top left of the tab.
5. Still on the "Build Phases" tab, add "CwlUtils.framework" to the "Copy Files, Destination: Frameworks" step. NOTE: there may be multiple "CwlUtils.framework" files in the list, including one for macOS and one for iOS. You should select the "CwlUtils.framework" that appears *above* the corresponding CwlUtils macOS or iOS testing target.
6. *Optional step*: Adding the "CwlUtils.xcodeproj" file to your project's file tree will also add all of its schemes to your scheme list in Xcode. You can hide these from your scheme list from the menubar by selecting "Product" -> "Scheme" -> "Manage Schemes" (or typing Command-Shift-,) and unselecting the checkboxes in the "Show" column next to the CwlUtils scheme names.
7. In Swift files where you want to use CwlUtils code, write `import CwlUtils` at the top.

Note about step (1): it is not required to create the checkout inside your project's directory but if you check the code out in a shared location and then open it in multiple parent projects simultaneously, Xcode will complain – it's usually easier to create a new copy inside each of your projects.
