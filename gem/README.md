# ECS Rails

An Entity–Component–System reimagining of ActiveRecord that stays idiomatic to
Ruby on Rails.

> The full API below is implemented and tested (534 examples on real
> PostgreSQL). A companion bulletin-board app is built entirely on it and runs
> live at **[ecs-rails.kranzky.com](https://ecs-rails.kranzky.com)**. See the
> [v0.1 retrospective](https://github.com/kranzky/rails-ecs/blob/main/docs/retrospective-v0.1.md)
> for the full story of how it was designed.

## The idea

Replace one-table-per-model with one-table-per-component. An entity is a
lightweight identity row; all state and behaviour live in small, reusable
components that are composed onto it.

```ruby
class User < ApplicationEntity
  component Name
  component Email
  component Avatar
  component Moderator          # a marker: no data, presence is the meaning
end

class Email < ApplicationComponent
  validates :address, presence: true

  def send_welcome_email
    # self is the Email, never the User
  end
end
```

```ruby
user = User.create!            # one row in `entities`, no component rows
user.email                     # => #<Email> — virtual, not persisted
user.email.address = "a@b.com"
user.save!                     # now `emails` gets a row

user.send_welcome_email        # delegated to the Email component
user.errors[:"email.address"]  # component errors merge onto the entity
```

Every v0.1 capability, working today:

```ruby
# Lazy components — no row until a value differs from its default.
user.avatar.persisted?                       # => false, costs no INSERT

# Presence / markers — a user IS a moderator when the row exists.
user.add(Moderator); user.moderator?         # => true
user.remove(Moderator)

# Query by composition — avoids AR's .with (CTEs); scopes to the entity model.
Post.with_component(PublishState, state: "published")
User.without_component(Avatar)

# Preload to bound the query count on a list view.
Post.with_component(PublishState).includes_components(Title, Body, Likes)
```

Components are shared by *type*, so `Likes` behaves identically on a `Post` and
a `Comment` — reuse without STI and without polymorphic associations.

## Getting started

```sh
rails g ecs_rails:install
rails g ecs_rails:component Email address:string verified:boolean
```

Entities go in `app/entities`, components in `app/entities/components`
([configurable](https://github.com/kranzky/rails-ecs/blob/main/docs/adr/0010-entity-component-directory-layout.md)); the
install generator wires the autoloading.

## Documentation

- **[Architecture](https://github.com/kranzky/rails-ecs/blob/main/docs/architecture.md)** — the invariants. Start here.
- **[v0.1 retrospective](https://github.com/kranzky/rails-ecs/blob/main/docs/retrospective-v0.1.md)** — what was built, what
  the demo found, what's next.
- **[ADRs](https://github.com/kranzky/rails-ecs/tree/main/docs/adr)** — why the design is the way it is (14 decisions,
  several amended by their own demo).
- **[RFCs](https://github.com/kranzky/rails-ecs/tree/main/docs/rfc)** — the 13 features, each one commit.
- **[Backlog](https://github.com/kranzky/rails-ecs/blob/main/docs/backlog.md)** — what deliberately isn't built yet.
- **[Friction log](https://github.com/kranzky/rails-ecs/blob/main/docs/friction-log.md)** — the demo's running verdict on
  the API.

## Development

Requires Ruby >= 3.2 and a running PostgreSQL.

```sh
createdb ecs_rails_test
bundle install
bundle exec rspec
```

Set `DATABASE_URL` to point the suite at a different database.

## Names

Three, deliberately different — see
[ADR-0007](https://github.com/kranzky/rails-ecs/blob/main/docs/adr/0007-monorepo-and-licensing.md#three-different-names).

| | |
|---|---|
| GitHub repo | [`rails-ecs`](https://github.com/kranzky/rails-ecs) |
| RubyGems gem | `ecs_rails` |
| Ruby module | `EcsRails` |
| `require` | `ecs_rails` |

The gem, module, and require are all `ecs_rails` / `EcsRails`. A `rails-` prefix
is reserved by convention for Rails Core Team gems, so the repo (not the gem)
carries it.

## Licence

MIT. See [LICENSE.txt](LICENSE.txt).
