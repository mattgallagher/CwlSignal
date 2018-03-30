// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])],
	dependencies: [.package(url: "https://github.com/mattgallagher/CwlUtils.git", .revision("e88c7369f10447dcf5f697d29b3c54176ca42a49"))],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		)
	]
)
