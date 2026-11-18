module RoomsHelper
  PUBLIC_SEARCH_MAX_LENGTH = 60
  PUBLIC_SEARCH_RESULT_LIMIT = 20

  # Only names of private groups in which the viewer currently participates
  # may be searched. Pending invitations and past memberships grant no access.
  def search_private_groups
    query = params[:name_search].to_s.strip
    return Room.none unless query.length.between?(2, PUBLIC_SEARCH_MAX_LENGTH)

    escaped = ActiveRecord::Base.sanitize_sql_like(query)
    Room.private_groups.joins(:participants)
      .where(participants: { user_id: current_user.id })
      .where("rooms.name ILIKE ?", "%#{escaped}%")
      .order(name: :asc, id: :asc)
      .limit(PUBLIC_SEARCH_RESULT_LIMIT)
  end

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
