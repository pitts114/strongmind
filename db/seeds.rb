# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Seed RSS Feed data from fixture
fixture_path = Rails.root.join("spec", "fixtures", "nasa_rss_feed.xml")
xml_content = File.read(fixture_path)

# Parse the XML using RssFeedParserService
parser = RssFeedParserService.new
parsed_data = parser.call(xml_content)

# Create or find the RSS feed URL
rss_feed_url = RssFeedUrl.find_or_create_by!(url: "https://www.nasa.gov/feed/")

# Create the RSS feed using CreateRssFeedService
create_feed_service = CreateRssFeedService.new
rss_feed = create_feed_service.call(
  rss_feed_url_id: rss_feed_url.id,
  title: parsed_data[:feed][:title],
  description: parsed_data[:feed][:description],
  link: parsed_data[:feed][:link]
)

# Create RSS feed items using CreateRssFeedItemService
create_item_service = CreateRssFeedItemService.new
parsed_data[:items].each do |item|
  create_item_service.call(
    rss_feed_id: rss_feed.id,
    title: item[:title],
    link: item[:link],
    description: item[:description],
    guid: item[:guid],
    image: item[:image],
    content: item[:content]
  )
end

puts "Successfully seeded #{parsed_data[:items].count} RSS feed items from NASA RSS feed"
