class CollectionCountry < ActiveRecord::Base
  belongs_to :country
  belongs_to :collection
end