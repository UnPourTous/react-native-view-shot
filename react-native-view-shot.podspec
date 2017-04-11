require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name     = "react-native-view-shot"
  s.version  = package['version']
  s.summary  = package['description']
  s.homepage = "https://github.com/gre/react-native-view-shot"
  s.license  = package['license']
  s.author   = package['author']
  s.source   = { :git => "https://github.com/gre/react-native-view-shot.git", :tag => "v#{s.version}" }

  s.platform = :ios, "8.0"

  s.preserve_paths = 'README.md', 'LICENSE', 'package.json', 'index.js'
  s.source_files   = "ios/*.{h,m}"

  s.dependency 'React'
end
