# Composing Rails

*Building a Rails application out of components instead of inheritance — and
whether the idea survives contact with a database.*

**Jason Hutchens · July 2026**

---

Last year I watched a conference talk called ["The Big OOPs: Anatomy of a
Thirty-Five-Year Mistake,"](https://www.youtube.com/watch?v=wo84LFzx5nI) given by
Casey Muratori at the 2025 Better Software Conference. Its argument is that the
object-oriented style of modelling most of us were taught — hierarchies of
classes, each inheriting from the one above — was a wrong turn taken decades ago,
and one we have been quietly working around ever since.

I found it hard to disagree, because I have spent a career watching it happen. An
inheritance hierarchy nearly always begins as a clean diagram and slowly stops
being one. `Animal` becomes `Dog` becomes `ServiceDog`, and the design holds
until the day something needs to be two things at once — a customer who is also a
member of staff — and the tidy tree has no branch to put it on. The *is-a*
relationship, it turns out, is rarely the true shape of a domain. It is the shape
of a decision made early, on a whiteboard, and then lived with for years.

## What the game developers did instead

Game developers reached this conclusion some time ago, and many of them moved to
a different approach entirely, called **Entity–Component–System**. The clearest
expression of it I know is [Flecs](https://www.flecs.dev/), a library by Sander
Mertens.

The idea is deliberately small. An *entity* is only an identity — an id, with no
behaviour and no opinions. A *component* is a small, self-contained piece of data
attached to an entity: a position, a velocity, an amount of health. A *system* is
an ordinary function that runs over every entity carrying a particular component.
Nothing inherits from anything. A thing is defined not by what it *is*, but by
what it *has* — and what it has can change at any time.

It is a small idea, and a durable one, but it has lived almost entirely in games
and simulations — places where thousands of objects gain and lose capabilities
many times a second. I found myself wondering whether it could be carried
somewhere quite different: an ordinary Rails web application, where the objects
are rows in a database and a busy moment is a page load.

## An unlikely host

Rails is object-oriented modelling in a concentrated form. ActiveRecord gives you
one class and one table, and it supports inheritance directly, through Single
Table Inheritance: add a `type` column, and subclasses share a table.

It is not, in fairness, hostile to composition. Rails has **Concerns** — modules
of related behaviour that you mix into a model to keep it from growing
unmanageable — and they are used everywhere. But a Concern composes *behaviour*
only. It carries no data of its own; the attributes it works on still live on the
model, and the model is a single, wide table. Each feature a model takes on tends
to add a column or two, most of them nullable, until the `users` table has forty
columns and no one is entirely sure which are still in use. Concerns tidy the
code above the table; they do nothing about the table itself. A component,
roughly, is what you get when you let a Concern carry its own data — and its own
table.

If inheritance-based modelling is the thing in question, Rails is where it is
most at home — which is what made it worth the experiment. Could a Rails
application be built so that its domain model is *composed*, data and all, rather
than inherited? And would the idea survive contact with a relational database, or
come apart at the first foreign key?

The way to answer that is to build it, so I did. The result is a gem,
[ecs_on_rails](https://rubygems.org/gems/ecs_on_rails), and a small bulletin board
built entirely on top of it, [running live](https://ecs-rails.kranzky.com). In
code, an entity declares what it is composed of, and nothing more:

```ruby
class User < ApplicationEntity
  component Name
  component Email
  component Avatar
  component Moderator          # a marker: no data, presence is the meaning
end
```

> One `User` entity, composed of four parts — `Name`, `Email`, `Avatar`, and the
> marker `Moderator` — not a subclass of anything.

## Under the hood

It is worth looking at how this actually works, because the mechanics are where an
idea like this either holds together or quietly falls apart.

There is a single table called `entities`, and it is nearly empty: an id, a
`model` column naming what kind of entity each row is, and a timestamp. Everything
else lives in a table of its own — one per component.

```
entities                 emails                    names
  id                       id                        id
  model     "users"        entity_id  → entities     entity_id  → entities
  created_at               address                   first
                           verified                  last
```

A `User` and a `Post` are rows in that same `entities` table, told apart only by
the `model` string. There is no `users` table to scan, because there is no
`users` table at all. `User.all` becomes a filter on the shared one:

```sql
SELECT * FROM entities WHERE model = 'users'
```

When a row is read back, the `model` column decides which class to build, so
asking the base class for a record by id returns a `User`, not a generic entity.
Rails already carries this machinery for Single Table Inheritance; the gem borrows
the mechanism and aims it at the `model` column instead of `type` — keeping the
one genuinely useful part of STI and leaving the inheritance behind.

Each component is an ordinary `has_one`, but its reader is wrapped. Ask a user for
an email it does not have, and the answer is not `nil`; it is an `Email` with
every attribute at its default, not yet written anywhere. It becomes a database
row only once you change something and save — once there is something worth
keeping. A hundred users with no avatar cost a hundred rows in `entities` and
nothing at all in `avatars`.

```ruby
user = User.create!        # one row in entities, and that is all
user.email                 # => #<Email address: nil> — virtual, unsaved
user.email.address = "a@b.com"
user.save!                 # now, and only now, a row appears in emails
```

Because a component is a real object, it can hold behaviour, and that behaviour is
written from the component's own point of view: inside an `Email`'s methods,
`self` is the `Email`, never the user carrying it. The methods worth having on the
entity are delegated onto it — but into a module that is mixed in, rather than
defined on the entity directly, so that anything you write on the entity itself
takes precedence with no special handling. The entity stays in charge; each
component minds its own affairs.

And because composition is the whole premise, it is also how you query.
`Post.with_component(PublishState, state: "published")` does not join tables. It
compiles to a correlated subquery that asks, for each candidate post, whether a
matching component row exists:

```sql
SELECT * FROM entities
WHERE model = 'posts'
  AND EXISTS (
    SELECT 1 FROM publish_states
    WHERE publish_states.entity_id = entities.id
      AND publish_states.state = 'published'
  )
```

An entity either matches or it does not — no duplicate rows, no table aliases to
keep track of — and the `model = 'posts'` condition is still doing its quiet work,
keeping every other kind of entity out of the results. That last part matters,
because the same `PublishState` component is perfectly content to sit on a `Post`,
a `Comment` or a `Group`; the table it lives in knows nothing about which owns a
given row.

Some components have no columns at all. A `Moderator` is an empty table, and the
only thing a row in it records is that it exists. So presence becomes an operation
in its own right — `user.add(Moderator)`, `user.moderator?`,
`user.remove(Moderator)` — and "is this user a moderator?" is answered by whether
a row is there, rather than by a boolean column on an ever-widening users table.
Deletion is tidy for the same structural reason: every component table holds a
foreign key back to `entities` with `ON DELETE CASCADE`, so removing an entity
removes its components in the database, without Rails loading a single one.

## Assembling, rather than designing

There is a practical consequence to all of this that took me a while to notice,
and it is the reason I kept going. When a model is composed of parts, the parts
can come from anywhere — including from other people.

> You stop designing the data model, and begin assembling it.

So much of schema design is a solved problem that we insist on re-solving. A phone
number has a correct representation — the international
[E.164](https://en.wikipedia.org/wiki/E.164) format, a single canonical string —
and someone who cares about telephony more than you do has already worked it out.
Money has a correct representation too: an integer number of minor units and a
currency code, and never a floating-point value. Addresses, slugs, geographic
coordinates, state machines, expiring tokens — these are well-understood shapes
with settled answers.

Imagine a catalogue of them: components that each capture one person's careful
judgement about one small thing, ready to be attached to an entity as needed. You
would assemble an application much the way you assemble a computer from parts —
choosing the best available for each role, rather than fabricating every piece
yourself.

That is why I think the approach is at its most useful for hobby projects and
proofs of concept. When the aim is to find out whether an idea is worth pursuing
at all, time spent perfecting a schema is time taken from the question that
actually matters. Compose something from ready-made parts, put it in front of
people, and see. If the idea holds, the data model can be given proper attention
later, once it has earned it.

## Where it goes next

A few honest words first. `ecs_on_rails` is an experiment — a demonstration that
Entity–Component–System is workable on Rails, not a mature framework to build a
business on. It has firm opinions and unfinished edges, and the firmest opinion,
for now, is that an entity holds exactly one of each component: one name, one
email, one address. That is clean and unambiguous for identity, and awkward the
first time you want both a billing address and a shipping one.

Lifting that limitation is the piece of design I am most confident about. A
component gains an optional label — a *slot* — so an entity may carry a
`business_address` alongside its `postal_address`, or a `mobile_phone` beside a
`work_phone`, each a proper singleton in its own right. Underneath it is a modest
change: the rule that today guarantees one component per entity is widened to one
per entity per slot, and the plain, unlabelled case becomes simply the default.
Nothing already written has to change.

The larger ambition is the catalogue. Rails has always generated models and
migrations from the command line, and the same machinery generates components just
as well — a better thing to share than a model, because a component is small,
self-contained, and answerable to a standard. The phone number and the currency
amount from a moment ago, installed rather than written; a postal address that
knows how countries genuinely differ; a slug; a state machine that keeps its own
history. A growing library of best-of-breed components, each contributed by
whoever cares most about that one small problem, is the direction I find most
worth pursuing.

And there is the third letter, so far left alone. Systems — the verbs, to
entities' and components' nouns — are at present just plain Ruby objects that
operate over components. That is honest, and unambitious. A real convention for
them, for the scheduled and batched work that acts on many entities at once, is
further off; I would rather let its shape emerge from use than invent it in
advance.

The question I set out with, though, was only whether Entity–Component–System
could work inside a Rails application, and the answer is that it can, with rather
less friction than I expected. The demo is [live](https://ecs-rails.kranzky.com),
the gem is [on RubyGems](https://rubygems.org/gems/ecs_on_rails), and the whole
project — the code, and the design documents that argue with it — is
[on GitHub](https://github.com/kranzky/ecs_rails).

If the idea interests you, the most useful thing you could do is write a
component: a good one, the kind you would want to reach for again. A framework
built on composition is only as good as the parts available to compose with, and
the shelf, for now, is nearly bare.

I'll let you know how I get on.

---

## References

- **[The live demo](https://ecs-rails.kranzky.com)** — a bulletin board built
  entirely on components.
- **[The gem](https://rubygems.org/gems/ecs_on_rails)** — `ecs_on_rails`, on
  RubyGems.
- **[The source](https://github.com/kranzky/ecs_rails)** — code, ADRs and RFCs on
  GitHub.
- **[The Big OOPs](https://www.youtube.com/watch?v=wo84LFzx5nI)** — Casey
  Muratori, Better Software 2025, the talk that started it.
- **[Flecs](https://www.flecs.dev/)** — Sander Mertens' Entity–Component–System
  library.
