class AddCountryLanguageTable < ActiveRecord::Migration
  def change
    create_table :countries_languages do |t|
      t.belongs_to :country, :null => false
      t.belongs_to :language, :null => false
    end
    add_index :countries_languages, [:country_id, :language_id], :unique => :true

    remove_index :languages, :country_id
    remove_column :languages, :country_id
  end
end
