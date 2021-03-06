ActiveAdmin.register FieldOfResearch do
  menu :parent => "Other Entities"
  config.sort_order = "name_asc"
  actions :all, :except => [:destroy]

  # Don't filter by collections
  filter :identifier
  filter :name
end
