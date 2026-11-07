module RoomsHelper
  PUBLIC_SEARCH_MAX_LENGTH = 60
  PUBLIC_SEARCH_RESULT_LIMIT = 20

  def search_rooms
    query = params[:name_search].to_s.strip
    return Room.none unless query.length.between?(2, PUBLIC_SEARCH_MAX_LENGTH)

    # Treat SQL wildcard characters as literal search input. Use a subquery
    # instead of plucking an unbounded list of a user's joined room IDs.
    escaped = ActiveRecord::Base.sanitize_sql_like(query)
    Room.public_rooms
      .where.not(id: current_user.joined_rooms.select(:id))
      .where("name ILIKE ?", "%#{escaped}%")
      .order(name: :asc, id: :asc)
      .limit(PUBLIC_SEARCH_RESULT_LIMIT)
  end
end
