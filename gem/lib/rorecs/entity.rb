# frozen_string_literal: true

module Rorecs
  # An immutable identity row. Carries no domain state.
  #
  # Implements RFC-0001. See docs/architecture.md §1 for the invariants and
  # docs/adr/0002-single-entities-table.md for why the `model` column exists.
  #
  # Host apps subclass this once, as ApplicationEntity, then subclass that per
  # entity type:
  #
  #   class ApplicationEntity < Rorecs::Entity
  #     self.abstract_class = true
  #   end
  #
  #   class User < ApplicationEntity
  #   end
  #
  #   User.create!.model  # => "users"
  #   User.all            # => SELECT * FROM entities WHERE model = 'users'
  #   ApplicationEntity.all # => SELECT * FROM entities  (no filter)
  #
  # All entity classes share the one `entities` table. There is no updated_at
  # column: an entity is written once and never changes, so ActiveRecord's
  # timestamp code — which only touches timestamp columns that actually exist —
  # stamps created_at and nothing else. No configuration is needed for that.
  class Entity < ActiveRecord::Base
    # Makes assignment to a readonly attribute raise on a persisted record.
    #
    # ActiveRecord ships this behaviour, but `attr_readonly` only installs it
    # when `ActiveRecord.raise_on_assign_to_attr_readonly` is true. That config
    # defaults to *false* in bare ActiveRecord, and in a Rails app it is applied
    # by the railtie only after this file has already been required — so by the
    # time `attr_readonly` runs below, the host's setting is not yet visible and
    # cannot be relied on either way. RFC-0001 requires the raise
    # unconditionally, so we install our own guard rather than inherit a race.
    #
    # Harmless if ActiveRecord's own guard is also installed: both raise the
    # same error.
    module ImmutableIdentity
      # Rejects writes to readonly attributes once the row exists. New records
      # are untouched, so create — including ActiveRecord assigning the
      # database-generated id — still works.
      #
      # Both writers are guarded because the public #write_attribute does not
      # call #_write_attribute; it writes to the attribute set directly.
      def write_attribute(attr_name, value)
        guard_readonly_attribute!(attr_name)
        super
      end

      # The internal writer, which every generated `attr=` method funnels into.
      def _write_attribute(attr_name, value)
        guard_readonly_attribute!(attr_name)
        super
      end

      private

      def guard_readonly_attribute!(attr_name)
        return if new_record?
        return unless self.class.readonly_attributes.include?(attr_name.to_s)

        raise ActiveRecord::ReadonlyAttributeError, attr_name
      end
    end

    self.abstract_class = true
    self.table_name = "entities"

    include ImmutableIdentity

    # Immutable identity (architecture.md §1). Beyond the guard above, this is
    # what excludes id and model from any UPDATE statement.
    attr_readonly :id, :model

    # Filters each concrete subclass to its own discriminator.
    #
    # `default_scope` is the right mechanism here despite its usual reputation,
    # for two reasons:
    #
    # 1. `build_default_scope` returns early for abstract classes, so the
    #    abstract base applies no filter and can query across all entities —
    #    exactly what RFC-0001 asks for, with no special-casing from us.
    # 2. The block is instance_exec'd against the relation, so `klass` is
    #    whichever class is being queried. One declaration here covers every
    #    subclass, and a subclass of a subclass filters on its own plural.
    #
    # Its notorious leak into `new`/`create` is, unusually, wanted: scope_for_create
    # means `User.new.model` is already "users" before save. That leak is a
    # convenience, not the mechanism — #stamp_model below is what guarantees the
    # discriminator is correct.
    default_scope { where(model: klass.model_name.plural) }

    # RFC-0001: model is set on create from the subclass's model_name.plural.
    #
    # Deliberately not left to the default scope's scope_for_create. The
    # discriminator is derived from the class, never supplied by the caller, so
    # it is stamped unconditionally: `User.create!(model: "posts")` yields a
    # user, and `User.unscoped.create!` — which has no create scope to inherit —
    # is still stamped rather than failing the NOT NULL constraint.
    before_validation :stamp_model, on: :create

    private

    # Stamps the model discriminator from the class name. See ADR-0002.
    def stamp_model
      self.model = self.class.model_name.plural
    end
  end
end
