require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless app_target

tickemo_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo"
end
raise "Tickemo group not found" unless tickemo_group

support_group = tickemo_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Support"
end
raise "Support group not found" unless support_group

app_sources_phase = app_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

unless support_group.children.any? { |c| c.respond_to?(:path) && c.path == "SafariView.swift" }
  file_ref = support_group.new_reference("SafariView.swift")
  app_sources_phase.add_file_reference(file_ref)
  puts "Registered Support/SafariView.swift"
end

project.save
puts "Saved #{project_path}"
