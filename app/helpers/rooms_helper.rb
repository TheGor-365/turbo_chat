module RoomsHelper
  def search_rooms
    query = params[:name_search].to_s.strip.first(80)
    return Room.none if query.blank?

    safe_query = ActiveRecord::Base.sanitize_sql_like(query)
    Room.public_rooms
        .where.not(id: current_user.joined_rooms.select(:id))
        .where("name ILIKE ?", "%#{safe_query}%")
        .order(name: :asc)
        .limit(25)
  end
end
