# frozen_string_literal: true

# Additive, durable multi-process usage accounting. There is NO provider
# integration, automatic dispatch, billing transaction or outgoing Send here.
class CreateAiUsageReservations < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_usage_reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :room, null: false, foreign_key: true
      t.string :request_key_hash, null: false, limit: 64
      t.string :purpose, null: false, limit: 36
      t.string :state, null: false, default: "reserved", limit: 16
      t.bigint :reserved_ticks, null: false
      t.bigint :allocated_ticks, null: false
      t.bigint :actual_ticks
      t.date :day_utc, null: false
      t.date :month_utc, null: false
      t.datetime :uncertain_at
      t.datetime :settled_at
      t.timestamps
    end

    add_index :ai_usage_reservations, :request_key_hash, unique: true,
      name: "index_ai_usage_reservations_unique_request"
    add_index :ai_usage_reservations, [:user_id, :day_utc],
      name: "index_ai_usage_reservations_user_day"
    add_index :ai_usage_reservations, [:user_id, :month_utc],
      name: "index_ai_usage_reservations_user_month"
    add_index :ai_usage_reservations, [:room_id, :month_utc],
      name: "index_ai_usage_reservations_room_month"
    add_index :ai_usage_reservations, :month_utc,
      name: "index_ai_usage_reservations_global_month"
    add_check_constraint :ai_usage_reservations,
      "reserved_ticks > 0 AND allocated_ticks >= 0 AND (actual_ticks IS NULL OR actual_ticks >= 0)",
      name: "ai_usage_reservations_nonnegative_ticks"
  end
end
