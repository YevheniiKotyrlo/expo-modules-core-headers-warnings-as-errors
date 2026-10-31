Pod::Spec.new do |s|
  s.name           = 'StrictProbe'
  s.version        = '1.0.0'
  s.summary        = 'A local Expo module whose Swift builds with warnings as errors'
  s.license        = 'MIT'
  s.author         = 'Yevhenii Kotyrlo'
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = { :ios => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_TREAT_WARNINGS_AS_ERRORS' => 'YES',
  }

  s.source_files = '**/*.swift'
end
