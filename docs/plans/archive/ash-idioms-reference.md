# Ash Idioms Reference Guide

*Condensed reference for auditing Elixir/Ash codebases. Each section: WHAT IT IS, WHEN TO USE, CODE EXAMPLE, ANTI-PATTERN.*

---

## 1. Domains

**WHAT IT IS**
An Ash Domain groups related resources and acts as the canonical public boundary for a business capability — the equivalent of a Phoenix Context but with enforced structure. It is the only layer external callers should interact with; never call resource actions directly from outside the domain.

**WHEN TO USE**
- Every resource belongs to exactly one domain
- Cross-cutting authorization rules (e.g. `authorize :by_default`) belong here
- Shared execution config (timeouts, tracer, short name) belongs here
- Define all code interface functions here so callers never reference resource modules

**CODE EXAMPLE**
```elixir
defmodule MyApp.Tweets do
  use Ash.Domain

  resources do
    resource MyApp.Tweets.Tweet do
      define :create_tweet, action: :create, args: [:text]
      define :get_tweet,    action: :read,   get_by: :id
      define :delete_tweet, action: :destroy
    end
  end
end

# Usage — only the domain is called from outside
tweet = MyApp.Tweets.create_tweet!("Hello", actor: user)
```

**ANTI-PATTERN**
```elixir
# Wrong: calling resource actions directly from a LiveView or controller
{:ok, tweet} = MyApp.Tweets.Tweet
  |> Ash.Changeset.for_create(:create, %{text: "Hello"})
  |> Ash.create(actor: user)

# Wrong: writing hand-rolled wrapper functions in the domain
def create_tweet(text, actor) do
  MyApp.Tweets.Tweet
  |> Ash.Changeset.for_create(:create, %{text: text})
  |> Ash.create(actor: actor)
end
```

---

## 2. Code Interface (`define`)

**WHAT IT IS**
The `define` macro inside a `resource` block of a domain auto-generates named public functions on the domain module. It eliminates boilerplate wrapper functions and makes action-to-function mapping explicit and auditable in one place.

**WHEN TO USE**
- Any resource action that external callers need to invoke
- Replacing hand-written `def create_foo(attrs)` wrapper functions in domain modules
- Exposing read actions with `get_by:` for common lookup patterns
- Controlling which inputs are accepted from outside via `exclude_inputs:`

**CODE EXAMPLE**
```elixir
defmodule MyApp.Accounts do
  use Ash.Domain

  resources do
    resource MyApp.Accounts.User do
      # Positional args mapped to action inputs
      define :create_user, action: :create, args: [:email, :name]

      # get? returns a single record (raises if multiple match)
      define :get_user_by_id, action: :read, get_by: :id

      # get_by shorthand -- auto-filters by field
      define :get_user_by_email, action: :read, get_by: :email

      # update with require_reference? (default: true) -- first arg is the record
      define :update_user, action: :update

      # not_found_error?: false returns nil instead of raising
      define :find_user, action: :read, get_by: :id, not_found_error?: false
    end
  end
end

# Generated bang + non-bang variants
{:ok, user} = MyApp.Accounts.create_user("a@b.com", "Alice", actor: admin)
user = MyApp.Accounts.get_user_by_id!(user_id, actor: admin)
nil  = MyApp.Accounts.find_user(unknown_id, actor: admin)
```

**Key `define` options:**

| Option | Purpose |
|---|---|
| `action:` | Which action to invoke (defaults to function name) |
| `args:` | Maps positional function args to action inputs |
| `get?:` | Return single result instead of list |
| `get_by:` | Auto-filter by field(s), implies `get?: true` |
| `get_by_identity:` | Auto-filter using a named identity |
| `not_found_error?:` | `false` returns nil instead of raising |
| `exclude_inputs:` | Block specific action inputs from being accepted |
| `default_options:` | Merge defaults into every call's options |

**ANTI-PATTERN**
```elixir
# Wrong: hand-written wrapper that duplicates the changeset boilerplate
def create_user(email, name) do
  MyApp.Accounts.User
  |> Ash.Changeset.for_create(:create, %{email: email, name: name})
  |> Ash.create()
end

# Wrong: wrapper that leaks the resource module to callers
def get_user!(id) do
  MyApp.Accounts.User |> Ash.get!(id)
end
```

