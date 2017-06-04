Pod::Spec.new do |s|
  s.name          = "CwlSignal"
  s.version       = "1.0.0"
  s.summary       = "A Swift framework for reactive programming."
  s.description   = <<-DESC
    An implementation of reactive programming. For details, see the article on Cocoa with An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://cocoawithlove.com), [CwlSignal, a library for reactive programming](https://cocoawithlove.com/blog/cwlsignal.html)
  DESC
  s.homepage      = "https://github.com/mattgallagher/CwlSignal"
  s.license       = { :type => "ISC", :file => "LICENSE.txt" }
  s.author        = "Matt Gallagher"
  s.ios.deployment_target = "9.0"
  s.osx.deployment_target = "10.12"
  s.source        = { :git => "https://github.com/xjki/CwlSignal.git", :tag => "#{s.version}" }
  s.source_files  = "Sources/CwlSignal/*.{swift,h}"
end
