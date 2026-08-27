#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates SmartSwapsNative/SmartSwaps.xcodeproj from the SmartSwaps/ app
# target sources plus a local package dependency on SmartSwapsKit (this
# directory's own Package.swift).
#
# Written against the `xcodeproj` gem (`gem install xcodeproj`) because no
# Xcode/xcodegen is available in the container this port has been done in so
# far — see PORTING_NOTES.md. Re-run this after adding/removing app-target
# source files; it does not need Xcode to run, only to open the result.
#
# Usage: ruby Tools/generate-xcodeproj.rb   (from SmartSwapsNative/)

require 'xcodeproj'
require 'pathname'

ROOT = Pathname.new(__dir__).parent
APP_DIR = ROOT + 'SmartSwaps'
PROJECT_PATH = ROOT + 'SmartSwaps.xcodeproj'
BUNDLE_ID = 'com.anonymous.smartswapsmobile'
DEPLOYMENT_TARGET = '16.4'

project = Xcodeproj::Project.new(PROJECT_PATH)

app_group = project.new_group('SmartSwaps', 'SmartSwaps')
%w[App DesignSystem Screens State Components Services].each do |subdir|
  sub_group = app_group.new_group(subdir, subdir)
  Dir.glob(APP_DIR + subdir + '*.swift').sort.each do |file|
    sub_group.new_file(Pathname.new(file).relative_path_from(APP_DIR + subdir).to_s)
  end
end
resources_group = app_group.new_group('Resources', 'Resources')
info_plist_ref = resources_group.new_file('Info.plist')

target = project.new_target(:application, 'SmartSwaps', :ios, DEPLOYMENT_TARGET)

app_group.recursive_children.each do |ref|
  next unless ref.is_a?(Xcodeproj::Project::Object::PBXFileReference)
  next unless ref.path.to_s.end_with?('.swift')

  target.add_file_references([ref])
end

# Local SPM package dependency: SmartSwapsKit lives one level up (this
# directory's own Package.swift), matching Package.swift's own comment that
# the app target depends on it as a package rather than embedding its sources.
package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = '..'
project.root_object.package_references << package_ref

product_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product_dependency.package = package_ref
product_dependency.product_name = 'SmartSwapsKit'
target.package_product_dependencies << product_dependency

frameworks_phase = target.frameworks_build_phase
build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = product_dependency
frameworks_phase.files << build_file

target.build_configurations.each do |config|
  config.build_settings['INFOPLIST_FILE'] = 'SmartSwaps/Resources/Info.plist'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['SWIFT_VERSION'] = '5.9'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2' # iPhone + iPad (app.json: supportsTablet)
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['ENABLE_PREVIEWS'] = 'YES'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = nil
end

project.save

puts "Wrote #{PROJECT_PATH}"
