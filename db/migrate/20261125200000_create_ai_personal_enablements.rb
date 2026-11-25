class CreateAiPersonalEnablements < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_personal_enablements do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.boolean :enabled, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
      t.check_constraint "lock_version >= 0", name: "ai_personal_enablements_nonnegative_lock"
    end
  end
end
