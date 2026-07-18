# frozen_string_literal: true

# Creates the member_groups component table.
#
# Every component table follows the same invariants (docs/architecture.md §2):
# a UUID primary key, a non-null entity_id with a UNIQUE index (ADR-0005) and an
# ON DELETE CASCADE foreign key, and an explicit default for every attribute
# (RFC-0006).
class CreateMemberGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :member_groups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :entity_id, null: false
      t.uuid :group_id, default: nil
      t.timestamps
    end

    # ADR-0005: a component appears at most once per entity.
    add_index :member_groups, :entity_id, unique: true

    # Destroying an entity destroys its components, at the database level.
    add_foreign_key :member_groups, :entities, column: :entity_id, on_delete: :cascade
  end
end
