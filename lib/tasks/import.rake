namespace :import do

  desc 'Setup database from old PARADISEC data & other imports'
  task :all => [:setup, :import]

  desc 'Setup database from old PARADISEC'
  task :setup => [:load_db, :add_identifiers]

  desc 'Import data from old PARADISEC DB & other files'
  task :import => [:users, :contacts,
                   :universities,
                   :countries, :languages, :fields_of_research, :collections]
#                   :discourse_types, :agent_roles, :items

  desc 'Teardown intermediate stuff'
  task :teardown => [:remove_identifiers]


##  SUBROUTINES BELOW HERE ##

  ## FOR DB IMPORT

  desc 'Load database from old PARADISEC system'
  task :load_db do
    system 'echo "DROP DATABASE paradisec_legacy" | mysql -u root'
    system 'echo "CREATE DATABASE paradisec_legacy" | mysql -u root'
    system "mysql -u root paradisec_legacy < #{Rails.root}/db/legacy/paradisecDump.sql"
  end


  ## ADD / REMOVE ID COLUMS

  class AddIdentifiers < ActiveRecord::Migration
    def change
      add_column :users, :pd_user_id, :integer
      add_column :users, :pd_contact_id, :integer

      add_column :collections, :pd_collector_id, :integer
      add_column :collections, :pd_operator_id, :integer
      add_column :collections, :pd_coll_id, :string

      add_column :items, :pd_coll_id, :string
      add_column :discourse_types, :pd_dt_id, :integer
      add_column :agent_roles, :pd_role_id, :integer
    end
  end

  desc 'Add paradisec_legacy identifier colums to DBs for import tasks'
  task :add_identifiers => :environment do
    AddIdentifiers.migrate(:up)
  end

  desc 'Remove paradisec_legacy identifier colums to DBs for import tasks'
  task :remove_identifiers => :environment do
    AddIdentifiers.migrate(:down)
  end


  def connect
    require 'mysql2'
    client = Mysql2::Client.new(:host => "localhost", :username => "root")
    client.query("use paradisec_legacy")
    client.query("set names utf8")
    client
  end

  ## FOR USERS

  def fixme(object, field, default = 'FIXME')
    msg = "#{object} has invalid field #{field}"
    if Rails.env == "development"
