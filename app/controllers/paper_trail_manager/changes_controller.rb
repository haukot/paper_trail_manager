# frozen_string_literal: true

# Allow the parent class of ChangesController to be configured in the host app
PaperTrailManager::ChangesController = Class.new(PaperTrailManager.base_controller.constantize)

class PaperTrailManager
  class ChangesController
    # Default number of changes to list on a pagenated index page.
    PER_PAGE = 50

    helper PaperTrailManager.route_helpers if PaperTrailManager.route_helpers
    helper PaperTrailManager::ChangesHelper
    layout PaperTrailManager.layout if PaperTrailManager.layout

    # List changes
    def index
      unless change_index_allowed?
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.permission_denied_index')
        return(redirect_to root_url)
      end

      @versions = PaperTrail::Version.order('created_at DESC, id DESC')
      @versions = @versions.where(item_type: params[:type]) if params[:type]
      @versions = @versions.where(item_id: params[:id]) if params[:id]

      # Ensure pagination parameters have sensible values
      @page = params[:page].to_i
      @page = nil if @page.zero?

      @per_page = params[:per_page].to_i
      @per_page = nil if @per_page.zero?

      @versions = if defined?(WillPaginate)
                    @versions.paginate(page: @page, per_page: @per_page)
                  else
                    @versions.page(@page).per(@per_page)
                  end

      respond_to do |format|
        format.html # index.html.erb
        format.atom # index.atom.builder
        format.json { render json: @versions }
      end
    end

    # Show a change
    def show
      begin
        @version = PaperTrail::Version.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.version_not_found')
        return(redirect_to action: :index)
      end

      unless change_show_allowed?(@version)
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.permission_denied_show')
        return(redirect_to action: :index)
      end

      respond_to do |format|
        format.html # show.html.erb
        format.json { render json: @version }
      end
    end

    # Rollback a change
    def update
      begin
        @version = PaperTrail::Version.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.version_not_found')
        return(redirect_to(changes_path))
      end

      unless change_revert_allowed?(@version)
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.permission_denied_revert')
        return(redirect_to changes_path)
      end

      if @version.event == 'create'
        @record = @version.item_type.constantize.find(@version.item_id)
        @result = @record.destroy
      else
        @record = @version.reify
        @result = @record.save
      end

      if @result
        if @version.event == 'create'
          flash[:notice] = I18n.t('paper_trail_manager.changes.messages.rollback_create_success')
          redirect_to changes_path
        else
          flash[:notice] = I18n.t('paper_trail_manager.changes.messages.rollback_update_success')
          redirect_to change_item_url(@version)
        end
      else
        flash[:error] = I18n.t('paper_trail_manager.changes.messages.rollback_error')
        redirect_to changes_path
      end
    end

    protected

    # Return the URL for the item represented by the +version+, e.g. a Company record instance referenced by a version.
    def change_item_url(version)
      version_type = version.item_type.underscore.split('/').last
      send("#{version_type}_url", version.item_id)
    rescue NoMethodError
      changes_path
    end
    helper_method :change_item_url

    # Allow index?
    def change_index_allowed?
      PaperTrailManager.allow_index?(self)
    end
    helper_method :change_index_allowed?

    # Allow show?
    def change_show_allowed?(version)
      PaperTrailManager.allow_show?(self, version)
    end
    helper_method :change_show_allowed?

    # Allow revert?
    def change_revert_allowed?(version)
      PaperTrailManager.allow_revert?(self, version)
    end
    helper_method :change_revert_allowed?
  end
end
