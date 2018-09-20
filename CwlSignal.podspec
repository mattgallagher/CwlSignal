Pod::Spec.new do |s|
  s.name          = "CwlSignal"
  s.version       = "2.0.0"
  
  s.summary       = "A Swift framework for reactive programming."
  s.description   = <<-DESC
    An implementation of reactive programming. For details, see the article on Cocoa with An implementation of reactive programming. For details, see the article on [Cocoa with Love](https://www.cocoawithlove.com), [CwlSignal, a library for reactive programming](https://www.cocoawithlove.com/blog/cwlsignal.html)
  DESC
  
  s.homepage      = "https://github.com/mattgallagher/CwlSignal"
  s.license       = { :type => "ISC", :file => "LICENSE.txt" }
  s.author        = "Matt Gallagher"
  
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"
  
  s.dependency 'CwlUtils'
  
  s.source        = { :git => "https://github.com/mattgallagher/CwlSignal.git", :branch => "xcode10" }
  s.source_files  = "Sources/**/*.{swift,h}"
end
