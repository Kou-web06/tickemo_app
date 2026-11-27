require "xcodeproj"

project_path = File.expand_path("../Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

FILES_TO_REMOVE = %w[
  RecordSeatMapSectionView.swift
  RecordSeatMapPresentation.swift
  TokyoDomeVenueMatching.swift
  RecordSeatMapPresentationTests.swift
].freeze

def remove_file_refs(project, names)
  removed = []
  project.files.each do |file_ref|
    path = file_ref.path.to_s
    name = File.basename(path)
    next unless names.include?(name)

    file_ref.build_files.each do |build_file|
      build_file.remove_from_project
    end
    file_ref.remove_from_project
    removed << name
    puts "Removed #{name}"
  end
  removed
end

removed = remove_file_refs(project, FILES_TO_REMOVE)
missing = FILES_TO_REMOVE - removed
raise "Not found in project: #{missing.join(', ')}" unless missing.empty?

project.save
puts "Saved #{project_path}"
