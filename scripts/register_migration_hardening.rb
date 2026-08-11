require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless app_target

test_target = project.targets.find { |t| t.name == "TickemoTests" }
raise "TickemoTests target not found" unless test_target

app_sources = app_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
test_sources = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

tickemo_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo"
end
raise "Tickemo group not found" unless tickemo_group

tests_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "TickemoTests"
end
raise "TickemoTests group not found" unless tests_group

def find_or_create_group(parent, display_name, path)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == display_name } ||
    parent.new_group(display_name, path)
end

def register(group, sources_phase, names)
  names.each do |name|
    if group.children.any? { |c| c.respond_to?(:path) && c.path == name }
      puts "Already registered: #{name}"
      next
    end
    file_ref = group.new_reference(name)
    sources_phase.add_file_reference(file_ref)
    puts "Registered #{name}"
  end
end

# Tickemo/Migration — claim gate, stable ids, backup, sweeper, coordinator.
migration_group = find_or_create_group(tickemo_group, "Migration", "Tickemo/Migration")
register(migration_group, app_sources, %w[
  LegacyMigrationClaim.swift
  StableLegacyID.swift
  LegacyDataBackup.swift
  DuplicateRecordSweeper.swift
  MigrationCoordinator.swift
])

# Tickemo/Components — the first-launch migration cover.
components_group = find_or_create_group(tickemo_group, "Components", "Tickemo/Components")
register(components_group, app_sources, %w[MigrationOverlayView.swift])

register(tests_group, test_sources, %w[
  LegacyMigrationClaimTests.swift
  StableLegacyIDTests.swift
  DataMigrationImporterTests.swift
  DuplicateRecordSweeperTests.swift
])

project.save
puts "Saved #{project_path}"
