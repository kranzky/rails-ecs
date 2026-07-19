# frozen_string_literal: true

class Post < ApplicationEntity
  component Title, except: [:text]
  component Body, except: [:text]
  component Authorship
  component PublishState
  component Likes

  # The query the proposal writes as `Post.with(PublishState)` — which doesn't
  # exist yet, and whose name collides with ActiveRecord's own `.with` (CTEs).
  # Hand-rolled across the entity/component split until a query DSL lands.
  # See docs/friction-log.md.
  def self.published
    ids = PublishState.where(state: "published").select(:entity_id)
    where(id: ids).order(created_at: :desc)
  end
end