---

## 3. Calculations

**WHAT IT IS**
Calculations are derived fields declared on a resource that are computed on demand — either pushed down into the data layer (SQL) for expression calculations, or computed in Elixir for module calculations. They are loaded explicitly and never stored.

**WHEN TO USE**
- Deriving a value from existing attributes (e.g. `full_name` from `first_name` + `last_name`)
- Values that are too expensive to compute on every read but needed by some callers
- Replacing hand-rolled `def full_name(user)` helper functions scattered across the codebase
- Derived values that need to participate in filtering or sorting (expression calculations only)
- Batch computations over many records (module calculations run once per batch, not per record)

**CODE EXAMPLE**
```elixir
# Expression calculation (pushed to SQL)
calculations do
  calculate :full_name, :string, expr(first_name <> " " <> last_name)
  calculate :adult?, :boolean, expr(age >= 18)
end

# Module calculation (Elixir-side)
defmodule MyApp.Accounts.Calculations.GravatarUrl do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:email]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      hash = :md5 |> :crypto.hash(record.email) |> Base.encode16(case: :lower)
      "https://www.gravatar.com/avatar/\#{hash}"
    end)
  end
end

# Declaration on the resource
calculations do
  calculate :gravatar_url, :string, MyApp.Accounts.Calculations.GravatarUrl
end

# Loading calculations
users = MyApp.Accounts.list_users!(load: [:full_name, :gravatar_url], actor: admin)

# Filtering on expression calculations
MyApp.Accounts.list_users!(filter: [adult?: true], actor: admin)
```

**ANTI-PATTERN**
```elixir
# Wrong: scattered helper functions that duplicate logic per callsite
def full_name(%User{} = u), do: "\#{u.first_name} \#{u.last_name}"

# Wrong: computing derived values in the LiveView or controller
assign(socket, :full_name, "\#{user.first_name} \#{user.last_name}")

# Wrong: storing derived values as attributes (stale data risk)
attribute :full_name, :string  # now you must keep it in sync manually
```

---

## 4. Embedded Resources

**WHAT IT IS**
Embedded resources are Ash resources with `data_layer: :embedded` that are stored as structured maps (JSONB in Postgres) inside an attribute of a parent resource. They support the full Ash feature set: actions, validations, calculations, and policies.

**WHEN TO USE**
- Structured data that lives entirely inside a parent record and is never queried independently
- When you need validations, policies, or calculations on the nested data (not just type checking)
- Replacing raw `map` or plain Elixir `@enforce_keys` structs for embedded JSON fields
- Replacing Ecto embedded schemas (`embeds_one`, `embeds_many`)
- Use `Ash.Type.NewType` or `Ash.TypedStruct` instead if you only need type validation without Ash actions/policies

**CODE EXAMPLE**
```elixir
defmodule MyApp.Accounts.Address do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street,  :string, allow_nil?: false, public?: true
    attribute :city,    :string, allow_nil?: false, public?: true
    attribute :country, :string, allow_nil?: false, public?: true
  end

  validations do
    validate present([:street, :city, :country])
  end
end

# Used as an attribute type on the parent resource
defmodule MyApp.Accounts.User do
  use Ash.Resource, domain: MyApp.Accounts, data_layer: AshPostgres.DataLayer

  attributes do
    attribute :address, MyApp.Accounts.Address, public?: true
    # Array of embedded resources
    attribute :past_addresses, {:array, MyApp.Accounts.Address}, public?: true
  end
end
```

**Key constraints:**
- Cannot have aggregates or data-layer-dependent expression calculations
- Set `embed_nil_values?: false` to omit nil keys from stored JSON
- Add a `uuid_v7_primary_key :id` to enable update semantics on array items (avoids destroy+create on every change)

**ANTI-PATTERN**
```elixir
# Wrong: raw map type with no validation
attribute :address, :map  # accepts anything, no validation

# Wrong: separate Ecto embedded schema when the app is already on Ash
defmodule MyApp.Address do
  use Ecto.Schema
  embedded_schema do
    field :street, :string
  end
end

# Wrong: plain struct with ad-hoc validation functions scattered across the codebase
defmodule MyApp.Address do
  @enforce_keys [:street, :city]
  defstruct [:street, :city, :country]
end
```

