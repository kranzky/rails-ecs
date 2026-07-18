# frozen_string_literal: true

# Creates the moderators component table.
#
# Every component table follows the same invariants (docs/architecture.md §2):
# a UUID primary key, a non-null entity_id with a UNIQUE index (ADR-0005) and an
# ON DELETE CASCADE foreign key, and an explicit default for every attribute
# (RFC-0006).
class CreateModerators < ActiveRecord::Migration[8.1]
  def change
    create_table :moderators, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :entity_id, null: false
      t.timestamps
    end

    # ADR-0005: a component appears at most once per entity.
    add_index :moderators, :entity_id, unique: true

    # Destroying an entity destroys its components, at the database level.
    add_foreign_key :moderators, :entities, column: :entity_id, on_delete: :cascade
  end
end
