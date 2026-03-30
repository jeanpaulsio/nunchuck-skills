---
name: rails-patterns
description: Deep reference for Ruby on Rails 8 patterns -- Hotwire/Turbo 8 morphing, Sidekiq + Solid Queue, service objects, minitest + fixtures, ActiveRecord, security, deployment with Kamal. Focused on Rails 8-specific and non-obvious patterns.
origin: claude-rails (audited, rebuilt, and expanded for nunchuck-skills)
---

# Ruby on Rails Patterns

Production patterns for Rails 8 applications. Focused on what's non-obvious, Rails 8-specific, or commonly gotten wrong. Generic Rails advice that any model already knows is excluded.

> To run an automated review, use the **rails-reviewer** agent or `/rails-review`.

---

## Table of Contents

1. [Hotwire / Turbo 8](#hotwire--turbo-8)
2. [Service Objects](#service-objects)
3. [Controller Patterns](#controller-patterns)
4. [Model Patterns](#model-patterns)
5. [Background Jobs (Sidekiq + Solid Queue)](#background-jobs)
6. [Authentication (Rails 8 Generator)](#authentication)
7. [Testing (Minitest + Fixtures)](#testing)
8. [Database & Migrations](#database--migrations)
9. [Deployment (Kamal 2)](#deployment)
10. [ERB Patterns](#erb-patterns)
11. [Rails 8 Features](#rails-8-features)
12. [Quick Reference](#quick-reference)

---

## Hotwire / Turbo 8

### Decision Hierarchy

Before reaching for JavaScript, exhaust simpler options:

```
HTML (links, forms, semantic elements)
  → CSS (transitions, animations, :has(), :target)
    → Turbo Drive (SPA-like navigation for free)
      → Turbo Frames (partial page updates)
        → Turbo Streams (targeted DOM mutations)
          → Turbo 8 Morphing (full-page refresh with diff)
            → Stimulus (lightweight JS behavior)
              → Custom JS (only when nothing above works)
```

### Turbo 8 Morphing (Page Refreshes)

The biggest Hotwire change. Instead of targeted Turbo Stream DOM operations, the server re-renders the full page and morphs only the changed elements.

**Setup (in layout head):**
```html
<meta name="turbo-refresh-method" content="morph">
<meta name="turbo-refresh-scroll" content="preserve">
```

**Model:**
```ruby
class Board < ApplicationRecord
  broadcasts_refreshes
end
```

**View subscription:**
```erb
<%= turbo_stream_from @board %>
```

**Controller stays vanilla (no turbo_stream format):**
```ruby
def create
  @column = @board.columns.create!(column_params)
  redirect_to @board
end
```

**Why this is better than targeted broadcasts:**
- No coupling between models and views via DOM IDs
- No separate `*.turbo_stream.erb` templates to maintain
- Solves the session context problem: each client fetches its own content, so you can't accidentally expose hidden data
- Automatic debouncing of sequential refreshes
- `data-turbo-permanent` preserves UI state (open menus, form input) during morphs

**When to still use Turbo Streams:** Client-specific targeted updates (flash messages for one user), or when full-page re-render is too expensive.

### Turbo Frame Gotchas

```erb
<%# Page A: link inside a frame %>
<%= turbo_frame_tag "edit_form" do %>
  <%= link_to "Edit", edit_post_path(@post) %>
<% end %>

<%# Page B (edit_post_path): MUST have matching frame tag %>
<%= turbo_frame_tag "edit_form" do %>
  <%= form_with model: @post do |f| %>
    ...
  <% end %>
<% end %>

<%# If the target page doesn't have a matching turbo_frame_tag,
    the frame renders EMPTY with no error. This is the #1 Turbo debugging issue. %>
```

### Status Codes Matter for Turbo

```ruby
# Turbo re-renders forms on validation failure.
# It ONLY re-renders if the response status is 422 (unprocessable_entity).
def create
  @post = Post.new(post_params)
  if @post.save
    redirect_to @post, status: :see_other  # 303 required for DELETE/POST redirects
  else
    render :new, status: :unprocessable_entity  # 422 required for Turbo form re-render
  end
end
```

Without `:unprocessable_entity`, Turbo treats the response as a full page navigation and your form errors don't appear. Without `:see_other` on redirects after POST/DELETE, Turbo replays the POST instead of following the redirect.

---

## Service Objects

### The Callable Pattern

```ruby
class Users::Register
  def initialize(params:, ip_address: nil)
    @params = params
    @ip_address = ip_address
  end

  def call
    user = User.new(@params)
    return Result.failure(user.errors) unless user.save

    UserMailer.welcome(user).deliver_later
    AuditLog.record(action: "register", user: user, ip: @ip_address)
    Result.success(user)
  end
end

# Simple Result object
Result = Data.define(:success?, :value, :errors) do
  def self.success(value) = new(success?: true, value: value, errors: nil)
  def self.failure(errors) = new(success?: false, value: nil, errors: errors)
end

# Usage in controller
result = Users::Register.new(params: user_params, ip_address: request.remote_ip).call
if result.success?
  redirect_to dashboard_path
else
  @user = User.new(user_params)
  @user.errors.merge!(result.errors)
  render :new, status: :unprocessable_entity
end
```

### When NOT to Use a Service

Don't wrap single ActiveRecord calls just for architecture:

```ruby
# OVER-ENGINEERED
class Posts::Find
  def initialize(id:) = @id = id
  def call = Post.find(@id)
end

# JUST DO THIS
Post.find(params[:id])
```

Use services when: business logic beyond CRUD, multiple models coordinate, side effects (email, audit, webhooks), or the logic needs independent testing.

### File Organization

```
app/services/
├── users/
│   ├── register.rb
│   ├── deactivate.rb
│   └── export_data.rb
├── orders/
│   ├── process.rb
│   ├── refund.rb
│   └── calculate_total.rb
└── external/
    ├── stripe_sync.rb
    └── email_provider.rb
```

Namespace by domain, not by type (`Users::Register` not `RegisterUserService`).

---

## Controller Patterns

### CRUD-Only Actions (37signals Style)

Only 7 REST actions. Custom operations become new resources:

```ruby
# BAD: custom actions
class PostsController < ApplicationController
  def archive = ...
  def publish = ...
  def feature = ...
end

# GOOD: new resources
class Posts::ArchivalsController < ApplicationController
  def create
    @post = Post.find(params[:post_id])
    @post.archive!
    redirect_to @post, status: :see_other
  end
end
```

### `params.expect` (Rails 8)

Replaces `require.permit`. Returns 400 on malformed input instead of 500:

```ruby
# Old (500 on malformed params)
params.require(:user).permit(:name, :email)

# New (400 on malformed params)
params.expect(user: [:name, :email])

# Nested arrays of hashes (note double brackets)
params.expect(post: [:title, categories: [[:name]]])
```

---

## Model Patterns

### `normalizes` -- Automatic Attribute Normalization

```ruby
class User < ApplicationRecord
  normalizes :email, with: -> (e) { e.strip.downcase }
  normalizes :phone, with: -> (p) { p.delete("^0-9").delete_prefix("1") }
end

user.email = "  FOO@BAR.COM  "
user.email  # => "foo@bar.com"

# Non-obvious: normalizes applies to QUERIES too
User.find_by(email: "FOO@bar.com")
# SQL: WHERE email = 'foo@bar.com' -- normalized before query
```

### `generates_token_for` -- Purpose-Built Tokens

```ruby
class User < ApplicationRecord
  has_secure_password

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_confirmation, expires_in: 24.hours do
    email
  end
end

token = user.generate_token_for(:password_reset)
user = User.find_by_token_for(:password_reset, token) # nil if expired or password changed
```

The block value is embedded in the token. If the tracked attribute changes (password_salt after password change), the token auto-invalidates.

### Dual Validation (Model + DB Constraint)

```ruby
class User < ApplicationRecord
  validates :email, uniqueness: true  # Nice error message for users
end

# Migration: DB constraint catches race conditions that model validation can't
add_index :users, :email, unique: true
```

Model-level validation is not thread-safe. Two requests checking uniqueness simultaneously can both pass validation. The database constraint is the last line of defense.

### Enum with Explicit Values

```ruby
class Order < ApplicationRecord
  enum :status, {
    pending: "pending",
    processing: "processing",
    shipped: "shipped",
    delivered: "delivered",
    cancelled: "cancelled",
  }
end

# String values (not integers) are readable in DB queries and don't break if reordered
```

### Callbacks: Only for Model-Intrinsic Behavior

```ruby
# GOOD: callbacks for data integrity
class Post < ApplicationRecord
  before_validation :generate_slug, if: -> { slug.blank? }
  before_destroy :ensure_not_published

  private
  def generate_slug = self.slug = title.parameterize
  def ensure_not_published
    throw(:abort) if published?
  end
end

# BAD: callbacks for business logic (hidden, untestable, order-dependent)
class Post < ApplicationRecord
  after_create :send_notification     # Use service object
  after_update :sync_to_search_index  # Use job
  after_destroy :update_user_stats    # Use service object
end
```

### Strict Loading (Catch N+1 in Dev)

```ruby
# config/environments/development.rb
config.active_record.strict_loading_by_default = true

# Now accessing un-preloaded associations raises immediately:
posts = Post.all
posts.first.comments  # RAISES ActiveRecord::StrictLoadingViolationError

# Fix: preload explicitly
posts = Post.includes(:comments).all
posts.first.comments  # works
```

---

## Background Jobs

### Sidekiq

#### Idempotent Job Design

The most important pattern. Sidekiq retries failed jobs 25 times by default. If your job isn't idempotent, retries create duplicates.

```ruby
# BAD: not idempotent - retries create duplicates
class ProcessPaymentJob
  include Sidekiq::Job

  def perform(order_id)
    order = Order.find(order_id)
    PaymentGateway.charge(order.amount) # retried = double charge!
    order.update!(status: :paid)
  end
end

# GOOD: check-before-act
class ProcessPaymentJob
  include Sidekiq::Job

  def perform(order_id)
    order = Order.find(order_id)
    return if order.paid? # already processed

    PaymentGateway.charge(order.amount, idempotency_key: order_id)
    order.update!(status: :paid)
  end
end
```

#### Use `find_by` with Early Return, Not `find`

```ruby
# BAD: raises RecordNotFound, retries 25 times, fills your error tracker
def perform(user_id)
  user = User.find(user_id) # deleted between enqueue and execution
  user.send_welcome_email
end

# GOOD: silently skip deleted records
def perform(user_id)
  user = User.find_by(id: user_id)
  return unless user

  user.send_welcome_email
end
```

#### Handle Exhausted Retries

```ruby
class ImportJob
  include Sidekiq::Job
  sidekiq_options retry: 5

  sidekiq_retries_exhausted do |job, exception|
    Rails.error.report(exception, context: {
      job_class: job["class"],
      job_id: job["jid"],
      args: job["args"],
    })
    # Update the record so the UI can show the failure
    Import.find_by(id: job["args"].first)&.update!(status: :failed)
  end

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import
    # ... do the work
  end
end
```

#### Testing Job Logic Directly

Test the `perform` method, not Sidekiq infrastructure:

```ruby
test "processes payment" do
  order = orders(:unpaid)
  ProcessPaymentJob.new.perform(order.id)
  assert_equal "paid", order.reload.status
end

test "skips already paid orders" do
  order = orders(:paid)
  ProcessPaymentJob.new.perform(order.id)
  # assert no duplicate charge - PaymentGateway not called
end

test "handles deleted orders" do
  ProcessPaymentJob.new.perform(SecureRandom.uuid)
  # no error raised
end
```

#### Scheduling

```ruby
# Immediate
ImportJob.perform_async(import.id)

# Delayed
ReminderJob.perform_in(1.hour, user.id)

# Scheduled
ReportJob.perform_at(Date.tomorrow.noon, account.id)
```

For recurring jobs, use `sidekiq-cron` or `sidekiq-scheduler`:

```yaml
# config/sidekiq_cron.yml
daily_summary:
  cron: "0 9 * * *"
  class: DailySummaryJob
  queue: mailers
```

### Solid Queue (Rails 8 Default)

If you're on Rails 8 defaults instead of Sidekiq:

#### Key Differences from Sidekiq

- **No retry by default.** You must configure `retry_on` explicitly in your job classes. Sidekiq retries 25 times by default.
- Uses database tables instead of Redis for job storage
- Built-in concurrency controls (Sidekiq needs `sidekiq-unique-jobs` gem for this):

```ruby
class InvoiceExportJob < ApplicationJob
  limits_concurrency to: 1, key: -> (account_id) { "invoice_export_#{account_id}" }
  retry_on StandardError, wait: :exponentially_longer, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(account_id)
    # Only one export per account at a time
  end
end
```

#### Recurring Jobs

```yaml
# config/recurring.yml
production:
  daily_summary:
    class: DailySummaryJob
    schedule: every day at 9am
    queue: mailers
```

---

## Authentication

### The Generator

```bash
rails generate authentication
# Generates: User model, Session model, SessionsController,
# PasswordsController, password reset mailer, Current class
```

**What it does NOT generate:** Registration. You must build signup yourself:

```ruby
class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def create
    @user = User.new(params.expect(user: [:email_address, :password, :password_confirmation]))
    if @user.save
      start_new_session_for @user
      redirect_to root_url
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

### Built-in Rate Limiting

```ruby
class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_url, alert: "Try again later." }
end
```

### Current Attributes

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :user, to: :session, allow_nil: true
end

# Available everywhere in the request: Current.user
# Does NOT work in background jobs (no request context)
```

**Use sparingly.** Limit to 2-3 top-level attributes (user, session, account). If Current has 10 attributes, it's a god object.

---

## Testing

### Fixtures Over Factories

```yaml
# test/fixtures/users.yml
alice:
  email_address: alice@example.com
  password_digest: <%= BCrypt::Password.create("password") %>

bob:
  email_address: bob@example.com
  password_digest: <%= BCrypt::Password.create("password") %>
```

**Why fixtures:** Pre-built database state is faster than runtime construction. No factory chain explosions. Tests see the same data shape every time.

### What to Test (Decision Table)

| Layer | Test Type | What to Assert |
|-------|-----------|---------------|
| Model | Unit | Validations, scopes, methods |
| Service | Unit | Business logic, return values, side effects |
| Controller | Request | Status codes, redirects, response body |
| View | System (Capybara) | Critical user flows only |
| Job | Unit | Job logic directly (not Sidekiq/SQ infrastructure) |

### Request Tests with Turbo Streams

```ruby
test "create appends via turbo stream" do
  post messages_url, params: { message: { body: "Hello" } }, as: :turbo_stream
  assert_response :success
  assert_turbo_stream action: "append", target: "messages" do
    assert_select "template p", text: "Hello"
  end
end
```

### Broadcast Assertions

```ruby
test "model broadcasts on create" do
  assert_turbo_stream_broadcasts "messages" do
    Message.create!(body: "Hello")
  end
end
```

### Testing Service Objects

```ruby
test "registers user and sends welcome email" do
  assert_enqueued_emails 1 do
    result = Users::Register.new(
      params: { email_address: "new@example.com", password: "secure123" }
    ).call

    assert result.success?
    assert_equal "new@example.com", result.value.email_address
  end
end

test "fails with invalid params" do
  result = Users::Register.new(params: { email_address: "" }).call
  refute result.success?
  assert_includes result.errors.full_messages, "Email address can't be blank"
end
```

---

## Database & Migrations

### strong_migrations (Zero-Downtime Safety)

| Dangerous | Why | Safe |
|-----------|-----|------|
| `remove_column` | ActiveRecord caches columns | Add `self.ignored_columns`, deploy, then remove |
| `add_index` | Blocks writes | `add_index :t, :col, algorithm: :concurrently` with `disable_ddl_transaction!` |
| `add_foreign_key` | Blocks reads/writes | Add with `validate: false`, validate separately |
| `change_column` type | Rewrites table | New column, backfill, swap, drop old |
| Backfill in same migration | Table locked | Separate migration with `disable_ddl_transaction!` |

### Safe Backfill Pattern

```ruby
class BackfillStatusColumn < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    User.unscoped.in_batches(of: 10_000) do |relation|
      relation.where(status: nil).update_all(status: "active")
      sleep(0.01) # throttle to reduce DB load
    end
  end
end
```

### Strict Locals in Partials (Rails 7.1+)

```erb
<%# app/views/posts/_post.html.erb %>
<%# locals: (post:, show_author: true) -%>

<h2><%= post.title %></h2>
<% if show_author %>
  <p>By <%= post.author.name %></p>
<% end %>
```

Calling `render partial: "post", locals: { post: @post, extra: "oops" }` raises. The partial explicitly declares what it accepts.

---

## Deployment

### Kamal 2 Request Flow

```
User -> Cloudflare (optional) -> kamal-proxy (SSL/routing) -> Thruster (compression) -> Puma -> Rails
```

Thruster is included in Rails 8 Dockerfile by default. It replaces Nginx for HTTP/2, gzip/brotli, and asset caching.

### Key deploy.yml Patterns

```yaml
service: myapp
image: myapp

servers:
  web:
    hosts: [203.0.113.10]
  job:
    hosts: [203.0.113.10]
    cmd: bin/jobs start  # Separate container for Solid Queue

proxy:
  ssl: true
  hosts: [myapp.com]

asset_path: /rails/public/assets  # Prevents 404s during deploy

volumes:
  - "myapp_storage:/rails/storage"  # Mandatory for SQLite/ActiveStorage
```

### Non-Obvious Kamal Gotchas

- **`asset_path`** is critical: without it, users who loaded a page before deploy get 404s for JS/CSS (old asset fingerprints disappear)
- Run Solid Queue in a **separate container** (`cmd: bin/jobs start`) so runaway jobs can't starve web requests
- With Cloudflare, use **"Full" SSL mode**, not "Flexible" (causes infinite redirect loops)
- Set `config.assume_ssl = true` in production.rb when behind proxy chains
- `SECRET_KEY_BASE_DUMMY=1` in Dockerfile lets asset precompilation run without real secrets
- Docker entrypoint runs `bin/rails db:prepare` automatically on web start

---

## ERB Patterns

### Presenter Pattern

```ruby
class PostPresenter < SimpleDelegator
  def status_badge
    case status
    when "published" then tag.span("Published", class: "badge badge-green")
    when "draft" then tag.span("Draft", class: "badge badge-gray")
    end
  end

  def reading_time
    words = body.split.size
    minutes = (words / 200.0).ceil
    "#{minutes} min read"
  end

  private
  def tag = ActionController::Base.helpers
end

# Usage in view
<%= PostPresenter.new(@post).status_badge %>
```

---

## Rails 8 Features

### `delegated_type` (Alternative to STI)

```ruby
class Entry < ApplicationRecord
  delegated_type :entryable, types: %w[Message Comment]
  delegate :title, to: :entryable
end

class Message < ApplicationRecord
  include Entryable
  def title = subject
end

# Generated methods: Entry.messages, @entry.message?, @entry.message
```

Avoids table bloat from STI (separate tables per subtype).

### `rate_limit`

```ruby
class PasswordsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_password_url, alert: "Too many attempts." }
end
```

### Solid Cache

Database-backed cache using FIFO eviction (not LRU like Redis).

**When to use:** Large cached values, moderate read rates, want to eliminate Redis.
**When NOT to use:** Sub-millisecond latency needed, DB is already the bottleneck, cache churn is very high.

**Gotcha:** FIFO means frequently-accessed-but-old entries get evicted before rarely-accessed-but-new ones. The opposite of what you want for hot-path caching.

---

## Quick Reference

| Mistake | Fix |
|---------|-----|
| Missing `status: :unprocessable_entity` on form error | Turbo won't re-render the form without 422 |
| Missing `status: :see_other` on POST/DELETE redirect | Turbo replays the POST instead of following |
| Missing matching `turbo_frame_tag` on target page | Frame renders empty with no error |
| `after_create` for business logic | Use service object |
| `Model.find(params[:id])` unscoped | Scope to current user: `current_user.posts.find(...)` |
| `permit!` on params | Never. Whitelist every field explicitly |
| Integer enum values | Use string values: `enum :status, { active: "active" }` |
| Non-idempotent Sidekiq jobs | Check-before-act pattern, `find_by` with early return |
| No `retry_on` in ApplicationJob (Solid Queue) | Solid Queue doesn't retry by default, unlike Sidekiq |
| `add_index` without `algorithm: :concurrently` | Blocks writes on large tables |
| `remove_column` without `ignored_columns` | Crashes on deploy until column is removed |
| Module-scope store in Wrapper/Layout | Cross-request data leaks during SSR |
| `config.assume_ssl` not set behind proxy | Rails generates HTTP URLs instead of HTTPS |
