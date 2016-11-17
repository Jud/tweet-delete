require 'twitter'
require "json"

USERNAME = ENV['USERNAME']
DAYS_SAVED = ENV['TTL']

# Setup the Twitter client with credentials
client = Twitter::REST::Client.new do |config|
  config.consumer_key = ENV['CONSUMER_KEY']
  config.consumer_secret = ENV['CONSUMER_SECRET']
  config.access_token = ENV['ACCESS_TOKEN']
  config.access_token_secret = ENV['ACCESS_TOKEN_SECRET']
end

def collect_with_max_id(collection=[], max_id=nil, &block)
  response = yield(max_id)
  collection += response
  response.empty? ? collection.flatten : collect_with_max_id(collection, response.last.id - 1, &block)
end

def client.get_all_tweets(user)
  collect_with_max_id do |max_id|
    options = {count: 200, include_rts: true}
    options[:max_id] = max_id unless max_id.nil?
    begin
      user_timeline(user, options)
    rescue Twitter::Error::TooManyRequests => error
      sleep error.rate_limit.reset_in + 1
      retry
    end
  end
end

def client.get_all_favorites(user)
  collect_with_max_id do |max_id|
    options = { count: 100 }
    options[:max_id] = max_id unless max_id.nil?
    begin
      favorites(user, options)
    rescue Twitter::Error::TooManyRequests => error
      sleep error.rate_limit.reset_in + 1
      retry
    end
  end
end

while true
  # An array of tweet ids by USERNAME that have
  # also been favorited by USERNAME (mark to keep)
  favorite_ids = []

  client.get_all_favorites(USERNAME).each do |tweet|
    # If you favorited your own tweet, we'll keep it around
    # and we need to keep the favorite around as well.
    if tweet.user.screen_name.downcase == USERNAME.downcase
      favorite_ids << tweet.id
    else
      if (Time.now.to_i - tweet.created_at.to_i) / (24 * 60 * 60) > DAYS_SAVED
        begin
          client.unfavorite(tweet.id)
        rescue Twitter::Error::TooManyRequests => error
          sleep error.rate_limit.reset_in + 1
          retry
        end
      end
    end
  end

  client.get_all_tweets(USERNAME).each do |tweet|
    if !favorite_ids.include? tweet.id
      if (Time.now.to_i - tweet.created_at.to_i) / (24 * 60 * 60) > DAYS_SAVED
        begin
          client.destroy_tweet tweet.id
        rescue Twitter::Error::TooManyRequests => error
          sleep error.rate_limit.reset_in + 1
          retry
        end
      end
    end
  end

  puts 'Sleeping....'
  sleep 12*60*60
end
