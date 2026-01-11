# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_10_22_143335) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "rss_feed_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "rss_feed_id", null: false
    t.string "title"
    t.string "link"
    t.text "description"
    t.text "content"
    t.string "guid"
    t.string "image"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["description"], name: "index_rss_feed_items_on_description"
    t.index ["guid"], name: "index_rss_feed_items_on_guid"
    t.index ["rss_feed_id"], name: "index_rss_feed_items_on_rss_feed_id"
    t.index ["title"], name: "index_rss_feed_items_on_title"
  end

  create_table "rss_feed_urls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["url"], name: "index_rss_feed_urls_on_url", unique: true
  end

  create_table "rss_feeds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "rss_feed_url_id", null: false
    t.string "title", null: false
    t.text "description", null: false
    t.string "link", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["rss_feed_url_id"], name: "index_rss_feeds_on_rss_feed_url_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "rss_feed_items", "rss_feeds"
  add_foreign_key "rss_feeds", "rss_feed_urls"
end
