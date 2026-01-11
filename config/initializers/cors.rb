# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # In development/test: allow common localhost ports
    # In production: only allow origins specified in ALLOWED_ORIGINS environment variable
    origins Rails.env.production? ?
      ENV.fetch("ALLOWED_ORIGINS", "").split(",") :
      [
        "http://localhost:3000",
        "http://localhost:3001",
        "http://localhost:5173",
        "http://localhost:5174",
        "http://localhost:8080",
        /\Ahttp:\/\/localhost:\d+\z/  # Regex to match any localhost port
      ]

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true
  end
end