#      $stderr.puts msg + " replacing with " + default
    else
      raise msg
    end
    default
  end

  desc 'Import users into NABU from paradisec_legacy DB'
  task :users => :environment do
    client = connect
    users = client.query("SELECT * FROM users")
    users.each do |user|
      next if user['usr_deleted'] == 1

      ## user name
      first_name, last_name = user['usr_realname'].split(/ /, 2)
      if last_name.blank?
        first_name = user['usr_realname']
        last_name = 'unknown'
      end

      ## admin access
      access = user['usr_access'] == 'administrator' ? true : false

      ## email
      email = user['usr_email']
      if email.blank?
        email = fixme(user, 'usr_email', user['usr_id'].to_s+'@example.com')
      end

      ## password
      password = fixme(user, 'password', 'asdfgj')

      ## create user
      new_user = User.new :first_name => first_name,
                          :last_name => last_name,
                          :email => email,
                          :password => password,
                          :password_confirmation => password
      new_user.pd_user_id = user['usr_id']
      new_user.admin = access
      if !new_user.valid?
        puts "Error parsing User #{user['usr_id']}"
        puts "#{new_user.errors}"
        if Rails.env == "development"
          next
        end
      end
      new_user.save!
      puts "saved new user #{first_name} #{last_name}, #{user['usr_id']}"
    end
  end

  desc 'Import contacts into NABU from paradisec_legacy DB (do users first)'
  task :contacts => :environment do
    client = connect
    users = client.query("SELECT * FROM contacts")
    users.each do |user|
      next if user['cont_collector'].blank? && user['cont_collector_surname'].blank?
      last_name, first_name = user['cont_collector'].split(/, /, 2)
      if first_name.blank?
        first_name, last_name = user['cont_collector'].split(/ /, 2)
      end
      if last_name.blank?
        first_name = user['cont_collector']
        last_name = user['cont_collector_surname']
      end
      if user['cont_email']
        email = user['cont_email'].split(/ /)[0]
      end
      if email.blank?
        email = fixme(user, 'cont_email', user['cont_id'].to_s + 'cont@example.com')
      end
      address = user['cont_address1']
      if user['cont_address1'] && user['cont_address2']
        address = user['cont_address1'] + ',' + user['cont_address2']
      end

      # identify if this user already exists in DB
      cur_user = User.first(:conditions => ["first_name = ? AND last_name = ?", first_name, last_name])
      if cur_user
        cur_user.email = email
        cur_user.address = address
        cur_user.country = user['cont_country']
        cur_user.phone = user['cont_phone']
        cur_user.pd_contact_id = user['cont_id']
        cur_user.save!
        puts "saved existing user " + cur_user.email
      else
        password = fixme(user, 'password', 'asdfgh')
        new_user = User.new :first_name => first_name,
                            :last_name => last_name,
                            :email => email,
                            :password => password,
                            :password_confirmation => password,
                            :address => address,
                            :country => user['cont_country'],
                            :phone => user['cont_phone']
        new_user.pd_contact_id = user['cont_id']
        new_user.admin = false
        if !new_user.valid?
          puts "Error parsing contact #{user['cont_id']}"
          puts first_name + " " + last_name
        end
        new_user.save!
        puts "saved new user " + new_user.email
      end
    end
  end


  ## FOR COLLECTIONS

  desc 'Import universities into NABU from paradisec_legacy DB'
  task :universities => :environment do
    client = connect
    universities = client.query("SELECT * FROM universities")
    universities.each do |uni|
      next if uni['uni_description'].empty?
      new_uni = University.new :name => uni['uni_description']
      if !new_uni.valid?
        puts "Error adding university #{uni['uni_description']}"
        next
      end
      new_uni.save!
      puts "Saved university #{uni['uni-description']}"
    end
  end

  desc 'Import countries into NABU from ethnologue DB'
  task :countries => :environment do
    require 'iconv'
    data = File.open("#{Rails.root}/data/CountryCodes.tab", "rb").read
    data = Iconv.iconv('UTF8', 'ISO-8859-1', data).first.force_encoding('UTF-8')
    data.each_line do |line|
      next if line =~ /^CountryID/
      code, name, area = line.split("\t")
      country = Country.new :name => name
      if !country.valid?
        puts "Skipping adding country #{code}, #{name}, #{area}"
        next
      end
      country.save!
      puts "Saved country #{name}"
    end
  end

  desc 'Import languages into NABU from ethnologue DB'
  task :languages => :environment do
    require 'iconv'
    data = File.open("#{Rails.root}/data/LanguageIndex.tab", "rb").read
    data = Iconv.iconv('UTF8', 'ISO-8859-1', data).first.force_encoding('UTF-8')
    data.each_line do |line|
      next if line =~ /^LangID/
        code, country_code, name_type, name = line.strip.split("\t")
      next unless name_type == "L"
      language = Language.new :code => code, :name => name
      if !language.valid?
        puts "Error adding language #{code}, #{name}"
        next
      end
      language.save!
      puts "Saved language #{code}, #{name}"
    end
  end

  desc 'Import fields_of_research into NABU from ANDS DB'
  task :fields_of_research => :environment do
    require 'iconv'
    data = File.open("#{Rails.root}/data/ANZSRC.txt", "rb").read
    data = Iconv.iconv('UTF8', 'ISO-8859-1', data).first.force_encoding('UTF-8')
    data.each_line do |line|
      id, name = line.split(" ", 2)
      id.strip!
      name.strip!
      field = FieldOfResearch.new :identifier => id, :name => name
      if !field.valid?
        puts "Error adding field of research #{id}, #{name}"
        next
      end
      field.save!
      puts "Saved field of research #{id}, #{name}"
    end
  end

  desc ' Import collections into NABU from paradisec_legacy DB'
  task :collections => :environment do
    client = connect
    collections = client.query("SELECT * FROM collections")
    collections.each do |coll|
      next if coll['coll_id'].blank?
      puts "analysing collection #{coll['coll_id']}"
      next if !coll['coll_collector_id'] or coll['coll_collector_id'] == 0
      collector = User.find_by_pd_contact_id coll['coll_collector_id']
      puts "Collector = #{collector.id} (contact: #{collector.pd_contact_id}), #{collector.first_name} #{collector.last_name}"
      if !coll['coll_original_uni'].blank?
        uni = University.find_by_name coll['coll_original_uni']
        puts "University = #{uni.name}"
      end
      coll_xmax = coll['coll_xmax']
      coll_xmin = coll['coll_xmin']
      coll_ymax = coll['coll_ymax']
      coll_ymin = coll['coll_ymin']
      if (coll_xmax && coll_xmin && coll_ymax && coll_ymin)
        longitude = (coll_xmax + coll_xmin) / 2.0
        latitude = (coll_ymax + coll_ymin) / 2.0
        zoom = 20 - ((coll_xmax - coll_xmin) / 18)
        zoom =  zoom < 0 ? 0 : (zoom > 20 ? 20 : zoom)
      else
        latitude = 0
        longitude = 0
        zoom = 0
      end
      if !coll['coll_access_conditions'].blank?
        puts "acces condition #{coll['coll_access_conditions']}"
        access_cond = AccessCondition.find_by_name coll['coll_access_conditions']
        if !access_cond
          access_cond = AccessCondition.create! :name => coll['coll_access_conditions']
        end
      end
