Pod::Spec.new do |s|
  s.name             = 'movement_vision'
  s.version          = '0.0.1'
  s.summary          = 'On-device pose capture boundary. Live capture is unavailable.'
  s.description      = <<-DESC
On-device pose capture boundary. Live capture is unavailable.
                       DESC
  s.homepage         = 'https://github.com/Ryan-AI-Studios/HelpMeMove'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'HelpMeMove' => 'dev@helpmemove.app' }
  s.source           = { :path => '.' }
  s.source_files = 'movement_vision/Sources/movement_vision/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
