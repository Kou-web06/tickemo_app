require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless target

tickemo_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo"
end
raise "Tickemo group not found" unless tickemo_group

sources_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

# The Tickemo PBXGroup has no `path` of its own (source_tree "<group>" with
# nil path); its children's `path` attributes are given relative to the
# project root, e.g. "Tickemo/AppDelegate.swift" — not "AppDelegate.swift".
# New references must follow the same convention.

# ContentView.swift goes directly in the Tickemo group.
content_view_path = "Tickemo/ContentView.swift"
unless tickemo_group.children.any? { |c| c.respond_to?(:path) && c.path == content_view_path }
  file_ref = tickemo_group.new_reference(content_view_path)
  sources_phase.add_file_reference(file_ref)
  puts "Registered #{content_view_path}"
end

# Services/*.swift go in a new Services subgroup whose own path resolves to
# Tickemo/Services, so its children can use bare filenames.
services_group = tickemo_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Services"
end
services_group ||= tickemo_group.new_group("Services", "Tickemo/Services")

%w[MusicKitService.swift AppleMusicService.swift WidgetReloaderService.swift].each do |name|
  next if services_group.children.any? { |c| c.respond_to?(:path) && c.path == name }
  file_ref = services_group.new_reference(name)
  sources_phase.add_file_reference(file_ref)
  puts "Registered Services/#{name}"
end

project.save
puts "Saved #{project_path}"
