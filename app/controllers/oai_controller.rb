class OaiController < ApplicationController
  def item
    # Remove controller and action from the options.  Rails adds them automatically.
    options = params.delete_if { |k,v| %w{controller action}.include?(k) }
    provider = ItemProvider.new
    response =  provider.process_request(options)
    render :text => response, :content_type => 'text/xml'
  end

  def collection
    # Remove controller and action from the options.  Rails adds them automatically.
    options = params.delete_if { |k,v| %w{controller action}.include?(k) }
    provider = CollectionProvider.new
    response =  provider.process_request(options)
    render :text => response, :content_type => 'text/xml'
  end
end
