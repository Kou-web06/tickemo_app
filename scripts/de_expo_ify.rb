require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless target

# 1. Remove RN/CocoaPods/Expo shell script build phases (keep Sources/Frameworks/
#    Resources/Embed Foundation Extensions, which the widget embed relies on).
phases_to_remove = [
  "[CP] Check Pods Manifest.lock",
  "[Expo] Configure project",
  "Bundle React Native code and images",
  "[CP] Copy Pods Resources",
  "[CP] Embed Pods Frameworks",
]
phases_to_remove.each do |name|
  phase = target.build_phases.find { |bp| bp.respond_to?(:name) && bp.name == name }
  next unless phase
  target.build_phases.delete(phase)
  phase.remove_from_project
  puts "Removed build phase: #{name}"
end

# 2. Detach Pods xcconfigs from both build configurations, then remove the
#    now-orphaned file references and the Pods group.
target.build_configurations.each do |config|
  if config.base_configuration_reference
    puts "Detaching base config for #{config.name}: #{config.base_configuration_reference.display_name}"
    config.base_configuration_reference = nil
  end
end
pods_group = project.main_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Pods" }
if pods_group
  pods_group.children.dup.each(&:remove_from_project)
  pods_group.remove_from_project
  puts "Removed Pods group and xcconfig references"
end

# 3. Remove Pods_Tickemo.framework from the Frameworks build phase and its
#    file reference.
frameworks_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXFrameworksBuildPhase) }
pods_framework_build_file = frameworks_phase.files.find { |f| f.display_name == "Pods_Tickemo.framework" }
if pods_framework_build_file
  file_ref = pods_framework_build_file.file_ref
  frameworks_phase.remove_file_reference(file_ref) if frameworks_phase.respond_to?(:remove_file_reference)
  pods_framework_build_file.remove_from_project
  file_ref&.remove_from_project
  puts "Removed Pods_Tickemo.framework"
end

# 4. Remove ExpoModulesProvider.swift (generated file that lived under Pods/)
#    from Sources and the now-empty ExpoModulesProviders group.
sources_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
expo_provider_build_file = sources_phase.files.find { |f| f.display_name == "ExpoModulesProvider.swift" }
if expo_provider_build_file
  file_ref = expo_provider_build_file.file_ref
  expo_provider_build_file.remove_from_project
  file_ref&.remove_from_project
  puts "Removed ExpoModulesProvider.swift"
end
top_level_provider_group = project.main_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "ExpoModulesProviders" }
top_level_provider_group&.remove_from_project
puts "Removed ExpoModulesProviders group" if top_level_provider_group

# 5. Remove Expo.plist (source file already deleted on disk) from Resources
#    and the now-empty Supporting group.
resources_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
expo_plist_build_file = resources_phase.files.find { |f| f.display_name == "Expo.plist" }
if expo_plist_build_file
  file_ref = expo_plist_build_file.file_ref
  expo_plist_build_file.remove_from_project
  file_ref&.remove_from_project
  puts "Removed Expo.plist"
end
tickemo_group = project.main_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo" }
supporting_group = tickemo_group&.children&.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Supporting" }
supporting_group&.remove_from_project
puts "Removed Supporting group" if supporting_group

# 6. Remove the bridging header file reference and build setting (no RN
#    Obj-C classes left to bridge).
bridging_header_ref = tickemo_group&.children&.find { |c| c.respond_to?(:path) && c.path.to_s.end_with?("Tickemo-Bridging-Header.h") }
bridging_header_ref&.remove_from_project
puts "Removed Tickemo-Bridging-Header.h reference" if bridging_header_ref
target.build_configurations.each do |config|
  config.build_settings.delete("SWIFT_OBJC_BRIDGING_HEADER")
end

project.save
puts "Saved #{project_path}"