---

## 5. Notifiers

**WHAT IT IS**
Notifiers are modules that run after an action's database transaction commits, making them the correct place to trigger side effects such as PubSub broadcasts, audit log writes, or analytics events. They implement "at most once" semantics — occasional failure is acceptable.

**WHEN TO USE**
- Broadcasting Phoenix PubSub messages to LiveViews after create/update/destroy
- Emitting telemetry or analytics events after mutations
- Triggering downstream processes (e.g. cache invalidation) that must see committed data
- Replacing `after_action` hooks that contain side effects with network/process calls
- Use Oban or Reactor instead when you need guaranteed delivery or saga semantics

**CODE EXAMPLE**
```elixir
# Built-in PubSub notifier
defmodule MyApp.Tweets.Tweet do
  use Ash.Resource,
    domain: MyApp.Tweets,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module MyApp.PubSub
    prefix "tweet"
    publish_all :create, ["created"]
    publish_all :update, ["updated", [:id]]
    publish_all :destroy, ["destroyed", [:id]]
  end
end

# Custom notifier
defmodule MyApp.Notifiers.AuditLog do
  use Ash.Notifier

  def notify(%Ash.Notifier.Notification{
        resource: resource,
        action: %{type: action_type},
        data: record,
        actor: actor
      }) do
    MyApp.Audit.log(resource, action_type, record.id, actor && actor.id)
  end
end

# Attach as simple_notifier (no extension dependency)
use Ash.Resource, simple_notifiers: [MyApp.Notifiers.AuditLog]

# Per-action notifier
create :create do
  notifiers [MyApp.Notifiers.AuditLog]
end
```

**Returning notifications for manual dispatch (multi-operation transactions):**
```elixir
{:ok, record, notifications} = MyApp.Tweets.create_tweet(attrs, return_notifications?: true)
Ash.Notifier.notify(notifications)
```

**ANTI-PATTERN**
```elixir
# Wrong: side effects inside after_action hooks
change fn changeset, _ ->
  Ash.Changeset.after_action(changeset, fn _cs, record ->
    Phoenix.PubSub.broadcast(MyApp.PubSub, "tweets", {:created, record})  # runs inside transaction
    {:ok, record}
  end)
end

# Wrong: broadcasting from the LiveView after calling the domain function
{:ok, tweet} = MyApp.Tweets.create_tweet!(attrs)
Phoenix.PubSub.broadcast(MyApp.PubSub, "tweets", {:created, tweet})  # not co-located with the action
```

---

## 6. Validations

**WHAT IT IS**
Validations are DSL-declared rules on resources that run during action execution and can only pass or add errors — they cannot modify the changeset. They can be scoped to specific actions or declared globally across multiple action types.

**WHEN TO USE**
- Enforcing field constraints that are not expressible as attribute-level constraints (e.g. conditional presence, cross-field rules)
- Replacing ad-hoc `validate_*` functions called manually before domain actions
- Adding conditional validation with `where:` clauses
- Sharing validation logic across multiple actions without duplicating it
- Use `atomic/3` for database-level constraint enforcement

**Built-in validators:**

| Validator | Purpose |
|---|---|
| `present/1` | Field must be non-nil/non-empty |
| `absent/1` | Field must be nil/absent |
| `compare/2` | Numeric/date comparison (`greater_than`, `less_than`, etc.) |
| `match/2` | Regex match |
| `one_of/2` | Value in allowed list |
| `string_length/2` | Min/max string length |
| `argument_equals/2` | Argument equals a value |
| `confirm/2` | Two fields match (e.g. password + confirmation) |
| `negate/1` | Inverts another validation |