puts "creating collection"
puts "#{coll['coll_id']}, #{coll['coll_description']}, #{coll['coll_note']}"
puts "#{collector.id}, #{uni}"
     new_coll = Collection.new :identifier => coll['coll_id'],
                                :title => coll['coll_description'] || fixme(coll, :title),
                                :description => coll['coll_note'],
                                :region => coll['coll_region_village'],
                                :latitude => latitude,
                                :longitude => longitude,
                                :zoom => zoom.to_i,
                                :access_narrative => coll['coll_access_narrative'],
                                :metadata_source => coll['coll_metadata_source'],
                                :orthographic_notes => coll['coll_orthographic_notes'],
                                :media => coll['coll_media'],
                                :comments => coll['coll_comments'],
                                :deposit_form_recieved => coll['coll_depform_rcvd'],
                                :tape_location => coll['coll_location']
      if collector
        new_coll.collector_id = collector.id
      end
      if uni
        new_coll.university_id = uni.id
      end
      if access_cond
        new_coll.access_condition_id = access_cond.id
      end
      new_coll.created_at = coll['coll_date_created']
      new_coll.updated_at = coll['coll_date_modified']

# missing new fields:
#      t.integer  "field_of_research_id",  :null => false
#      t.boolean  "complete"
#      t.boolean  "private"

# missing old fields:
# coll_operator_id: int

      if !new_coll.valid?
        puts "Error adding collection #{coll['coll_id']} #{coll['coll_note']}"
        puts "#{new_coll.errors}"
      end
      new_coll.save!
      puts "Saved collection #{coll['coll_id']} #{coll['coll_description']}"

      # language
      # country
    end

  end


  ## FOR ITEMS

  desc 'Import discourse_types into NABU from paradisec_legacy DB'
  task :discourse_types => :environment do
    client = connect
    discourses = client.query("SELECT * FROM discourse_types")
    discourses.each do |discourse|
      disc_type = DiscourseType.new :name => discourse['dt_name']
      if !disc_type.valid?
        puts "Error adding discourse type #{discourse['dt_name']}"
        next
      end
      disc_type.save!
      puts "Saved discourse type #{discourse['dt_name']}"
    end
  end

  desc 'Import agent_roles into NABU from paradisec_legacy DB'
  task :agent_roles => :environment do
    client = connect
    roles = client.query("SELECT * FROM roles")
    roles.each do |role|
      new_role = AgentRole.new :name => role['role_name']
      if !new_role.valid?
        puts "Error adding agent role #{role['role_name']}"
        next
      end
      new_role.save!
      puts "Saved agent role #{role['role_name']}"
    end
  end


# - import collection
# - import items
# - import content essences
end
