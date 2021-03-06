class EntriesController < ApplicationController
  include TagList

  before_action :set_request_format, only: [:index, :tagged, :show]
  before_action :load_tags, :load_tagged_entries, only: [:tagged]
  before_action :load_entries, only: [:index]
  before_action :check_if_user_has_visited, only: [:index, :tagged, :show, :preview]
  before_action :set_max_age, only: [:index, :tagged]
  before_action :set_entry_max_age, only: [:show, :preview]

  def index
    raise ActiveRecord::RecordNotFound if @entries.empty?
    if stale?(@photoblog, public: true)
      respond_to do |format|
        format.html
        format.json
        format.atom
      end
    end
  end

  def tagged
    raise ActiveRecord::RecordNotFound if @tags.empty? || @entries.empty?
    if stale?(@photoblog, public: true)
      respond_to do |format|
        format.html
        format.json
        format.atom
      end
    end
  end

  def show
    @entry = @photoblog.entries.includes(:photos, :user, :blog).published.find(params[:id])
    if stale?(@photoblog, public: true)
      respond_to do |format|
        format.html {
          redirect_to(@entry.permalink_url, status: 301) unless params_match(@entry, params)
        }
        format.json
        format.amp {
          @is_amp = true
          render layout: nil
        }
      end
    end
  end

  def preview
    request.format = 'html'
    @entry = @photoblog.entries.includes(:photos, :user, :blog).find(params[:id])
    if stale?(@photoblog, public: true)
      respond_to do |format|
        format.html {
          if @entry.is_published?
            redirect_to @entry.permalink_url
          else
            render 'entries/show'
          end
        }
      end
    end
  end

  def tumblr
    expires_in 1.year, public: true
    @entry = @photoblog.entries.published.where(tumblr_id: params[:tumblr_id]).order('published_at ASC').first
    raise ActiveRecord::RecordNotFound if @entry.nil?
    if stale?(@entry, public: true)
      respond_to do |format|
        format.html {
          redirect_to @entry.permalink_url, status: 301
        }
      end
    end
  end

  def sitemap
    @entries = @photoblog.entries.published
    expires_in 24.hours, public: true
    if stale?(@photoblog, public: true)
      render format: 'xml'
    end
  end

  private
  def params_match(entry, params)
    entry_date = entry.published_at
    year = entry_date.strftime('%Y')
    month = entry_date.strftime('%-m')
    day = entry_date.strftime('%-d')
    slug = entry.slug

    year == params[:year] &&
    month == params[:month] &&
    day == params[:day] &&
    slug == params[:slug]
  end

  def load_entries
    @page = (params[:page] || 1).to_i
    @count = (params[:count] || @photoblog.posts_per_page).to_i
    @entries = @photoblog.entries.includes(:photos).published.page(@page).per(@count)
  end

  def load_tagged_entries
    @page = (params[:page] || 1).to_i
    @count = (params[:count] || @photoblog.posts_per_page).to_i
    @entries = @photoblog.entries.includes(:photos).published.tagged_with(@tag_list, any: true).page(@page).per(@count)
  end

  def set_request_format
    request.format = 'json' if request.headers['Content-Type'].try(:downcase) == 'application/vnd.api+json'
  end
end