**CODE EXAMPLE**
```elixir
# Global validations (run on specified action types)
validations do
  validate present([:email, :name]) do
    on [:create]
  end

  validate compare(:age, greater_than_or_equal_to: 18) do
    on [:create, :update]
    message "must be 18 or older"
  end

  # Conditional: only validate last_name if first_name is present
  validate present(:last_name) do
    where [present(:first_name)]
    message "required when first_name is provided"
  end
end

# Action-scoped validation
actions do
  create :register do
    validate match(:email, ~r/@/)
    validate confirm(:password, :password_confirmation)
  end
end

# Custom validation module
defmodule MyApp.Validations.SlugFormat do
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :slug) do
      nil -> :ok
      slug ->
        if Regex.match?(~r/^[a-z0-9-]+$/, slug),
          do: :ok,
          else: {:error, field: :slug, message: "must be lowercase letters, numbers, and hyphens only"}
    end
  end
end

validations do
  validate MyApp.Validations.SlugFormat
end
```

**ANTI-PATTERN**
```elixir
# Wrong: validation logic in the LiveView or controller before calling the domain
def handle_event("save", %{"user" => params}, socket) do
  if String.contains?(params["email"], "@") do
    MyApp.Accounts.create_user(params)
  else
    {:noreply, assign(socket, error: "invalid email")}
  end
end

# Wrong: validation in a change (changes can modify; use validate for pure checks)
change fn changeset, _ ->
  if Ash.Changeset.get_attribute(changeset, :age) < 18 do
    Ash.Changeset.add_error(changeset, field: :age, message: "too young")
  else
    changeset
  end
end
```

---

## 7. Aggregates

**WHAT IT IS**
Aggregates are declared summary computations over related records (count, sum, list, etc.) that are pushed down to the data layer as efficient SQL subqueries. They are loaded on demand and can be used in filters and sorts.

**WHEN TO USE**
- Counting related records (e.g. `post.comment_count`)
- Summing a field across a relationship (e.g. `order.total_line_items_cost`)
- Checking existence of related records matching a condition (`exists`)
- Collecting related field values into a list (e.g. `user.tag_names`)
- Replacing `Repo.aggregate/3` calls or N+1 join queries in service modules
- Use calculations instead when you need complex Elixir logic that aggregates can't express

**Aggregate types:**

| Type | Requires `field:` | Purpose |
|---|---|---|
| `count` | No | Count matching related records |
| `exists` | No | Boolean — any matching related records? |
| `first` | Yes | First value of a field (add `sort:` to control order) |
| `sum` | Yes | Sum of a numeric field |
| `list` | Yes | All values of a field as a list |
| `max` | Yes | Maximum field value |
| `min` | Yes | Minimum field value |
| `avg` | Yes | Average of a numeric field |
| `custom` | Yes | User-defined SQL aggregate |

**CODE EXAMPLE**
```elixir
aggregates do
  # Count with filter
  count :published_post_count, :posts do
    filter expr(published == true)
  end

  # Existence check
  exists :has_admin_post, :posts do
    filter expr(is_admin_post == true)
  end

  # Sum
  sum :total_spend, :orders, :amount do
    filter expr(status == :completed)
  end

  # First (with explicit sort)
  first :latest_post_title, :posts, :title do
    sort inserted_at: :desc
  end

  # List of related values
  list :tag_names, :tags, :name do
    sort name: :asc
  end
end

# Loading aggregates
user = MyApp.Accounts.get_user!(id, load: [:published_post_count, :tag_names], actor: admin)

# Filtering on an aggregate
MyApp.Accounts.list_users!(
  filter: [published_post_count: [greater_than: 5]],
  actor: admin
)

# Sorting on an aggregate
MyApp.Accounts.list_users!(sort: [total_spend: :desc], actor: admin)
```

**ANTI-PATTERN**
```elixir
# Wrong: N+1 manual count in a domain function
def enrich_users(users) do
  Enum.map(users, fn user ->
    count = MyApp.Posts |> Ash.Query.filter(author_id: user.id) |> Ash.count!()
    Map.put(user, :post_count, count)
  end)
end

# Wrong: raw Ecto aggregate bypassing Ash
def post_count(user_id) do
  Repo.aggregate(MyApp.Posts.Post, :count, :id, author_id: user_id)
end

# Wrong: loading all related records just to count them
user = MyApp.Accounts.get_user!(id, load: :posts)
count = length(user.posts)
```

---

*Generated from hexdocs.pm/ash documentation. Use as a checklist when auditing resources, domains, and service modules for Ash anti-patterns.*
