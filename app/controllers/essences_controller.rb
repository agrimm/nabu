class EssencesController < ApplicationController
  load_and_authorize_resource :collection, :find_by => :identifier, except: [:list_mimetypes]
  load_and_authorize_resource :item, :find_by => :identifier, :through => :collection, except: [:list_mimetypes]
  load_and_authorize_resource :essence, :through => :item, except: [:list_mimetypes]

  def show
    @page_title = "Nabu - #{@essence.filename} (#{@essence.item.title})"
    unless can? :manage, @essence
      if @essence.item.access_condition.nil?
        flash[:error] = 'Item does not have data access conditions set'
        redirect_to [@collection, @item]
      elsif ['Open (subject to agreeing to PDSC access conditions)', 'Open (subject to the access condition details)'].include? @essence.item.access_condition.name
        unless session["terms_#{@collection.id}"] == true
          redirect_to show_terms_collection_item_essence_path
        end
      end
    end
  end

  def download
    unless File.exist?(@essence.path)
      flash[:error] = 'File not found'
      redirect_to [@collection, @item, @essence]
      return
    end
    Download.create! :user => current_user, :essence => @essence
    send_file @essence.path, :type => @essence.mimetype, :filename => @essence.filename
  end

  def display
    send_file @essence.path, :disposition => 'inline', :type => @essence.mimetype
  end

  def show_terms
    @page_title = 'Nabu - Terms and Conditions'
  end

  def agree_to_terms
    if params[:agree] == '1'
      session["terms_#{@collection.id}"] = true
      redirect_to [@collection, @item, @essence]
    else
      flash[:error] = 'You must agree to the PDSC access form before you can view files'
      redirect_to [@collection, @item]
    end
  end

  def destroy
    item = @essence.item
    message = EssenceDestructionService.destroy(@essence)
    flash[message.keys.first] = message.values.first # there's only one pair
    redirect_to [item.collection, item]
  end

  def list_mimetypes
    render json: Essence.where('mimetype like ?', "%#{params[:q]}%").uniq.order(:mimetype).pluck(:mimetype).map{|m| {id: m, name: m}} # list distinct mimetypes from the db
  end
end
