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

def find_or_create_group(parent, display_name, path)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == display_name } ||
    parent.new_group(display_name, path)
end

# Tickemo/Persistence — Core Data model + PersistenceController + transformer.
persistence_group = find_or_create_group(tickemo_group, "Persistence", "Tickemo/Persistence")

model_path = "Tickemo.xcdatamodeld"
unless persistence_group.children.any? { |c| c.respond_to?(:path) && c.path == model_path }
  model_ref = persistence_group.new_reference(model_path)
  # Must go in Sources, not Resources: Xcode's DataModelCodegen step routes
  # its generated NSManagedObject subclasses to whichever build phase the
  # .xcdatamodeld is a member of. Putting it in Resources produced
  # "cannot be processed by a Copy Bundle Resources build phase" warnings
  # and left CD_* types unresolved everywhere else in the target (verified
  # empirically). The compiled .momd still gets embedded in the app bundle
  # regardless of phase membership, so Sources-only is sufficient. Adding it
  # to both phases causes an "Unexpected duplicate tasks" build error.
  sources_phase.add_file_reference(model_ref)
  puts "Registered #{model_path} (#{model_ref.class}) in Sources phase"
end

%w[PersistenceController.swift StringArrayTransformer.swift].each do |name|
  next if persistence_group.children.any? { |c| c.respond_to?(:path) && c.path == name }
  file_ref = persistence_group.new_reference(name)
  sources_phase.add_file_reference(file_ref)
  puts "Registered Persistence/#{name}"
end

# Tickemo/Migration — legacy models, loaders, image migration, importer.
migration_group = find_or_create_group(tickemo_group, "Migration", "Tickemo/Migration")

%w[
  LegacyStoreModels.swift
  LegacyStoreLoading.swift
  ICloudFallbackLoader.swift
  UbiquitousItemDownloader.swift
  ImageMigrator.swift
  DataMigrationImporter.swift
].each do |name|
  next if migration_group.children.any? { |c| c.respond_to?(:path) && c.path == name }
  file_ref = migration_group.new_reference(name)
  sources_phase.add_file_reference(file_ref)
  puts "Registered Migration/#{name}"
end

project.save
puts "Saved #{project_path}"
