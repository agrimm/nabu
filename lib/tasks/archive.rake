require 'media'
include ActionView::Helpers::NumberHelper

require "#{Rails.root}/app/helpers/application_helper"
include ApplicationHelper


class OfflineTemplate < AbstractController::Base
  include AbstractController::Rendering
  include AbstractController::Helpers
  #include AbstractController::Layouts
  include CanCan::ControllerAdditions

  def initialize(*args)
    super()
    lookup_context.view_paths = Rails.root.join('app', 'views')
  end

  def current_user
    @current_user ||= User.admins.first
  end

  #def params
  #  {}
  #end
end

class ItemOfflineTemplate < OfflineTemplate
  attr_accessor :item
end

# Coding style for log messages:
# # Only use SUCCESS if an entire action has been completed successfully, not part of the action
# # Use INFO for progress through part of an action
# # WARNING and ERROR have their usual meaning
# # No need for a keyword for announcing a particular action is about to start,
# # or has just finished
namespace :archive do

  desc 'Provide essence files in scan_directory with metadata for sealing'
  task :export_metadata => :environment do
    verbose = ENV['VERBOSE'] ? true : false
    scan_directory = Nabu::Application.config.scan_directory

    BatchExportMetadataService.run(scan_directory, verbose)
  end


  desc 'Import files into the archive'
  task :import_files => :environment do
    verbose = ENV['VERBOSE'] ? true : false
    # Always update metadata
    force_update = true

    # find essence files in Nabu::Application.config.upload_directories
    dir_list = Nabu::Application.config.upload_directories

    dir_list.each do |upload_directory|
      next unless File.directory?(upload_directory)
      dir_contents = Dir.entries(upload_directory)

      # for each essence file, find its collection & item
      # by matching the pattern
      # "#{collection_id}-#{item_id}-xxx.xxx"
      dir_contents.each do |file|
        next unless File.file? "#{upload_directory}/#{file}"

        # skip files of size 0 bytes
        unless File.size?("#{upload_directory}/#{file}")
          puts "WARNING: file #{file} skipped, since it is empty" if verbose
          next
        end

        # skip files that can't be read
        unless File.readable?("#{upload_directory}/#{file}")
          puts "ERROR: file #{file} skipped, since it's not readable" if verbose
          next
        end

        # Skip files that are currently uploading
        last_updated = File.stat("#{upload_directory}/#{file}").mtime
        if (Time.now - last_updated) < 60*10
          next
        end

        basename, extension, coll_id, item_id, collection, item = ParseFileNameService.parse_file_name(verbose, file)
        next unless (collection && item)

        # skip files with item_id longer than 30 chars, because OLAC can't deal with them
        if item_id.length > 30
          puts "WARNING: file #{file} skipped - item id longer than 30 chars (OLAC incompatible)" if verbose
          next
        end

        puts '---------------------------------------------------------------'

        # make sure the archive directory for the collection and item exists
        # and move the file there
        begin
          destination_path = Nabu::Application.config.archive_directory + "#{coll_id}/#{item_id}/"
          FileUtils.mkdir_p(destination_path)
        rescue
          puts "WARNING: file #{file} skipped - not able to create directory #{destination_path}" if verbose
          next
        end

        begin
          FileUtils.cp(upload_directory + file, destination_path + file)
        rescue
          puts "WARNING: file #{file} skipped - not able to read it or write to #{destination_path + file}" if verbose
          next
        end

        puts "INFO: file #{file} copied into archive at #{destination_path}"

        # move old style CAT and df files to the new naming scheme
        if basename.split('-').last == "CAT" || basename.split('-').last == "df"
          FileUtils.mv(destination_path + file, destination_path + "/" + basename + "-PDSC_ADMIN." + extension)
        end

        # files of the pattern "#{collection_id}-#{item_id}-xxx-PDSC_ADMIN.xxx"
        # will be copied, but not added to the list of imported files in Nabu.
        if basename.split('-').last != "PDSC_ADMIN"
          # extract media metadata from file
          puts "Inspecting file #{file}..."
          begin
            import_metadata(destination_path, file, item, extension, force_update)
          rescue => e
            puts "WARNING: file #{file} skipped - error importing metadata [#{e.message}]" if verbose
            puts " >> #{e.backtrace}"
            next
          end
        end

        # if everything went well, remove file from original directory
        FileUtils.rm(upload_directory + file)
        puts "...done"
      end
    end
  end

  desc "Mint DOIs for objects that don't have one"
  task :mint_dois => :environment do
    batch_size = Integer(ENV['MINT_DOIS_BATCH_SIZE'] || 100)
    BatchDoiMintingService.run(batch_size)
  end

  desc "Perform image transformations for all image essences"
  task :transform_images => :environment do
    batch_size = Integer(ENV['IMAGE_TRANSFORMER_BATCH_SIZE'] || 100)
    verbose = true
    BatchImageTransformerService.run(batch_size, verbose)
  end

  desc "Update catalog details of items"
  task :update_item_catalogs => :environment do
    offline_template = OfflineTemplate.new
    BatchItemCatalogService.run(offline_template)
  end

  desc "Transcode essence files into required formats"
  task :transcode_essence_files => :environment do
    batch_size = Integer(ENV['TRANSCODE_ESSENCE_FILES_BATCH_SIZE'] || 100)
    BatchTranscodeEssenceFileService.run(batch_size)
  end

  # HELPERS

  def import_metadata(path, file, item, extension, force_update)
    # since everything operates off of the full path, construct it here
    full_file_path = path + "/" + file

    # extract media metadata from file
    media = Nabu::Media.new full_file_path
    unless media
      puts "ERROR: was not able to parse #{full_file_path} of type #{extension} - skipping"
      return
    end

    # find essence file in Nabu DB; if there is none, create a new one
    essence = Essence.where(:item_id => item, :filename => file).first
    unless essence
      essence = Essence.new(:item => item, :filename => file)
    end

    #attempt to generate derived files such as lower quality versions or thumbnails, continue even if this fails
    generate_derived_files(full_file_path, item, essence, extension, media)

    # update essence entry with metadata from file
    begin
      essence.mimetype   = media.mimetype
      essence.size       = media.size
      essence.bitrate    = media.bitrate
      essence.samplerate = media.samplerate
      essence.duration   = number_with_precision(media.duration, :precision => 3)
      essence.channels   = media.channels
      essence.fps        = media.fps
    rescue => e
      puts "ERROR: unable to process file #{file} - skipping"
      puts" #{e}"
      return
    end

    unless essence.valid?
      puts "ERROR: invalid metadata for #{file} of type #{extension} - skipping"
      essence.errors.each { |field, msg| puts "#{field}: #{msg}" }
      return
    end
    if essence.new_record? || (essence.changed? && force_update)
      essence.save!
      puts "SUCCESS: file #{file} metadata imported into Nabu"
    end
    if essence.changed? && !force_update
      puts "WARNING: file #{file} metadata is different to DB - use 'FORCE=true archive:update_file' to update"
      puts essence.changes.inspect
    end
  end


  # this method tries to avoid regenerating any files that already exist
  def generate_derived_files(full_file_path, item, essence, extension, media)
    ImageTransformerService.new(media, full_file_path, item, essence, ".#{extension}").perform_conversions
  end
end
