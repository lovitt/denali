class Admin::EntriesController < AdminController
  before_action :set_entry, only: [:show, :edit, :update, :destroy, :publish, :queue, :draft, :reposition, :preview]
  before_action :get_tags, only: [:new, :edit, :create, :update]

  after_action :enqueue_jobs, only: [:create, :publish]
  after_action :enqueue_invalidation, only: [:update]

  # GET /admin/entries
  def index
    @page = params[:page] || 1
    @entries = @photoblog.entries.published.page(@page)
    @page_title = 'Published'
  end

  # GET /admin/entries/queued
  def queued
    @entries = @photoblog.entries.queued
    @page_title = 'Queued'
  end

  # GET /admin/entries/drafts
  def drafts
    @entries = @photoblog.entries.drafted
    @page_title = 'Drafts'
  end

  # GET /admin/entries/new
  def new
    @entry = @photoblog.entries.new
    @entry.photos.build
    @page_title = 'New entry'
  end

  # GET /admin/entries/1/edit
  def edit
    @page_title = "Editing “#{@entry.title}”"
  end

  # PATCH /admin/entries/1/publish
  def publish
    respond_to do |format|
      if @entry.publish && @entry.update_position
        notice = 'Entry was successfully published.'
      else
        notice = 'Entry couldn\'t be published.'
      end
      format.html { redirect_to request.referrer || admin_entries_path, notice: notice }
    end
  end

  # PATCH /admin/entries/1/queue
  def queue
    notice = @entry.queue && @entry.update_position ? 'Entry was successfully queued.' : 'Entry couldn\'t be queued.'
    respond_to do |format|
      format.html { redirect_to request.referrer || queued_admin_entries_path, notice: notice }
    end
  end

  # PATCH /admin/entries/1/draft
  def draft
    notice = @entry.draft && @entry.update_position ? 'Entry was successfully saved as draft.' : 'Entry couldn\'t be saved as draft.'
    respond_to do |format|
      format.html { redirect_to request.referrer || drafts_admin_entries_path, notice: notice }
    end
  end

  # POST /admin/entries
  def create
    @entry = Entry.new(entry_params)
    @entry.user = current_user
    @entry.blog = @photoblog
    respond_to do |format|
      if @entry.save && @entry.update_position
        format.html { redirect_to get_redirect_url(@entry), notice: 'Entry was successfully created.' }
      else
        format.html { render :new }
      end
    end
  end

  # PATCH/PUT /admin/entries/1
  def update
    respond_to do |format|
      if @entry.update(entry_params)
        format.html { redirect_to get_redirect_url(@entry), notice: 'Entry was successfully updated.' }
      else
        format.html { render :edit }
      end
    end
  end

  # DELETE /admin/entries/1
  def destroy
    @entry.destroy
    respond_to do |format|
      format.html { redirect_to request.referrer || admin_entries_path, notice: 'Entry was successfully destroyed.' }
    end
  end

  def reposition
    @entry.insert_at(params[:position].to_i)
    respond_to do |format|
      format.js { render text: 'ok' }
    end
  end

  def photo
    @entry = Entry.new
    @count = params[:count] || 1
    @entry.photos.build
    respond_to do |format|
      format.html { render layout: nil }
    end
  end

  def preview
    respond_to do |format|
      format.html { render 'entries/show', layout: 'application' }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_entry
      @entry = @photoblog.entries.find(params[:id])
    end

    def get_tags
      @tags = ActsAsTaggableOn::Tag.order('name asc')
    end

    def entry_params
      params.require(:entry).permit(:title, :body, :slug, :status, :tag_list, :post_to_twitter, :post_to_tumblr, :post_to_facebook, :tweet_text, :invalidate_cloudfront, photos_attributes: [:source_url, :source_file, :id, :_destroy, :position, :caption])
    end

    def enqueue_jobs
      if @entry.is_published? && Rails.env.production?
        TwitterJob.perform_later(@entry) if @entry.post_to_twitter
        TumblrJob.perform_later(@entry) if @entry.post_to_tumblr
        BufferJob.perform_later(@entry) if @entry.post_to_facebook
        YoJob.perform_later(@entry)
      end
    end

    def enqueue_invalidation
      CloudfrontInvalidationJob.perform_later(@entry) if Rails.env.production? && @entry.is_published? && entry_params[:invalidate_cloudfront] == "1"
    end

    def get_redirect_url(entry)
      if entry.is_published?
        permalink_url(entry)
      elsif entry.is_queued?
        queued_admin_entries_path
      else
        drafts_admin_entries_path
      end
    end
end
