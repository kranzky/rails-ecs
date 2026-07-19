# frozen_string_literal: true

class Post < ApplicationEntity
  component Title, except: [:text]
  component Body, except: [:text]
  component Authorship
  component PublishState
  component Likes
end
